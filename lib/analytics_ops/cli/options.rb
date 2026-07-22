# frozen_string_literal: true

module AnalyticsOps
  class CLI
    # Parses and validates command-line options without loading a workspace.
    class Options
      DEFAULTS = {
        config: "config/analytics_ops.yml",
        profile: "production",
        format: "human",
        log_level: "warn",
        transport: :grpc,
        yes: false,
        noninteractive: false,
        no_launch_browser: false
      }.freeze
      SETUP_OPTIONS = %i[property client_id_file no_launch_browser].freeze
      PROPERTY_ID = /\A\d{1,50}\z/
      PROFILE = /\A[A-Za-z][A-Za-z0-9_]{0,63}\z/

      attr_reader :values

      def initialize(arguments)
        @arguments = arguments
        @values = DEFAULTS.dup
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
          add_client_options(options)
          add_execution_options(options)
        end
      end

      def add_file_options(options)
        options.on("-c", "--config PATH", "Configuration path") { |path| @values[:config] = path }
        options.on("-p", "--profile NAME", "Configuration profile") { |name| @values[:profile] = name }
        options.on("-o", "--output PATH", "Write a generated plan to PATH") { |path| @values[:output] = path }
      end

      def add_format_options(options)
        options.on("-f", "--format FORMAT", CLI::FORMATS, CLI::FORMATS.join(", ")) do |format|
          @values[:format] = format
        end
        options.on("--json", "Use JSON output") { @values[:format] = "json" }
        options.on("--csv", "Use CSV report output") { @values[:format] = "csv" }
      end

      def add_setup_options(options)
        options.on("--property ID", "Property to select during setup") { |id| @values[:property] = id }
        options.on("--client-id-file PATH", "Desktop OAuth client file for setup") do |path|
          @values[:client_id_file] = path
        end
        options.on("--no-launch-browser", "Print the Google login URL instead of opening it") do
          @values[:no_launch_browser] = true
        end
      end

      def add_client_options(options)
        options.on("--log-level LEVEL", CLI::LOG_LEVELS, CLI::LOG_LEVELS.join(", ")) do |level|
          @values[:log_level] = level
        end
        options.on("--transport TRANSPORT", %w[grpc rest], "grpc or rest") do |transport|
          @values[:transport] = transport.to_sym
        end
        options.on("--timeout SECONDS", Float, "Google API timeout") do |seconds|
          raise OptionParser::InvalidArgument, "timeout must be positive" unless seconds.positive?

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
        validate_setup! if command == "setup"
        validate_format!(command)
      end

      def validate_arguments!(command)
        return unless CLI::NO_ARGUMENT_COMMANDS.include?(command) && @arguments.any?

        raise OptionParser::InvalidArgument, "#{command} does not accept positional arguments"
      end

      def validate_scoped_options!(command)
        raise OptionParser::InvalidArgument, "--output is only valid with plan" if @values[:output] && command != "plan"
        raise OptionParser::InvalidArgument, "--yes is only valid with apply" if @values[:yes] && command != "apply"
        if @values[:noninteractive] && !%w[apply setup].include?(command)
          raise OptionParser::InvalidArgument, "--non-interactive is only valid with apply or setup"
        end
        return if SETUP_OPTIONS.none? { |name| @values[name] } || command == "setup"

        raise OptionParser::InvalidArgument, "--property, --client-id-file, and --no-launch-browser are setup-only"
      end

      def validate_setup!
        validate_setup_property!
        raise OptionParser::InvalidArgument, "--profile is invalid" unless PROFILE.match?(@values.fetch(:profile))

        validate_setup_client!
        validate_setup_json!
      end

      def validate_setup_property!
        if @values[:noninteractive] && !@values[:property]
          raise OptionParser::MissingArgument, "Non-interactive setup requires --property ID"
        end
        return unless @values[:property] && !PROPERTY_ID.match?(@values.fetch(:property))

        raise OptionParser::InvalidArgument, "--property must be a numeric GA4 property ID"
      end

      def validate_setup_client!
        return unless @values[:client_id_file] && !File.file?(@values.fetch(:client_id_file))

        raise OptionParser::InvalidArgument, "--client-id-file must identify an existing file"
      end

      def validate_setup_json!
        return unless @values.fetch(:format) == "json" && (!@values[:noninteractive] || !@values[:property])

        raise OptionParser::MissingArgument, "JSON setup requires --non-interactive --property ID"
      end

      def validate_format!(command)
        return unless @values.fetch(:format) == "csv" && !%w[report realtime].include?(command)

        raise OptionParser::InvalidArgument, "CSV output is only valid for report results"
      end
    end
  end
end
