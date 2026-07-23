# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module AnalyticsOps
  # The single supported Google authentication source.
  class ServiceAccount
    MAX_KEY_BYTES = 64 * 1024
    READ_SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
    EDIT_SCOPE = "https://www.googleapis.com/auth/analytics.edit"
    ACCESS_SCOPES = {
      read: [READ_SCOPE].freeze,
      edit: [READ_SCOPE, EDIT_SCOPE].freeze
    }.freeze
    REQUIRED_FIELDS = %w[type client_email private_key token_uri].freeze
    CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/

    attr_reader :path

    def self.load(path: nil, store: Store.new)
      new(path || store.read)
    end

    def initialize(path)
      @path = validated_path(path).freeze
      validate_key!
      freeze
    end

    def credentials(access: :read)
      build_credentials(scopes_for(access))
    end
    private :credentials

    private

    def scopes_for(access)
      ACCESS_SCOPES.fetch(access) { raise ArgumentError, "access must be :read or :edit" }
    end

    def build_credentials(scopes)
      require "googleauth"
      File.open(path, "rb") do |key|
        Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: key, scope: scopes)
      end
    rescue LoadError => error
      raise UnsupportedCapabilityError,
            "Google authentication support is unavailable: #{Redaction.message(error.message)}"
    rescue AnalyticsOps::Error
      raise
    rescue StandardError
      raise AuthenticationError, "The configured service-account key could not be loaded"
    end

    def validated_path(value)
      unless value.is_a?(String) && !value.empty? && !value.match?(CONTROL_CHARACTERS)
        raise AuthenticationError, "A valid service-account key path is required"
      end

      expanded = File.expand_path(value)
      unless File.file?(expanded)
        raise AuthenticationError,
              "The configured service-account key is unavailable; run " \
              "`analytics-ops setup --service-account /absolute/path/to/service-account.json`"
      end
      if File.size(expanded) > MAX_KEY_BYTES
        raise AuthenticationError, "The configured service-account key is too large"
      end

      File.realpath(expanded)
    rescue AnalyticsOps::Error
      raise
    rescue SystemCallError
      raise AuthenticationError,
            "The configured service-account key is unavailable; run " \
            "`analytics-ops setup --service-account /absolute/path/to/service-account.json`"
    end

    def validate_key!
      document = JSON.parse(File.binread(path, MAX_KEY_BYTES + 1), max_nesting: 8)
      valid = document.is_a?(Hash) &&
              document["type"] == "service_account" &&
              REQUIRED_FIELDS.all? { |field| document[field].is_a?(String) && !document[field].empty? }
      return if valid

      raise AuthenticationError, "The selected JSON file is not a Google service-account key"
    rescue AnalyticsOps::Error
      raise
    rescue JSON::ParserError, ArgumentError, SystemCallError
      raise AuthenticationError, "The selected JSON file is not a valid Google service-account key"
    end

    # User-level pointer to a validated key. The key itself is never copied.
    class Store
      VERSION = 1
      MAX_BYTES = 16 * 1024
      FIELDS = %w[service_account_path version].freeze

      attr_reader :path

      def self.default_path
        File.join(Dir.home, ".config", "analytics_ops", "connection.json")
      rescue ArgumentError
        raise AuthenticationError, "Cannot determine the user configuration directory"
      end

      def initialize(path: nil)
        candidate = path || self.class.default_path
        unless candidate.is_a?(String) && !candidate.empty? && !candidate.match?(CONTROL_CHARACTERS)
          raise AuthenticationError, "The Analytics Ops connection path is invalid"
        end

        @path = File.expand_path(candidate).freeze
      end

      def read
        unless File.file?(path)
          raise AuthenticationError,
                "No service account is configured; run " \
                "`analytics-ops setup --service-account /absolute/path/to/service-account.json`"
        end
        raise AuthenticationError, "The saved Analytics Ops connection is too large" if File.size(path) > MAX_BYTES

        document = JSON.parse(File.binread(path, MAX_BYTES + 1), max_nesting: 4)
        valid = document.is_a?(Hash) &&
                document.keys.sort == FIELDS &&
                document["version"] == VERSION &&
                document["service_account_path"].is_a?(String)
        return document.fetch("service_account_path") if valid

        raise AuthenticationError, invalid_connection_message
      rescue AnalyticsOps::Error
        raise
      rescue JSON::ParserError, ArgumentError, SystemCallError
        raise AuthenticationError, invalid_connection_message
      end

      def write(service_account_path)
        normalized = ServiceAccount.new(service_account_path).path
        directory = File.dirname(path)
        FileUtils.mkdir_p(directory, mode: 0o700)
        File.chmod(0o700, directory)
        temporary = File.join(directory, ".connection.#{Process.pid}.#{SecureRandom.hex(6)}.tmp")
        payload = JSON.generate("version" => VERSION, "service_account_path" => normalized) << "\n"

        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(payload)
          file.flush
          file.fsync
        end
        File.rename(temporary, path)
        File.chmod(0o600, path)
        path
      rescue AnalyticsOps::Error
        raise
      rescue SystemCallError
        raise AuthenticationError, "Cannot save the Analytics Ops service-account connection"
      ensure
        File.unlink(temporary) if temporary && File.exist?(temporary)
      end

      private

      def invalid_connection_message
        "The saved Analytics Ops connection is invalid; rerun setup with --service-account"
      end
    end
  end
end
