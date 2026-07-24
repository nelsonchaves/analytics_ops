# frozen_string_literal: true

module AnalyticsOps
  class CLI
    # Parses and validates command-line options without loading a workspace.
    class Options
      DEFAULTS = {
        config: "config/analytics_ops.yml",
        profile: "production",
        profile_explicit: false,
        format: "human",
        log_level: "warn",
        transport: :grpc,
        yes: false,
        noninteractive: false,
        compare: false
      }.freeze
      SETUP_OPTIONS = %i[property service_account].freeze
      PROPERTY_ID = /\A\d{1,50}\z/
      PROFILE = /\A[A-Za-z][A-Za-z0-9_]{0,63}\z/
      CONNECTION = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/

      attr_reader :values

      def initialize(arguments)
        @arguments = arguments
        @values = DEFAULTS.dup
        @explicit_format = nil
      end

      def parse!(command)
        parser.parse!(@arguments)
        validate!(command)
        @values.freeze
      end

      private

      def parser
        OptionParser.new do |options|
          add_file_options(options)
          add_format_options(options)
          add_setup_options(options)
          add_report_options(options)
          add_client_options(options)
          add_execution_options(options)
        end
      end

      def add_file_options(options)
        options.on("-c", "--config PATH", "Configuration path") { |path| @values[:config] = path }
        options.on("-p", "--profile NAME", "Configuration profile") do |name|
          @values[:profile] = name
          @values[:profile_explicit] = true
        end
        options.on("--connection NAME", "Saved Google connection") { |name| @values[:connection] = name }
        options.on("-o", "--output PATH", "Write a generated plan to PATH") { |path| @values[:output] = path }
      end

      def add_format_options(options)
        options.on("-f", "--format FORMAT", CLI::FORMATS, CLI::FORMATS.join(", ")) do |format|
          select_format(format)
        end
        options.on("--json", "Use JSON output") { select_format("json") }
        options.on("--csv", "Use CSV report output") { select_format("csv") }
      end

      def select_format(format)
        if @explicit_format && @explicit_format != format
          raise OptionParser::InvalidArgument, "choose exactly one output format"
        end

        @explicit_format = format
        @values[:format] = format
      end

      def add_setup_options(options)
        options.on("--property ID", "Property to select during setup") { |id| @values[:property] = id }
        options.on("--service-account PATH", "Google service-account JSON key for setup") do |path|
          @values[:service_account] = path
        end
      end

      def add_report_options(options)
        options.on("--last DAYS", Integer, "Use the previous number of complete days") do |days|
          @values[:last_days] = days
        end
        options.on("--from DATE", "Report start date (YYYY-MM-DD)") { |date| @values[:start_date] = date }
        options.on("--to DATE", "Report end date (YYYY-MM-DD)") { |date| @values[:end_date] = date }
        options.on("--compare", "Also include the equally long preceding period") { @values[:compare] = true }
      end

      def add_client_options(options)
        options.on("--log-level LEVEL", CLI::LOG_LEVELS, CLI::LOG_LEVELS.join(", ")) do |level|
          @values[:log_level] = level
        end
        options.on("--transport TRANSPORT", %w[grpc rest], "grpc or rest") do |transport|
          @values[:transport] = transport.to_sym
        end
        options.on("--timeout SECONDS", Float, "Google API timeout") do |seconds|
          unless seconds.finite? && seconds.positive?
            raise OptionParser::InvalidArgument, "timeout must be finite and positive"
          end

          @values[:timeout] = seconds
        end
      end

      def add_execution_options(options)
        options.on("--yes", "Approve every operation in a saved plan") { @values[:yes] = true }
        options.on("--non-interactive", "Never prompt") { @values[:noninteractive] = true }
      end

      def validate!(command)
        validate_arguments!(command)
        validate_scoped_options!(command)
        validate_connection!
        validate_report_period!(command)
        validate_setup! if command == "setup"
        validate_apply! if command == "apply"
        validate_mcp! if command == "mcp"
        validate_format!(command)
      end

      def validate_arguments!(command)
        return unless CLI::NO_ARGUMENT_COMMANDS.include?(command) && @arguments.any?

        raise OptionParser::InvalidArgument, "#{command} does not accept positional arguments"
      end

      def validate_scoped_options!(command)
        validate_plan_scope!(command)
        validate_selection_scope!(command)
        validate_execution_scope!(command)
        validate_setup_scope!(command)
      end

      def validate_plan_scope!(command)
        raise OptionParser::InvalidArgument, "--output is only valid with plan" if @values[:output] && command != "plan"
        raise OptionParser::InvalidArgument, "--yes is only valid with apply" if @values[:yes] && command != "apply"
      end

      def validate_selection_scope!(command)
        if @values[:connection] && %w[connections portfolio profiles schema].include?(command)
          raise OptionParser::InvalidArgument, "--connection is not valid with #{command}"
        end
        return unless @values[:profile_explicit] && %w[connections portfolio profiles schema use].include?(command)

        raise OptionParser::InvalidArgument, "--profile is not valid with #{command}"
      end

      def validate_execution_scope!(command)
        return unless @values[:noninteractive] && !%w[apply setup].include?(command)

        raise OptionParser::InvalidArgument, "--non-interactive is only valid with apply or setup"
      end

      def validate_setup_scope!(command)
        return if SETUP_OPTIONS.none? { |name| @values[name] } || command == "setup"

        raise OptionParser::InvalidArgument, "--property and --service-account are setup-only"
      end

      def validate_connection!
        return unless @values[:connection] && !CONNECTION.match?(@values.fetch(:connection))

        raise OptionParser::InvalidArgument,
              "--connection must start with a letter and use only letters, numbers, hyphens, or underscores"
      end

      def validate_report_period!(command)
        requested = @values[:last_days] || @values[:start_date] || @values[:end_date] || @values[:compare]
        return unless requested
        unless %w[overview portfolio report].include?(command)
          raise OptionParser::InvalidArgument,
                "--last, --from, --to, and --compare are only valid with overview, portfolio, or report"
        end

        Reports::Period.resolve(
          last_days: @values[:last_days],
          start_date: @values[:start_date],
          end_date: @values[:end_date],
          compare: @values.fetch(:compare)
        )
      rescue InvalidRequestError => error
        raise OptionParser::InvalidArgument, error.message
      end

      def validate_setup!
        validate_setup_property!
        raise OptionParser::InvalidArgument, "--profile is invalid" unless PROFILE.match?(@values.fetch(:profile))

        validate_service_account!
        validate_setup_json!
      end

      def validate_setup_property!
        if @values[:noninteractive] && !@values[:property]
          raise OptionParser::MissingArgument, "Non-interactive setup requires --property ID"
        end
        return unless @values[:property] && !PROPERTY_ID.match?(@values.fetch(:property))

        raise OptionParser::InvalidArgument, "--property must be a numeric GA4 property ID"
      end

      def validate_service_account!
        return unless @values[:service_account] && !File.file?(@values.fetch(:service_account))

        raise OptionParser::InvalidArgument, "--service-account must identify an existing file"
      end

      def validate_setup_json!
        return unless @values.fetch(:format) == "json" && (!@values[:noninteractive] || !@values[:property])

        raise OptionParser::MissingArgument, "JSON setup requires --non-interactive --property ID"
      end

      def validate_apply!
        return unless @values.fetch(:format) == "json" && (!@values[:noninteractive] || !@values[:yes])

        raise OptionParser::MissingArgument, "JSON apply requires --non-interactive --yes"
      end

      def validate_mcp!
        return if @values.fetch(:format) == "human"

        raise OptionParser::InvalidArgument, "mcp uses the MCP protocol and does not accept output formats"
      end

      def validate_format!(command)
        return unless @values.fetch(:format) == "csv" && !%w[report realtime].include?(command)

        raise OptionParser::InvalidArgument, "CSV output is only valid for report results"
      end
    end
  end
end
