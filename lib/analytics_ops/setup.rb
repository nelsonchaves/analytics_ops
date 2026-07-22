# frozen_string_literal: true

module AnalyticsOps
  # Interactive or automated configuration bootstrap using official Google ADC.
  class Setup
    ANALYTICS_SCOPES = %w[
      https://www.googleapis.com/auth/cloud-platform
      https://www.googleapis.com/auth/analytics.readonly
    ].freeze
    PROPERTY_ID = /\A\d{1,50}\z/
    PROFILE = /\A[A-Za-z][A-Za-z0-9_]{0,63}\z/

    # Immutable setup outcome returned to the CLI and Ruby callers.
    class Result
      attr_reader :config_path, :profile, :property

      def initialize(config_path:, profile:, property:, created:)
        unless property.is_a?(Resources::Property)
          raise ArgumentError, "property must be an AnalyticsOps::Resources::Property"
        end
        raise ArgumentError, "created must be true or false" unless [true, false].include?(created)

        @config_path = config_path.to_s.dup.freeze
        @profile = profile.to_s.dup.freeze
        @property = property
        @created = created
        freeze
      end

      def created?
        @created
      end

      def status
        created? ? "configured" : "already_configured"
      end

      def to_h
        {
          "status" => status,
          "config" => config_path,
          "profile" => profile,
          "property" => property.to_h
        }
      end
    end

    # Small injectable boundary around the official authentication subprocess.
    class SystemCommandRunner
      def available?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
          candidate = File.join(path, command)
          File.file?(candidate) && File.executable?(candidate)
        end
      end

      def run(arguments, input:, out:, err:)
        Kernel.system(*arguments, in: input, out:, err:)
      rescue SystemCallError
        false
      end
    end
    private_constant :SystemCommandRunner

    def initialize(connection:, config:, profile:, property_id: nil, noninteractive: false,
                   client_id_file: nil, no_launch_browser: false, input: $stdin, out: $stdout,
                   err: $stderr, command_runner: nil)
      validate_options!(
        config:,
        profile:,
        property_id:,
        noninteractive:,
        client_id_file:,
        no_launch_browser:
      )
      @connection = connection
      @config = config
      @profile = profile.to_s
      @property_id = property_id
      @noninteractive = noninteractive
      @client_id_file = client_id_file
      @no_launch_browser = no_launch_browser
      @input = input
      @out = out
      @err = err
      @command_runner = command_runner || SystemCommandRunner.new
      @attempted_authentication = false
    end

    def call
      selection = select_property(google_call { @connection.properties })
      verification = google_call { @connection.verify(selection.fetch("id")) }
      write = Configuration::Writer.new.write_minimal(
        @config,
        profile: @profile,
        property_id: verification.property.id
      )
      Result.new(
        config_path: write.path,
        profile: @profile,
        property: verification.property,
        created: write.created?
      )
    end

    private

    def validate_options!(config:, profile:, property_id:, noninteractive:, client_id_file:, no_launch_browser:)
      validate_config_path!(config)
      validate_profile!(profile)
      validate_property_id!(property_id)
      validate_boolean_options!(noninteractive, no_launch_browser)
      raise ConfigurationError, "Non-interactive setup requires a property ID" if noninteractive && !property_id

      validate_client_id_file!(client_id_file)
    end

    def validate_config_path!(config)
      valid = config.is_a?(String) && !config.empty? && !config.match?(/[\u0000-\u001f\u007f]/)
      return if valid

      raise ConfigurationError, "Setup configuration path is invalid"
    end

    def validate_profile!(profile)
      raise ConfigurationError, "Setup profile is invalid" unless PROFILE.match?(profile.to_s)
    end

    def validate_property_id!(property_id)
      return if property_id.nil? || (property_id.is_a?(String) && PROPERTY_ID.match?(property_id))

      raise ConfigurationError, "Setup property must be a numeric GA4 property ID"
    end

    def validate_boolean_options!(noninteractive, no_launch_browser)
      valid = [true, false].include?(noninteractive) && [true, false].include?(no_launch_browser)
      return if valid

      raise ConfigurationError, "Setup boolean options must be true or false"
    end

    def validate_client_id_file!(client_id_file)
      return if client_id_file.nil? || (client_id_file.is_a?(String) && File.file?(client_id_file))

      raise ConfigurationError, "Desktop OAuth client file does not exist"
    end

    def google_call
      yield
    rescue AuthenticationError
      raise if @attempted_authentication

      authenticate_for_setup!
      @attempted_authentication = true
      retry
    rescue AuthorizationError => error
      raise_disabled_api! if api_disabled?(error)
      raise unless insufficient_scope?(error) && !@attempted_authentication

      authenticate_for_setup!
      @attempted_authentication = true
      retry
    rescue InvalidRequestError, RemoteError => error
      raise_disabled_api! if api_disabled?(error)

      raise
    end

    def authenticate_for_setup!
      if @noninteractive
        raise AuthenticationError, "No usable Application Default Credentials. Run `#{authentication_command}`."
      end
      unless @command_runner.available?("gcloud")
        raise UnsupportedCapabilityError,
              "Google Cloud CLI is required for interactive setup. On macOS run " \
              "`brew install --cask google-cloud-sdk`; otherwise visit https://cloud.google.com/sdk/docs/install."
      end

      @out.puts "Google login is required. Analytics Ops will run the official gcloud ADC command."
      @out.puts "This may replace the local ADC credentials used by other development tools."
      succeeded = @command_runner.run(authentication_arguments, input: @input, out: @out, err: @err)
      if succeeded
        @connection.reload_credentials!
        return
      end

      raise AuthenticationError,
            "Google ADC login did not complete. If Google blocked the Analytics scope, create a Desktop OAuth " \
            "client and retry with --client-id-file PATH. For a headless session, add --no-launch-browser."
    end

    def authentication_arguments
      arguments = [
        "gcloud", "auth", "application-default", "login",
        "--scopes=#{ANALYTICS_SCOPES.join(",")}"
      ]
      arguments << "--client-id-file=#{@client_id_file}" if @client_id_file
      arguments << "--no-launch-browser" if @no_launch_browser
      arguments
    end

    def authentication_command
      command = "gcloud auth application-default login --scopes=\"#{ANALYTICS_SCOPES.join(",")}\""
      command += " --client-id-file=YOUR_DESKTOP_OAUTH_CLIENT.json" if @client_id_file
      command += " --no-launch-browser" if @no_launch_browser
      command
    end

    def insufficient_scope?(error)
      error.message.match?(/insufficient.*scope|ACCESS_TOKEN_SCOPE_INSUFFICIENT/i)
    end

    def api_disabled?(error)
      error.message.match?(/SERVICE_DISABLED|API.*(?:disabled|not been used)|serviceusage/i)
    end

    def raise_disabled_api!
      raise RemoteError,
            "Google Analytics APIs appear disabled. Run `gcloud services enable " \
            "analyticsadmin.googleapis.com analyticsdata.googleapis.com --project YOUR_GOOGLE_CLOUD_PROJECT`."
    end

    def select_property(accounts)
      choices = property_choices(accounts)
      raise AuthorizationError, "No accessible Google Analytics properties found" if choices.empty?

      return explicit_property(choices) if @property_id
      return choices.first if choices.one?

      prompt_for_property(choices)
    end

    def explicit_property(choices)
      choices.find { |choice| choice.fetch("id") == @property_id } ||
        raise(AuthorizationError, "Property #{@property_id} is not accessible")
    end

    def prompt_for_property(choices)
      @out.puts "Choose a Google Analytics property:"
      choices.each.with_index(1) do |choice, index|
        @out.puts "  #{index}. #{Redaction.message(choice.fetch("display_name"))} — " \
                  "#{Redaction.message(choice.fetch("account_display_name"))} " \
                  "(property #{Redaction.message(choice.fetch("id"))})"
      end
      @out.print "Property number: "
      @out.flush
      index = Integer(@input.gets&.strip, exception: false)
      unless index&.between?(1, choices.length)
        raise ConfigurationError, "A property number from 1 to #{choices.length} is required"
      end

      choices.fetch(index - 1)
    end

    def property_choices(accounts)
      choices = accounts.flat_map do |account|
        account.properties.map do |property|
          property.merge("account_id" => account.id, "account_display_name" => account.display_name)
        end
      end
      choices.sort_by do |property|
        [property.fetch("account_display_name"), property.fetch("display_name"), property.fetch("id")]
      end
    end
  end
end
