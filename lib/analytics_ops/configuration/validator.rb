# frozen_string_literal: true

# Strict configuration validation.

require "uri"

module AnalyticsOps
  module Configuration
    # Fail-closed validator and normalizer for configuration version 1.
    class Validator
      TOP_LEVEL_KEYS = %w[version profiles].freeze
      PROFILE_KEYS = %w[property_id streams retention google_signals key_events custom_dimensions custom_metrics
                        manual_requirements].freeze
      STREAM_KEYS = %w[stream_id default_uri enhanced_measurement].freeze
      ENHANCED_MEASUREMENT_KEYS = %w[enabled experimental].freeze
      RETENTION_KEYS = %w[event_data user_data reset_on_new_activity].freeze
      GOOGLE_SIGNALS_KEYS = %w[state experimental].freeze
      DIMENSION_KEYS = %w[parameter_name display_name description scope disallow_ads_personalization].freeze
      METRIC_KEYS = %w[
        parameter_name display_name description scope measurement_unit restricted_metric_types
      ].freeze
      RETENTION_VALUES = %w[2_months 14_months 26_months 38_months 50_months].freeze
      USER_RETENTION_VALUES = %w[2_months 14_months].freeze
      DIMENSION_SCOPES = %w[event user item].freeze
      METRIC_UNITS = %w[standard currency feet meters kilometers miles milliseconds seconds minutes hours].freeze
      RESTRICTED_METRIC_TYPES = %w[cost_data revenue_data].freeze
      SECRET_KEY = /
        (?:\A|_)
        (?:
          credentials?|password|private_key|client_(?:id|secret)|
          access_token|refresh_token|api_key|service_account|oauth
        )
        (?:\z|_)
      /ix
      NAME = /\A[a-z][a-z0-9_]*\z/i
      DISPLAY_NAME = /\A[A-Za-z][A-Za-z0-9_ ]{0,81}\z/
      EVENT_NAME = /\A[a-z][a-z0-9_]{0,39}\z/i
      ID = /\A\d{1,50}\z/

      def initialize(raw)
        @raw = raw
      end

      def call
        hash!(@raw, "$root")
        reject_secret_keys!(@raw)
        exact_keys!(@raw, TOP_LEVEL_KEYS, "$root")
        unless @raw["version"] == 1
          raise UnsupportedVersionError, "Unsupported configuration version #{@raw["version"].inspect}; expected 1"
        end

        profiles = hash!(@raw["profiles"], "profiles")
        raise ConfigurationError, "profiles must contain at least one profile" if profiles.empty?

        normalized = profiles.to_h do |name, profile|
          validate_name!(name, "profile name")
          [name, validate_profile(name, profile)]
        end

        Document.new(version: 1, profiles: normalized)
      end

      private

      def validate_profile(name, raw)
        path = "profiles.#{name}"
        profile = hash!(raw, path)
        exact_keys!(profile, PROFILE_KEYS, path)
        property_id = id!(required(profile, "property_id", path), "#{path}.property_id")

        DesiredState.new(
          profile: name,
          property_id:,
          streams: validate_streams(profile.fetch("streams", {}), path),
          retention: validate_retention(profile["retention"], path),
          key_events: validate_key_events(profile.fetch("key_events", []), path),
          custom_dimensions: validate_dimensions(profile.fetch("custom_dimensions", []), path),
          custom_metrics: validate_metrics(profile.fetch("custom_metrics", []), path),
          manual_requirements: validate_manual_requirements(profile.fetch("manual_requirements", []), path),
          google_signals: validate_google_signals(profile["google_signals"], path)
        )
      end

      def validate_streams(raw, profile_path)
        path = "#{profile_path}.streams"
        streams = hash!(raw, path).map do |name, value|
          validate_name!(name, "#{path} key")
          stream_path = "#{path}.#{name}"
          stream = hash!(value, stream_path)
          exact_keys!(stream, STREAM_KEYS, stream_path)

          {
            "name" => name,
            "stream_id" => id!(required(stream, "stream_id", stream_path), "#{stream_path}.stream_id"),
            "default_uri" => validate_uri(stream["default_uri"], "#{stream_path}.default_uri"),
            "enhanced_measurement" => validate_enhanced_measurement(stream["enhanced_measurement"], stream_path)
          }
        end
        streams.sort_by { |stream| stream.fetch("name") }
      end

      def validate_enhanced_measurement(raw, stream_path)
        return nil if raw.nil?

        path = "#{stream_path}.enhanced_measurement"
        settings = hash!(raw, path)
        exact_keys!(settings, ENHANCED_MEASUREMENT_KEYS, path)
        enabled = boolean!(required(settings, "enabled", path), "#{path}.enabled")
        experimental = boolean!(required(settings, "experimental", path), "#{path}.experimental")
        raise ConfigurationError, "#{path}.experimental must be true" unless experimental

        { "enabled" => enabled, "experimental" => true }
      end

      def validate_retention(raw, profile_path)
        return nil if raw.nil?

        path = "#{profile_path}.retention"
        retention = hash!(raw, path)
        exact_keys!(retention, RETENTION_KEYS, path)
        event_data = enum!(required(retention, "event_data", path), RETENTION_VALUES, "#{path}.event_data")
        user_data = enum!(required(retention, "user_data", path), USER_RETENTION_VALUES, "#{path}.user_data")
        reset = boolean!(required(retention, "reset_on_new_activity", path), "#{path}.reset_on_new_activity")

        { "event_data" => event_data, "user_data" => user_data, "reset_on_new_activity" => reset }
      end

      def validate_google_signals(raw, profile_path)
        return nil if raw.nil?

        path = "#{profile_path}.google_signals"
        settings = hash!(raw, path)
        exact_keys!(settings, GOOGLE_SIGNALS_KEYS, path)
        state = enum!(required(settings, "state", path), %w[enabled disabled], "#{path}.state")
        experimental = boolean!(required(settings, "experimental", path), "#{path}.experimental")
        raise ConfigurationError, "#{path}.experimental must be true" unless experimental

        { "state" => state, "experimental" => true }
      end

      def validate_key_events(raw, profile_path)
        path = "#{profile_path}.key_events"
        values = array!(raw, path).map.with_index do |event_name, index|
          string = string!(event_name, "#{profile_path}.key_events[#{index}]")
          unless EVENT_NAME.match?(string)
            raise ConfigurationError, "#{profile_path}.key_events[#{index}] is not a valid GA4 event name"
          end

          string
        end

        ensure_unique_strings!(values, path)
      end

      def validate_dimensions(raw, profile_path)
        path = "#{profile_path}.custom_dimensions"
        values = array!(raw, path).map.with_index do |value, index|
          item_path = "#{path}[#{index}]"
          dimension = hash!(value, item_path)
          exact_keys!(dimension, DIMENSION_KEYS, item_path)
          scope = enum!(required(dimension, "scope", item_path), DIMENSION_SCOPES, "#{item_path}.scope")
          parameter = parameter_name!(required(dimension, "parameter_name", item_path), scope, item_path)

          {
            "parameter_name" => parameter,
            "display_name" => display_name!(required(dimension, "display_name", item_path), item_path),
            "description" => description!(dimension.fetch("description", ""), item_path),
            "scope" => scope,
            "disallow_ads_personalization" => boolean!(dimension.fetch("disallow_ads_personalization", false),
                                                       "#{item_path}.disallow_ads_personalization")
          }.tap do |normalized|
            if normalized.fetch("disallow_ads_personalization") && scope != "user"
              raise ConfigurationError, "#{item_path}.disallow_ads_personalization is valid only for user scope"
            end
          end
        end

        ensure_unique!(values, %w[scope parameter_name], path)
      end

      def validate_metrics(raw, profile_path)
        path = "#{profile_path}.custom_metrics"
        values = array!(raw, path).map.with_index do |value, index|
          item_path = "#{path}[#{index}]"
          metric = hash!(value, item_path)
          exact_keys!(metric, METRIC_KEYS, item_path)
          scope = enum!(required(metric, "scope", item_path), ["event"], "#{item_path}.scope")

          measurement_unit = enum!(metric.fetch("measurement_unit", "standard"), METRIC_UNITS,
                                   "#{item_path}.measurement_unit")
          restricted_types = validate_restricted_metric_types(
            metric.fetch("restricted_metric_types", []), measurement_unit, item_path
          )

          {
            "parameter_name" => parameter_name!(required(metric, "parameter_name", item_path), scope, item_path),
            "display_name" => display_name!(required(metric, "display_name", item_path), item_path),
            "description" => description!(metric.fetch("description", ""), item_path),
            "scope" => scope,
            "measurement_unit" => measurement_unit,
            "restricted_metric_types" => restricted_types
          }
        end

        ensure_unique!(values, ["parameter_name"], path)
      end

      def validate_restricted_metric_types(raw, measurement_unit, item_path)
        path = "#{item_path}.restricted_metric_types"
        values = array!(raw, path).map.with_index do |value, index|
          enum!(value, RESTRICTED_METRIC_TYPES, "#{path}[#{index}]")
        end
        values = ensure_unique_strings!(values, path)
        if measurement_unit == "currency" && values.empty?
          raise ConfigurationError, "#{path} requires cost_data or revenue_data for a currency metric"
        end
        if measurement_unit != "currency" && !values.empty?
          raise ConfigurationError, "#{path} is valid only for a currency metric"
        end

        values
      end

      def validate_manual_requirements(raw, profile_path)
        path = "#{profile_path}.manual_requirements"
        values = array!(raw, path).map.with_index do |value, index|
          requirement = string!(value, "#{path}[#{index}]")
          validate_name!(requirement, "#{path}[#{index}]")
          requirement
        end

        ensure_unique_strings!(values, path)
      end

      def parameter_name!(value, scope, path)
        parameter = string!(value, "#{path}.parameter_name")
        maximum = scope == "user" ? 24 : 40
        unless NAME.match?(parameter) && parameter.length <= maximum
          raise ConfigurationError,
                "#{path}.parameter_name must start with a letter and be at most #{maximum} characters"
        end

        parameter
      end

      def display_name!(value, path)
        name = string!(value, "#{path}.display_name")
        unless DISPLAY_NAME.match?(name)
          raise ConfigurationError,
                "#{path}.display_name must start with a letter and use only letters, numbers, spaces, or underscores"
        end

        name
      end

      def description!(value, path)
        description = string!(value, "#{path}.description")
        if description.length > 150 || description.match?(/[\u0000-\u001f\u007f]/)
          raise ConfigurationError, "#{path}.description must be printable and at most 150 characters"
        end

        description
      end

      def validate_uri(value, path)
        return nil if value.nil?

        string = string!(value, path)
        uri = URI.parse(string)
        unless string.length <= 2_048 && !string.match?(/[\u0000-\u001f\u007f]/) &&
               %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo
          raise ConfigurationError, "#{path} must be an absolute HTTP or HTTPS URI without credentials"
        end

        string
      rescue URI::InvalidURIError
        raise ConfigurationError, "#{path} must be a valid URI"
      end

      def reject_secret_keys!(value, path = "$root")
        case value
        when Hash
          value.each do |key, child|
            raise ConfigurationError, "Secret-shaped key #{path}.#{key} is forbidden" if key.to_s.match?(SECRET_KEY)

            reject_secret_keys!(child, "#{path}.#{key}")
          end
        when Array
          value.each_with_index { |child, index| reject_secret_keys!(child, "#{path}[#{index}]") }
        end
      end

      def exact_keys!(hash, allowed, path)
        keys = hash.keys
        non_strings = keys.grep_v(String)
        raise ConfigurationError, "#{path} keys must be strings" unless non_strings.empty?

        unknown = keys - allowed
        raise ConfigurationError, "Unknown configuration key #{path}.#{unknown.first}" unless unknown.empty?
      end

      def ensure_unique!(values, keys, path)
        grouped = values.group_by do |value|
          keys.map do |key|
            value.fetch(key)
          end
        end
        duplicate = grouped.find { |_identity, rows| rows.length > 1 }
        raise ConfigurationError, "Duplicate identity in #{path}: #{duplicate.first.join(":")}" if duplicate

        values.sort_by { |value| keys.map { |key| value.fetch(key) } }
      end

      def ensure_unique_strings!(values, path)
        duplicate = values.tally.find { |_value, count| count > 1 }&.first
        raise ConfigurationError, "Duplicate value in #{path}: #{duplicate}" if duplicate

        values.sort
      end

      def required(hash, key, path)
        return hash[key] if hash.key?(key)

        raise ConfigurationError, "Missing required configuration key #{path}.#{key}"
      end

      def hash!(value, path)
        return value if value.is_a?(Hash)

        raise ConfigurationError, "#{path} must be a mapping"
      end

      def array!(value, path)
        return value if value.is_a?(Array)

        raise ConfigurationError, "#{path} must be an array"
      end

      def string!(value, path)
        if value.is_a?(String)
          if Redaction.credential_shaped?(value)
            raise ConfigurationError, "Credential-shaped value at #{path} is forbidden"
          end

          return value
        end

        raise ConfigurationError, "#{path} must be a string"
      end

      def boolean!(value, path)
        return value if [true, false].include?(value)

        raise ConfigurationError, "#{path} must be true or false"
      end

      def id!(value, path)
        string = string!(value, path)
        raise ConfigurationError, "#{path} must be a numeric identifier encoded as a string" unless ID.match?(string)

        string
      end

      def enum!(value, allowed, path)
        string = string!(value, path)
        return string if allowed.include?(string)

        raise ConfigurationError, "#{path} must be one of: #{allowed.join(", ")}"
      end

      def validate_name!(value, path)
        string = string!(value, path)
        return string if NAME.match?(string) && string.length <= 64

        raise ConfigurationError, "#{path} must use letters, numbers, and underscores and start with a letter"
      end
    end
  end
end
