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

    attr_reader :path, :security_warnings

    def self.load(path: nil, store: Store.new, connection: nil, config: nil, profile: nil)
      new(path || store.read(name: connection, config:, profile:))
    end

    def initialize(path)
      @path = validated_path(path).freeze
      validate_key!
      @security_warnings = key_security_warnings.map { |warning| warning.dup.freeze }.freeze
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

    def key_security_warnings
      warnings = []
      mode = File.stat(path).mode & 0o777
      if mode.anybits?(0o077)
        warnings << "Service-account key permissions are #{format("%04o", mode)}; protect the file with `chmod 600`."
      end
      if inside_git_repository?
        warnings << "The service-account key is stored inside a Git repository; " \
                    "move it outside every application repository."
      end
      warnings
    rescue SystemCallError
      ["Analytics Ops could not verify the service-account key's local file permissions."]
    end

    def inside_git_repository?
      directory = File.dirname(path)
      loop do
        return true if File.exist?(File.join(directory, ".git"))

        parent = File.dirname(directory)
        return false if parent == directory

        directory = parent
      end
    end

    # User-level pointer to a validated key. The key itself is never copied.
    class Store
      VERSION = 2
      LEGACY_VERSION = 1
      MAX_BYTES = 64 * 1024
      FIELDS = %w[configs connections version].freeze
      LEGACY_FIELDS = %w[service_account_path version].freeze
      CONFIG_FIELDS = %w[profile_connections selected_profile].freeze
      CONNECTION_NAME = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/
      PROFILE_NAME = /\A[A-Za-z][A-Za-z0-9_]{0,63}\z/

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

      def read(name: nil, config: nil, profile: nil)
        saved = read_document(required: true)
        selected = resolve_name(saved, name:, config:, profile:)
        saved.fetch("connections").fetch(selected)
      end

      def resolve_connection_name(name: nil, config: nil, profile: nil)
        resolve_name(read_document(required: true), name:, config:, profile:)
      end

      def connection_name_for(service_account_path, preferred:, config:, profile:)
        normalized = ServiceAccount.new(service_account_path).path
        validate_association!(config, profile)
        preferred_name = validate_connection_name!(preferred)
        saved = read_document(required: false)
        associated = associated_connection(saved, config:, profile:)
        return associated if associated

        connections = saved.fetch("connections")
        return preferred_name unless connections.key?(preferred_name)
        return preferred_name if connections.fetch(preferred_name) == normalized

        unique_connection_name(connections, preferred_name, normalized)
      end

      def write(service_account_path, name: "default", config: nil, profile: nil, select: true)
        normalized = ServiceAccount.new(service_account_path).path
        connection_name = validate_connection_name!(name)
        validate_association!(config, profile)
        raise AuthenticationError, "select must be true or false" unless [true, false].include?(select)

        saved = read_document(required: false)
        if connection_name != "default" &&
           saved.fetch("configs").empty? &&
           saved.fetch("connections") == { "default" => normalized }
          saved.fetch("connections").delete("default")
        end
        saved.fetch("connections")[connection_name] = normalized
        associate!(saved, config:, profile:, connection: connection_name, select:) if config
        persist(saved)
      end

      def select(config:, profile:, connection: nil)
        validate_association!(config, profile)
        saved = read_document(required: true)
        selected = resolve_name(saved, name: connection, config:, profile:)
        associate!(saved, config:, profile:, connection: selected, select: true)
        persist(saved)
        selection(config:)
      end

      def selection(config:)
        saved = read_document(required: false)
        entry = saved.fetch("configs")[config_key(config)]
        return nil unless entry

        profile = entry.fetch("selected_profile")
        {
          "profile" => profile,
          "connection" => entry.fetch("profile_connections").fetch(profile)
        }.freeze
      end

      def selected_profile(config:)
        selection(config:)&.fetch("profile")
      end

      def profile_connection(config:, profile:)
        saved = read_document(required: false)
        associated = associated_connection(saved, config:, profile:)
        return associated if associated

        resolve_name(saved, name: nil, config:, profile:)
      rescue AuthenticationError
        nil
      end

      def summaries
        saved = read_document(required: false)
        selected_names = saved.fetch("configs").values.flat_map do |entry|
          entry.fetch("profile_connections").values
        end.uniq
        saved.fetch("connections").sort.map do |name, service_account_path|
          {
            "name" => name,
            "available" => File.file?(service_account_path),
            "in_use" => selected_names.include?(name)
          }.freeze
        end.freeze
      end

      private

      def persist(document)
        directory = File.dirname(path)
        FileUtils.mkdir_p(directory, mode: 0o700)
        File.chmod(0o700, directory)
        temporary = File.join(directory, ".connection.#{Process.pid}.#{SecureRandom.hex(6)}.tmp")
        payload = JSON.generate(ordered_document(document)) << "\n"

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

      def read_document(required:)
        unless File.file?(path)
          raise AuthenticationError, missing_connection_message if required

          return empty_document
        end
        raise AuthenticationError, "The saved Analytics Ops connection is too large" if File.size(path) > MAX_BYTES

        parsed = JSON.parse(File.binread(path, MAX_BYTES + 1), max_nesting: 8)
        return migrate_legacy(parsed) if legacy_document?(parsed)

        validate_document!(parsed)
        parsed
      rescue AnalyticsOps::Error
        raise
      rescue JSON::ParserError, ArgumentError, SystemCallError
        raise AuthenticationError, invalid_connection_message
      end

      def empty_document
        { "version" => VERSION, "connections" => {}, "configs" => {} }
      end

      def legacy_document?(document)
        document.is_a?(Hash) &&
          document.keys.sort == LEGACY_FIELDS &&
          document["version"] == LEGACY_VERSION &&
          document["service_account_path"].is_a?(String)
      end

      def migrate_legacy(document)
        empty_document.merge(
          "connections" => { "default" => document.fetch("service_account_path") }
        )
      end

      def validate_document!(document)
        valid = document.is_a?(Hash) &&
                document.keys.sort == FIELDS &&
                document["version"] == VERSION &&
                valid_connections?(document["connections"]) &&
                valid_configs?(document["configs"], document["connections"])
        raise AuthenticationError, invalid_connection_message unless valid
      end

      def valid_connections?(connections)
        connections.is_a?(Hash) && connections.all? do |name, service_account_path|
          CONNECTION_NAME.match?(name.to_s) &&
            service_account_path.is_a?(String) &&
            !service_account_path.empty? &&
            !service_account_path.match?(CONTROL_CHARACTERS)
        end
      end

      def valid_configs?(configs, connections)
        configs.is_a?(Hash) &&
          configs.all? { |config, entry| valid_config_entry?(config, entry, connections) }
      end

      def valid_config_entry?(config, entry, connections)
        return false unless valid_config_name?(config)
        return false unless entry.is_a?(Hash) && entry.keys.sort == CONFIG_FIELDS

        profile = entry["selected_profile"]
        mappings = entry["profile_connections"]
        PROFILE_NAME.match?(profile.to_s) &&
          mappings.is_a?(Hash) &&
          mappings.key?(profile) &&
          mappings.all? do |profile_name, connection_name|
            valid_profile_connection?(profile_name, connection_name, connections)
          end
      end

      def valid_config_name?(config)
        config.is_a?(String) && !config.empty? && !config.match?(CONTROL_CHARACTERS)
      end

      def valid_profile_connection?(profile, connection, connections)
        PROFILE_NAME.match?(profile.to_s) &&
          CONNECTION_NAME.match?(connection.to_s) &&
          connections.key?(connection)
      end

      def resolve_name(document, name:, config:, profile:)
        connections = document.fetch("connections")
        if name
          selected = validate_connection_name!(name)
          return selected if connections.key?(selected)

          raise AuthenticationError, "Unknown Analytics Ops connection #{selected.inspect}; " \
                                     "available connections: #{connections.keys.sort.join(", ")}"
        end

        associated = associated_connection(document, config:, profile:)
        return associated if associated && connections.key?(associated)
        return profile if profile && connections.key?(profile)
        return connections.keys.first if connections.length == 1
        return "default" if connections.key?("default")

        raise AuthenticationError, choose_connection_message(connections)
      end

      def associated_connection(document, config:, profile:)
        return nil unless config

        entry = document.fetch("configs")[config_key(config)]
        return nil unless entry

        selected_profile = profile || entry.fetch("selected_profile")
        entry.fetch("profile_connections")[selected_profile]
      end

      def associate!(document, config:, profile:, connection:, select:)
        key = config_key(config)
        entry = document.fetch("configs")[key] ||= {
          "selected_profile" => profile,
          "profile_connections" => {}
        }
        entry.fetch("profile_connections")[profile] = connection
        entry["selected_profile"] = profile if select
      end

      def validate_association!(config, profile)
        return if config.nil? && profile.nil?
        unless config.is_a?(String) && !config.empty? && !config.match?(CONTROL_CHARACTERS)
          raise AuthenticationError, "The Analytics Ops configuration path is invalid"
        end

        validate_profile_name!(profile)
      end

      def validate_connection_name!(name)
        string = name.to_s
        return string if CONNECTION_NAME.match?(string)

        raise AuthenticationError,
              "Connection names must start with a letter and use only letters, numbers, hyphens, or underscores"
      end

      def validate_profile_name!(profile)
        string = profile.to_s
        return string if PROFILE_NAME.match?(string)

        raise AuthenticationError,
              "Profile names must start with a letter and use only letters, numbers, or underscores"
      end

      def config_key(config)
        expanded = File.expand_path(config)
        File.exist?(expanded) ? File.realpath(expanded) : expanded
      rescue SystemCallError
        File.expand_path(config)
      end

      def ordered_document(document)
        connections = document.fetch("connections").sort.to_h
        configs = document.fetch("configs").sort.to_h do |config, entry|
          [
            config,
            {
              "selected_profile" => entry.fetch("selected_profile"),
              "profile_connections" => entry.fetch("profile_connections").sort.to_h
            }
          ]
        end
        { "version" => VERSION, "connections" => connections, "configs" => configs }
      end

      def unique_connection_name(connections, preferred, service_account_path)
        2.upto(9_999) do |number|
          suffix = "_#{number}"
          candidate = "#{preferred.slice(0, 64 - suffix.length)}#{suffix}"
          return candidate unless connections.key?(candidate)
          return candidate if connections.fetch(candidate) == service_account_path
        end

        raise AuthenticationError, "Cannot choose a unique Analytics Ops connection name; use --connection NAME"
      end

      def missing_connection_message
        "No service account is configured; run " \
          "`analytics-ops setup --service-account /absolute/path/to/service-account.json`"
      end

      def choose_connection_message(connections)
        available = connections.keys.sort.join(", ")
        "More than one Analytics Ops connection is saved. Use --connection NAME; available connections: #{available}"
      end

      def invalid_connection_message
        "The saved Analytics Ops connection is invalid; rerun setup with --service-account"
      end
    end
  end
end
