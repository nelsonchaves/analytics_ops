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

    COMMANDS = %w[doctor discover snapshot audit plan apply verify report realtime schema].freeze
    FORMATS = %w[human json csv].freeze
    LOG_LEVELS = %w[debug info warn error].freeze
    NO_ARGUMENT_COMMANDS = %w[doctor discover snapshot audit plan verify schema].freeze

    def self.start(arguments, out: $stdout, err: $stderr, input: $stdin, workspace_loader: nil)
      new(arguments, out:, err:, input:, workspace_loader:).call
    end

    def initialize(arguments, out:, err:, input:, workspace_loader:)
      @arguments = arguments.dup
      @out = out
      @err = err
      @input = input
      @workspace_loader = workspace_loader || method(:load_workspace)
      @options = default_options
    end

    def call
      command = @arguments.shift
      return write(@out, help) if [nil, "help", "--help", "-h"].include?(command)
      return write(@out, AnalyticsOps::VERSION) if ["version", "--version", "-v"].include?(command)
      return unknown_command(command) unless COMMANDS.include?(command)

      parse_options!
      validate_command!(command)
      return render(Configuration::SCHEMA, status: SUCCESS) if command == "schema"

      workspace = @workspace_loader.call(
        config: @options.fetch(:config),
        profile: @options.fetch(:profile),
        transport: @options.fetch(:transport),
        timeout: @options[:timeout],
        logger: operation_logger
      )
      dispatch(command, workspace)
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

    private

    def default_options
      {
        config: "config/analytics_ops.yml",
        profile: "production",
        format: "human",
        log_level: "warn",
        transport: :grpc,
        yes: false,
        noninteractive: false
      }
    end

    def parse_options!
      parser = OptionParser.new do |value|
        value.on("-c", "--config PATH", "Configuration path") { |path| @options[:config] = path }
        value.on("-p", "--profile NAME", "Configuration profile") { |name| @options[:profile] = name }
        value.on("-f", "--format FORMAT", FORMATS, FORMATS.join(", ")) { |format| @options[:format] = format }
        value.on("-o", "--output PATH", "Write a generated plan to PATH") { |path| @options[:output] = path }
        value.on("--log-level LEVEL", LOG_LEVELS, LOG_LEVELS.join(", ")) { |level| @options[:log_level] = level }
        value.on("--transport TRANSPORT", %w[grpc rest], "grpc or rest") do |transport|
          @options[:transport] = transport.to_sym
        end
        value.on("--timeout SECONDS", Float, "Google API timeout") do |seconds|
          raise OptionParser::InvalidArgument, "timeout must be positive" unless seconds.positive?

          @options[:timeout] = seconds
        end
        value.on("--yes", "Approve every operation in a saved plan") { @options[:yes] = true }
        value.on("--non-interactive", "Never prompt") { @options[:noninteractive] = true }
      end
      parser.parse!(@arguments)
    end

    def validate_command!(command)
      if NO_ARGUMENT_COMMANDS.include?(command) && @arguments.any?
        raise OptionParser::InvalidArgument, "#{command} does not accept positional arguments"
      end
      raise OptionParser::InvalidArgument, "--output is only valid with plan" if @options[:output] && command != "plan"
      if (@options[:yes] || @options[:noninteractive]) && command != "apply"
        raise OptionParser::InvalidArgument, "--yes and --non-interactive are only valid with apply"
      end
      return unless @options.fetch(:format) == "csv" && !%w[report realtime].include?(command)

      raise OptionParser::InvalidArgument, "CSV output is only valid for report results"
    end

    def dispatch(command, workspace)
      case command
      when "doctor"
        result = workspace.doctor
        render(result, status: result.success? ? SUCCESS : REMOTE_ERROR)
      when "discover"
        render(workspace.discover)
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
      when "report"
        render(workspace.report(required_report_name!("report")))
      when "realtime"
        render(workspace.realtime(optional_realtime_name!))
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

    def operation_logger
      @operation_logger ||= Logger.new(@err).tap do |logger|
        logger.level = Logger.const_get(@options.fetch(:log_level).upcase)
        logger.formatter = ->(_severity, _time, _program, message) { "#{message}\n" }
      end
    end

    def render(value, status: SUCCESS)
      case @options.fetch(:format)
      when "json"
        @out.write(json(value))
      when "csv"
        @out.write(csv(value))
      else
        @out.puts(human(value))
      end
      status
    end

    def json(value)
      payload = serializable(value)
      "#{JSON.pretty_generate(Canonical.normalize(payload))}\n"
    end

    def csv(value)
      unless value.is_a?(Reports::Result)
        raise OptionParser::InvalidArgument, "CSV output is only valid for report results"
      end

      lines = [value.headers]
      value.rows.each { |row| lines << value.headers.map { |header| csv_cell(row.fetch(header)) } }
      "#{lines.map { |line| line.map { |cell| csv_field(cell) }.join(",") }.join("\n")}\n"
    end

    def csv_cell(value)
      string = value.to_s
      string.match?(/\A[=+\-@]/) ? "'#{string}" : string
    end

    def csv_field(value)
      string = value.to_s
      return string unless string.match?(/[",\r\n]/)

      "\"#{string.gsub("\"", "\"\"")}\""
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

    def human(value)
      case value
      when Plan
        human_plan(value)
      when Snapshot
        "Snapshot #{value.fingerprint}\n#{JSON.pretty_generate(Canonical.normalize(value.to_h))}"
      when Workspace::DoctorResult
        human_doctor(value)
      when Workspace::Verification
        "#{value.converged ? "Converged" : "Drift found"}: #{value.plan.changes.length} planned changes"
      when Applier::Result
        "Apply #{value.status}: #{value.applied.length} changes completed"
      when Reports::Result
        human_report(value)
      when Array
        human_discovery(value)
      else
        JSON.pretty_generate(Canonical.normalize(serializable(value)))
      end
    end

    def human_doctor(value)
      value.checks.map do |check|
        "#{check.fetch("status").upcase.ljust(11)} #{check.fetch("name")}: #{check.fetch("detail")}"
      end.join("\n")
    end

    def human_plan(plan, detailed: false)
      lines = [
        "Plan for profile #{plan.profile} / property #{plan.property_id}",
        "Snapshot: #{plan.snapshot_fingerprint}",
        "Changes: #{plan.changes.length}; findings: #{plan.findings.length}"
      ]
      plan.changes.each do |change|
        lines << "  #{change.operation.upcase.ljust(6)} #{change.resource_type} #{change.resource_identity}"
        next unless detailed

        lines << "    before: #{JSON.generate(Canonical.normalize(change.before))}"
        lines << "    after:  #{JSON.generate(Canonical.normalize(change.after))}"
        lines << "    rollback: #{change.rollback}"
      end
      plan.findings.each do |finding|
        lines << "  #{finding.severity.upcase.ljust(12)} #{finding.resource_identity}: #{finding.message}"
      end
      lines.join("\n")
    end

    def human_report(result)
      lines = ["Report #{result.name} (#{result.kind}) — #{result.row_count} rows"]
      return (lines << "No rows returned").join("\n") if result.rows.empty?

      widths = result.headers.to_h do |header|
        values = result.rows.map { |row| row.fetch(header).to_s }
        [header, ([header.length] + values.map(&:length)).max.clamp(1, 60)]
      end
      lines << table_row(result.headers, widths)
      lines << result.headers.map { |header| "-" * widths.fetch(header) }.join("-+-")
      result.rows.each do |row|
        lines << table_row(result.headers.map { |header| row.fetch(header) }, widths, headers: result.headers)
      end
      lines.join("\n")
    end

    def table_row(values, widths, headers: values)
      values.zip(headers).map do |value, header|
        value.to_s.slice(0, widths.fetch(header)).ljust(widths.fetch(header))
      end.join(" | ")
    end

    def human_discovery(accounts)
      return "No accessible Google Analytics accounts found" if accounts.empty?

      accounts.flat_map do |account|
        lines = ["Account #{account.id}: #{account.display_name}"]
        account.properties.each do |property|
          lines << "  Property #{property.fetch("id")}: #{property.fetch("display_name")}"
          property.fetch("streams").each do |stream|
            lines << "    Stream #{stream.fetch("id")}: #{stream.fetch("display_name")} (#{stream.fetch("type")})"
          end
        end
        lines
      end.join("\n")
    end

    def render_error_result(error, status)
      if json?
        @err.write(json("error" => error_payload(error), "result" => serializable(error.result)))
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
      @options.fetch(:format) == "human"
    end

    def json?
      @options.fetch(:format) == "json"
    end

    def write(stream, message, status = SUCCESS)
      stream.puts message
      status
    end

    def unknown_command(command)
      @err.puts "Unknown command: #{Redaction.message(command)}"
      write(@err, "Run `analytics-ops help` for available commands.", USAGE_ERROR)
    end

    def help
      <<~HELP
        Analytics Ops #{AnalyticsOps::VERSION}
        Google Analytics 4 configuration as code and reporting for Ruby and Rails.

        Usage:
          analytics-ops COMMAND [options]

        Read-only commands:
          doctor       Validate local setup and Google API/property access
          discover     List accessible accounts, properties, and data streams
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
          -c, --config PATH       Default: config/analytics_ops.yml
          -p, --profile NAME     Default: production
          -f, --format FORMAT    human, json, or report-only csv
          -o, --output PATH      Save a generated plan (plan only)
              --transport NAME   grpc or rest
              --timeout SECONDS
              --log-level LEVEL  debug, info, warn, or error
              --yes              Required for non-interactive apply
              --non-interactive  Never prompt
      HELP
    end
  end
end
