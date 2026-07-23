# frozen_string_literal: true

module AnalyticsOps
  # Interactive or automated property selection after service-account loading.
  class Setup
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

    def initialize(connection:, config:, profile:, property_id: nil, noninteractive: false,
                   input: $stdin, out: $stdout)
      validate_options!(
        config:,
        profile:,
        property_id:,
        noninteractive:
      )
      @connection = connection
      @config = config
      @profile = profile.to_s
      @property_id = property_id
      @noninteractive = noninteractive
      @input = input
      @out = out
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

    def validate_options!(config:, profile:, property_id:, noninteractive:)
      validate_config_path!(config)
      validate_profile!(profile)
      validate_property_id!(property_id)
      validate_boolean_option!(noninteractive)
      raise ConfigurationError, "Non-interactive setup requires a property ID" if noninteractive && !property_id
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

    def validate_boolean_option!(noninteractive)
      return if [true, false].include?(noninteractive)

      raise ConfigurationError, "Setup boolean options must be true or false"
    end

    def google_call
      yield
    rescue AuthorizationError, InvalidRequestError, RemoteError => error
      raise_disabled_api! if api_disabled?(error)

      raise
    end

    def api_disabled?(error)
      error.message.match?(/SERVICE_DISABLED|API.*(?:disabled|not been used)|serviceusage/i)
    end

    def raise_disabled_api!
      raise RemoteError,
            "Google Analytics APIs appear disabled. Enable Google Analytics Admin API and " \
            "Google Analytics Data API in the Google Cloud project that owns the service account."
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
