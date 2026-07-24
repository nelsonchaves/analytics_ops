# frozen_string_literal: true

require "json"
require "mcp"

module AnalyticsOps
  # Strictly read-only MCP bridge for ChatGPT, Codex, Claude, and other MCP clients.
  class MCPServer
    PROFILE = /\A[A-Za-z][A-Za-z0-9_]{0,63}\z/
    CONNECTION = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/
    CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/
    PROFILE_JSON_PATTERN = "^[A-Za-z][A-Za-z0-9_]{0,63}$"
    CONNECTION_JSON_PATTERN = "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
    READ_ONLY_ANNOTATIONS = {
      title: "Read Google Analytics",
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: true
    }.freeze
    PROFILE_INPUT = {
      type: "object",
      additionalProperties: false,
      properties: {
        profile: {
          type: "string",
          pattern: PROFILE_JSON_PATTERN,
          description: "Optional Analytics Ops profile. Uses the locally selected profile when omitted."
        }
      }
    }.freeze
    PERIOD_PROPERTIES = {
      last_days: {
        type: "integer",
        minimum: 1,
        maximum: Reports::Period::MAX_DAYS,
        description: "Optional number of complete days ending yesterday."
      },
      start_date: {
        type: "string",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$",
        description: "Optional YYYY-MM-DD start date; requires end_date."
      },
      end_date: {
        type: "string",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$",
        description: "Optional YYYY-MM-DD end date; requires start_date."
      },
      compare: {
        type: "boolean",
        description: "Also include the equally long preceding period."
      }
    }.freeze
    OBJECT_OUTPUT = { type: "object" }.freeze
    ARRAY_OUTPUT = { type: "array", items: { type: "object" } }.freeze
    STANDARD_REPORTS = (
      Reports::Catalog.names.select { |name| Reports::Catalog.fetch(name).kind == "standard" } +
      Reports::Catalog.aliases.keys
    ).sort.freeze

    attr_reader :server

    def initialize(config: "config/analytics_ops.yml", profile: nil, connection: nil,
                   store: ServiceAccount::Store.new, workspace_loader: nil, connection_loader: nil,
                   service_account_loader: nil, portfolio_loader: nil,
                   transport: :grpc, timeout: nil, logger: nil)
      @config = config
      @profile = profile
      @connection = connection
      @store = store
      @workspace_loader = workspace_loader || method(:load_workspace)
      @connection_loader = connection_loader || method(:load_connection)
      @service_account_loader = service_account_loader || ServiceAccount.method(:load)
      @portfolio_loader = portfolio_loader || method(:load_portfolio)
      @transport = transport
      @timeout = timeout
      @logger = logger
      validate_defaults!
      @server = build_server
      define_tools
    end

    def start
      ::MCP::Server::Transports::StdioTransport.new(server).open
    end

    private

    def build_server
      configuration = ::MCP::Configuration.new(
        validate_tool_call_arguments: true,
        validate_tool_call_results: true
      )
      ::MCP::Server.new(
        name: "analytics_ops",
        title: "Analytics Ops",
        version: AnalyticsOps::VERSION,
        description: "Read Google Analytics 4 configuration and reports safely.",
        website_url: "https://github.com/nelsonchaves/analytics_ops",
        instructions: "Every Analytics Ops tool is strictly read-only. Use these tools to inspect GA4 properties, " \
                      "configuration drift, reports, and realtime events. No tool can create a plan, apply a change, " \
                      "or modify Google Analytics. Never claim that a tool changed GA4.",
        configuration:
      )
    end

    def define_tools
      define_local_tools
      define_google_tools
      define_reporting_tools
    end

    def define_local_tools
      owner = self
      server.define_tool(
        name: "analytics_list_profiles",
        title: "List Analytics Profiles",
        description: "Use this to list locally configured GA4 property profiles and see which one is selected.",
        input_schema: { type: "object", additionalProperties: false },
        output_schema: ARRAY_OUTPUT,
        annotations: READ_ONLY_ANNOTATIONS
      ) do |server_context: nil|
        owner.__send__(:respond, server_context) { owner.__send__(:profile_rows) }
      end

      server.define_tool(
        name: "analytics_list_connections",
        title: "List Analytics Connections",
        description: "Use this to list saved Google connection names and availability. " \
                     "Credential paths are never returned.",
        input_schema: { type: "object", additionalProperties: false },
        output_schema: ARRAY_OUTPUT,
        annotations: READ_ONLY_ANNOTATIONS
      ) do |server_context: nil|
        owner.__send__(:respond, server_context) { owner.__send__(:connection_rows) }
      end
    end

    def define_google_tools
      define_properties_tool
      define_profile_tool(
        "analytics_doctor",
        "Check Analytics Setup",
        "Use this to verify credentials, API access, property access, and client compatibility.",
        OBJECT_OUTPUT
      ) { |profile| workspace(profile).doctor }
      define_snapshot_tool
      define_profile_tool(
        "analytics_audit",
        "Audit GA4 Configuration",
        "Use this to compare desired and remote GA4 configuration. It reports drift but cannot save or apply a plan.",
        OBJECT_OUTPUT
      ) { |profile| workspace(profile).audit }
    end

    def define_properties_tool
      owner = self
      server.define_tool(
        name: "analytics_list_properties",
        title: "List Accessible GA4 Properties",
        description: "Use this to discover GA4 accounts and properties accessible through a saved Google connection.",
        input_schema: {
          type: "object",
          additionalProperties: false,
          properties: {
            connection: {
              type: "string",
              pattern: CONNECTION_JSON_PATTERN,
              description: "Optional saved connection name."
            }
          }
        },
        output_schema: ARRAY_OUTPUT,
        annotations: READ_ONLY_ANNOTATIONS
      ) do |connection: nil, server_context: nil|
        owner.__send__(:respond, server_context) do
          owner.__send__(:google_connection, connection).properties
        end
      end
    end

    def define_snapshot_tool
      define_profile_tool(
        "analytics_snapshot",
        "Read GA4 Configuration",
        "Use this to read the selected property's normalized GA4 configuration.",
        OBJECT_OUTPUT
      ) do |profile|
        snapshot = workspace(profile).snapshot
        { "fingerprint" => snapshot.fingerprint, "snapshot" => snapshot.to_h }
      end
    end

    def define_reporting_tools
      define_overview_tool
      define_standard_report_tool
      define_portfolio_tool
      define_profile_tool(
        "analytics_realtime",
        "Read Realtime Analytics",
        "Use this to read current GA4 event counts from the safe realtime_events recipe.",
        OBJECT_OUTPUT
      ) { |profile| workspace(profile).realtime }
    end

    def define_overview_tool
      owner = self
      server.define_tool(
        name: "analytics_overview",
        title: "Show Analytics Overview",
        description: "Use this for a five-part summary of users, sessions, trends, acquisition, " \
                     "landing pages, and devices.",
        input_schema: period_schema(profile: true),
        output_schema: OBJECT_OUTPUT,
        annotations: READ_ONLY_ANNOTATIONS
      ) do |profile: nil, last_days: nil, start_date: nil, end_date: nil, compare: false, server_context: nil|
        owner.__send__(:respond, server_context) do
          ranges = owner.__send__(
            :date_ranges,
            last_days:,
            start_date:,
            end_date:,
            compare:
          )
          target = owner.__send__(:workspace, profile)
          ranges ? target.overview(date_ranges: ranges) : target.overview
        end
      end
    end

    def define_portfolio_tool
      owner = self
      server.define_tool(
        name: "analytics_portfolio",
        title: "Compare All Analytics Properties",
        description: "Use this for users, sessions, and key events across every configured property.",
        input_schema: period_schema(profile: false),
        output_schema: OBJECT_OUTPUT,
        annotations: READ_ONLY_ANNOTATIONS
      ) do |last_days: nil, start_date: nil, end_date: nil, compare: false, server_context: nil|
        owner.__send__(:respond, server_context) do
          ranges = owner.__send__(
            :date_ranges,
            last_days:,
            start_date:,
            end_date:,
            compare:
          )
          target = owner.__send__(:portfolio)
          ranges ? target.overview(date_ranges: ranges) : target.overview
        end
      end
    end

    def define_profile_tool(name, title, description, output_schema, &operation)
      owner = self
      server.define_tool(
        name:,
        title:,
        description:,
        input_schema: PROFILE_INPUT,
        output_schema:,
        annotations: READ_ONLY_ANNOTATIONS
      ) do |profile: nil, server_context: nil|
        owner.__send__(:respond, server_context) do
          owner.instance_exec(profile, &operation)
        end
      end
    end

    def period_schema(profile:)
      properties = profile ? PROFILE_INPUT.fetch(:properties) : {}
      {
        type: "object",
        additionalProperties: false,
        properties: properties.merge(PERIOD_PROPERTIES)
      }
    end

    def respond(server_context)
      server_context&.raise_if_cancelled!
      payload = serializable(yield)
      server_context&.raise_if_cancelled!
      ::MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate(payload) }],
        structured_content: payload
      )
    rescue AnalyticsOps::Error => error
      error_response(error.class.name.split("::").last, error.message)
    rescue StandardError => error
      SafeLogging.write(@logger, :error, "mcp_tool_error", "type" => error.class.name)
      error_response("InternalError", "Analytics Ops could not complete this read-only request")
    end

    def error_response(type, message)
      payload = {
        "error" => {
          "type" => Redaction.message(type),
          "message" => Redaction.message(message)
        }
      }
      ::MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate(payload) }],
        structured_content: payload,
        error: true
      )
    end

    def profile_rows
      selected = @store.selection(config: @config)
      selected_profile = selected&.fetch("profile") || profile_name(nil)
      Configuration.load(@config).profiles.sort.map do |name, desired_state|
        {
          "name" => name,
          "property_id" => desired_state.property_id,
          "connection" => @store.profile_connection(config: @config, profile: name),
          "selected" => selected_profile == name
        }
      end
    end

    def connection_rows
      @store.summaries
    end

    def workspace(requested_profile)
      profile = profile_name(requested_profile)
      service_account = load_service_account(profile:, connection: @connection)
      @workspace_loader.call(
        config: @config,
        profile:,
        service_account:,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def google_connection(requested_connection)
      profile = profile_name(nil)
      service_account = load_service_account(profile:, connection: requested_connection || @connection)
      @connection_loader.call(
        service_account:,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def load_service_account(profile:, connection:)
      @service_account_loader.call(
        store: @store,
        connection:,
        config: @config,
        profile:
      )
    end

    def load_workspace(**options)
      Workspace.load(
        options.fetch(:config),
        profile: options.fetch(:profile),
        service_account: options.fetch(:service_account),
        transport: options.fetch(:transport),
        timeout: options[:timeout],
        logger: options[:logger]
      )
    end

    def load_connection(**)
      Connection.new(**)
    end

    def portfolio
      @portfolio_loader.call(
        config: @config,
        store: @store,
        workspace_loader: @workspace_loader,
        service_account_loader: @service_account_loader,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def load_portfolio(**)
      Portfolio.new(**)
    end

    def date_ranges(last_days:, start_date:, end_date:, compare:)
      Reports::Period.resolve(last_days:, start_date:, end_date:, compare:)
    end

    def profile_name(requested)
      selected = requested || @profile || @store.selected_profile(config: @config) || "production"
      raise ConfigurationError, "Invalid Analytics Ops profile" unless PROFILE.match?(selected.to_s)

      selected.to_s
    end

    def validate_defaults!
      valid_config = @config.is_a?(String) &&
                     @config.length.between?(1, 4_096) &&
                     !@config.match?(CONTROL_CHARACTERS)
      raise ConfigurationError, "MCP configuration path is invalid" unless valid_config
      raise ConfigurationError, "MCP profile is invalid" if @profile && !valid_profile?(@profile)
      raise ConfigurationError, "MCP connection is invalid" if @connection && !valid_connection?(@connection)
    end

    def valid_profile?(value)
      value.is_a?(String) && PROFILE.match?(value)
    end

    def valid_connection?(value)
      value.is_a?(String) && CONNECTION.match?(value)
    end

    def serializable(value)
      case value
      when Array
        value.map { |item| serializable(item) }
      when Hash
        value.to_h { |key, item| [key.to_s, serializable(item)] }
      else
        value.respond_to?(:to_h) ? serializable(value.to_h) : value
      end
    end
  end
end

require_relative "mcp_server/standard_report_tool"
