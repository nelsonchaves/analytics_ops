# frozen_string_literal: true

require "json"
require "logger"
require "optparse"
require_relative "../analytics_ops"

module AnalyticsOps
  # Command-line consumer of the same public Workspace API available to Ruby callers.
  class CLI
    SUCCESS = 0
    DRIFT = 2
    USAGE_ERROR = 64
    CONFIGURATION_ERROR = 65
    AUTHENTICATION_ERROR = 66
    REMOTE_ERROR = 69
    TIMEOUT_ERROR = 74
    QUOTA_ERROR = 75
    AUTHORIZATION_ERROR = 77
    UNSUPPORTED = 78
    STALE_PLAN = 79
    PARTIAL_APPLY = 80
    INTERRUPTED = 130

    COMMANDS = %w[
      setup properties doctor discover snapshot audit plan apply verify overview report realtime schema
    ].freeze
    FORMATS = %w[human json csv].freeze
    LOG_LEVELS = %w[debug info warn error].freeze
    NO_ARGUMENT_COMMANDS = %w[setup properties doctor discover snapshot audit plan verify overview schema].freeze
    CONNECTION_COMMANDS = %w[setup properties discover].freeze

    def self.start(arguments, out: $stdout, err: $stderr, input: $stdin, workspace_loader: nil,
                   connection_loader: nil, command_runner: nil)
      new(
        arguments,
        out:,
        err:,
        input:,
        workspace_loader:,
        connection_loader:,
        command_runner:
      ).call
    end

    def initialize(arguments, out:, err:, input:, workspace_loader:, connection_loader:, command_runner:)
      @arguments = arguments.dup
      @json_requested = json_option_present?(@arguments)
      @out = out
      @err = err
      @input = input
      @workspace_loader = workspace_loader || method(:load_workspace)
      @connection_loader = connection_loader || method(:load_connection)
      @command_runner = command_runner
    end

    def call
      with_error_handling { execute_command }
    end

    private

    def execute_command
      command = @arguments.shift
      if [nil, "help", "--help", "-h"].include?(command)
        raise OptionParser::InvalidArgument, "help does not accept arguments" if @arguments.any?

        return write(@out, help)
      end
      if ["version", "--version", "-v"].include?(command)
        raise OptionParser::InvalidArgument, "version does not accept arguments" if @arguments.any?

        return write(@out, AnalyticsOps::VERSION)
      end

      options = Options.new(@arguments)
      @options = options.values
      options.parse!(command)
      return unknown_command(command) unless COMMANDS.include?(command)

      execute(command)
    end

    def execute(command)
      return render(Configuration::SCHEMA, status: SUCCESS) if command == "schema"

      if CONNECTION_COMMANDS.include?(command)
        connection = @connection_loader.call(
          transport: @options.fetch(:transport),
          timeout: @options[:timeout],
          logger: operation_logger
        )
        return dispatch_connection(command, connection)
      end

      workspace = @workspace_loader.call(
        config: @options.fetch(:config),
        profile: @options.fetch(:profile),
        transport: @options.fetch(:transport),
        timeout: @options[:timeout],
        logger: operation_logger
      )
      dispatch(command, workspace)
    end

    def with_error_handling
      yield
    rescue Interrupt
      error_response(Interrupt.new("Interrupted by user"), INTERRUPTED)
    rescue OptionParser::ParseError, ConfirmationRequiredError => error
      error_response(error, USAGE_ERROR)
    rescue ConfigurationError, InvalidPlanError, ConflictError => error
      error_response(error, CONFIGURATION_ERROR)
    rescue AuthenticationError => error
      error_response(error, AUTHENTICATION_ERROR)
    rescue AuthorizationError => error
      error_response(error, AUTHORIZATION_ERROR)
    rescue UnsupportedCapabilityError => error
      error_response(error, UNSUPPORTED)
    rescue StalePlanError => error
      error_response(error, STALE_PLAN)
    rescue PartialApplyError => error
      render_error_result(error, PARTIAL_APPLY)
    rescue QuotaError => error
      error_response(error, QUOTA_ERROR)
    rescue TimeoutError => error
      error_response(error, TIMEOUT_ERROR)
    rescue InvalidRequestError, RemoteError => error
      error_response(error, REMOTE_ERROR)
    end

    def dispatch(command, workspace)
      case command
      when "doctor"
        result = workspace.doctor
        render(result, status: result.success? ? SUCCESS : REMOTE_ERROR)
      when "snapshot"
        render(workspace.snapshot)
      when "audit"
        plan = workspace.audit
        render(plan, status: plan.drift? ? DRIFT : SUCCESS)
      when "plan"
        render_plan(workspace.plan)
      when "apply"
        apply(workspace)
      when "verify"
        verification = workspace.verify
        render(verification, status: verification.converged ? SUCCESS : DRIFT)
      when "overview"
        render(workspace.overview)
      when "report"
        render(workspace.report(required_report_name!("report")))
      when "realtime"
        render(workspace.realtime(optional_realtime_name!))
      end
    end

    def dispatch_connection(command, connection)
      case command
      when "discover"
        render(connection.discover)
      when "properties"
        render_properties(connection.properties)
      when "setup"
        setup(connection)
      end
    end

    def setup(connection)
      result = Setup.new(
        connection:,
        config: @options.fetch(:config),
        profile: @options.fetch(:profile),
        property_id: @options[:property],
        noninteractive: @options[:noninteractive],
        client_id_file: @options[:client_id_file],
        no_launch_browser: @options[:no_launch_browser],
        input: @input,
        out: @out,
        err: @err,
        command_runner: @command_runner
      ).call

      if human?
        action = result.created? ? "Created" : "Using"
        @out.puts "#{action} #{Redaction.message(result.config_path)}"
        @out.puts "Connected #{Redaction.message(result.profile)} to " \
                  "#{Redaction.message(result.property.display_name)} " \
                  "(property #{Redaction.message(result.property.id)})."
        @out.puts "Next: analytics-ops overview"
        SUCCESS
      else
        render(result)
      end
    end

    def render_plan(plan)
      plan.write(@options.fetch(:output)) if @options[:output]
      render(plan)
    end

    def apply(workspace)
      path = required_plan_path!
      saved_plan = Plan.load(path)
      @out.puts(human_plan(saved_plan, detailed: true)) if human? && !@options[:yes]
      confirmed = @options[:yes] || interactive_confirmation?
      render(workspace.apply(saved_plan, confirm: confirmed))
    end

    def required_plan_path!
      raise OptionParser::MissingArgument, "apply requires exactly one PLAN_FILE" unless @arguments.length == 1

      @arguments.first
    end

    def required_report_name!(command)
      raise OptionParser::MissingArgument, "#{command} requires exactly one REPORT_NAME" unless @arguments.length == 1

      @arguments.first
    end

    def optional_realtime_name!
      raise OptionParser::InvalidArgument, "realtime accepts at most one REPORT_NAME" if @arguments.length > 1

      @arguments.first || "realtime_events"
    end

    def interactive_confirmation?
      raise ConfirmationRequiredError, "Non-interactive apply requires --yes" if @options[:noninteractive]

      @out.print "Apply every change in this saved plan? Type `yes` to continue: "
      @out.flush
      answer = @input.gets
      raise ConfirmationRequiredError, "Apply was not confirmed" unless answer&.strip == "yes"

      true
    end

    def load_workspace(config:, profile:, transport:, timeout:, logger:)
      Workspace.load(config, profile:, transport:, timeout:, logger:)
    end

    def load_connection(transport:, timeout:, logger:)
      Connection.new(transport:, timeout:, logger:)
    end

    def operation_logger
      @operation_logger ||= Logger.new(@err).tap do |logger|
        logger.level = Logger.const_get(@options.fetch(:log_level).upcase)
        logger.formatter = ->(_severity, _time, _program, message) { "#{message}\n" }
      end
    end

    def render(value, status: SUCCESS)
      presenter.render(value, status:)
    end

    def json(value)
      presenter.json(value)
    end

    def human_plan(plan, detailed: false)
      presenter.human_plan(plan, detailed:)
    end

    def render_properties(accounts)
      presenter.render_properties(accounts)
    end

    def render_error_result(error, status)
      if json?
        @err.write(json("error" => error_payload(error), "result" => error.result))
      else
        @err.puts "#{error_name(error)}: #{Redaction.message(error.message)}"
        @err.write(json(error.result))
      end
      status
    end

    def error_response(error, status)
      if json?
        @err.write(json("error" => error_payload(error)))
      else
        @err.puts "#{error_name(error)}: #{Redaction.message(error.message)}"
      end
      status
    end

    def error_payload(error)
      { "type" => error_name(error), "message" => Redaction.message(error.message) }
    end

    def error_name(error)
      error.class.name.split("::").last
    end

    def human?
      @options&.fetch(:format, "human") == "human"
    end

    def json?
      @json_requested || @options&.fetch(:format, "human") == "json"
    end

    def presenter
      format = json? ? "json" : @options&.fetch(:format, "human") || "human"
      @presenter ||= Presenter.new(out: @out, format:)
    end

    def write(stream, message, status = SUCCESS)
      stream.puts message
      status
    end

    def unknown_command(command)
      if json?
        error = OptionParser::InvalidArgument.new("Unknown command: #{Redaction.message(command)}")
        return error_response(error, USAGE_ERROR)
      end

      @err.puts "Unknown command: #{Redaction.message(command)}"
      write(@err, "Run `analytics-ops help` for available commands.", USAGE_ERROR)
    end

    def json_option_present?(arguments)
      arguments.each_with_index.any? do |argument, index|
        argument == "--json" || argument == "--format=json" || argument == "-fjson" ||
          (%w[--format -f].include?(argument) && arguments[index + 1] == "json")
      end
    end

    def help
      <<~HELP
        Analytics Ops #{AnalyticsOps::VERSION}
        Google Analytics 4 configuration as code and reporting for Ruby and Rails.

        Usage:
          analytics-ops COMMAND [options]

        Start here:
          setup        Connect Google, choose a property, and create configuration
          overview     Show a useful five-section summary for the selected property
          properties   List accessible accounts and properties without configuration

        Read-only commands:
          doctor       Validate local setup and Google API/property access
          discover     List accessible accounts, properties, and streams without configuration
          snapshot     Print normalized remote configuration
          audit        Compare desired and remote state (exit 2 for drift)
          plan         Generate a deterministic plan; use --output to save it
          verify       Prove whether managed state converges
          report NAME  Run a built-in standard report
          realtime     Run realtime_events (or pass another realtime recipe)
          schema       Print the version-1 configuration schema

        Mutation command:
          apply FILE   Apply only a saved, non-stale plan; prompts unless --yes

        Other commands:
          help         Show this help
          version      Print the installed version

        Common options:
          -c, --config PATH          Default: config/analytics_ops.yml
          -p, --profile NAME        Default: production
          -f, --format FORMAT       human, json, or report-only csv
              --json                Shortcut for --format json
              --csv                 Shortcut for --format csv
          -o, --output PATH         Save a generated plan (plan only)
              --property ID         Select a property without prompting (setup only)
              --client-id-file PATH Owned Desktop OAuth client file (setup only)
              --no-launch-browser   Print login instructions instead of opening a browser
              --transport NAME      grpc or rest
              --timeout SECONDS     Positive Google API timeout
              --log-level LEVEL     debug, info, warn, or error
              --yes                 Required for non-interactive apply
              --non-interactive     Never prompt
      HELP
    end
  end
end

require_relative "cli/presenter"
require_relative "cli/options"
