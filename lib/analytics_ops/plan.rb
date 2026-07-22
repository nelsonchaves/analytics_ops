# frozen_string_literal: true

require "json"
require "securerandom"
require "uri"

module AnalyticsOps
  # Versioned, deterministic, credential-free input to the apply workflow.
  class Plan
    FORMAT_VERSION = 1
    MAX_BYTES = 1_048_576
    MAX_CHANGES = 10_000
    MAX_FINDINGS = 10_000
    OPERATIONS = %w[create update].freeze
    RESOURCE_TYPES = %w[data_stream retention key_event custom_dimension custom_metric].freeze
    API_MATURITIES = %w[stable beta experimental].freeze
    FINDING_SEVERITIES = %w[drift manual experimental warning].freeze
    PROFILE = /\A[a-z][a-z0-9_]{0,63}\z/i
    ID = /\A\d{1,50}\z/
    NAME = /\A[a-z][a-z0-9_]{0,63}\z/i
    EVENT_NAME = /\A[a-z][a-z0-9_]{0,39}\z/i
    PARAMETER_NAME = /\A[a-z][a-z0-9_]{0,39}\z/i
    FINGERPRINT = /\Asha256:[a-f0-9]{64}\z/
    CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/
    SECRET_KEY = Configuration::Validator::SECRET_KEY
    RETENTION_VALUES = Configuration::Validator::RETENTION_VALUES
    USER_RETENTION_VALUES = Configuration::Validator::USER_RETENTION_VALUES
    DIMENSION_SCOPES = Configuration::Validator::DIMENSION_SCOPES
    METRIC_UNITS = Configuration::Validator::METRIC_UNITS
    RESTRICTED_METRIC_TYPES = Configuration::Validator::RESTRICTED_METRIC_TYPES

    RESOURCE_FIELDS = {
      "data_stream" => %w[id name display_name type default_uri measurement_id],
      "retention" => %w[name event_data user_data reset_on_new_activity],
      "key_event" => %w[event_name counting_method],
      "custom_dimension" => %w[parameter_name display_name description scope disallow_ads_personalization],
      "custom_metric" => %w[
        parameter_name display_name description scope measurement_unit restricted_metric_types
      ]
    }.freeze
    NAMED_DEFINITION_FIELDS = {
      "custom_dimension" => ["name", *RESOURCE_FIELDS.fetch("custom_dimension")],
      "custom_metric" => ["name", *RESOURCE_FIELDS.fetch("custom_metric")]
    }.freeze
    MUTABLE_FIELDS = {
      "data_stream" => %w[default_uri],
      "retention" => %w[event_data user_data reset_on_new_activity],
      "custom_dimension" => %w[display_name description disallow_ads_personalization],
      "custom_metric" => %w[display_name description]
    }.freeze

    # Detects duplicate JSON object keys before ordinary JSON parsing can discard them.
    class DuplicateKeyDetector
      NUMBER = /-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/

      def initialize(source)
        @source = source
        @index = 0
      end

      def call
        value
        whitespace
        raise InvalidPlanError, "Unexpected data after plan JSON" unless @index == @source.bytesize
      end

      private

      def value
        whitespace
        case byte
        when 123 then object
        when 91 then array
        when 34 then string
        when 116 then literal("true")
        when 102 then literal("false")
        when 110 then literal("null")
        else number
        end
      end

      def object
        consume(123)
        whitespace
        return consume(125) if byte == 125

        keys = {}
        loop do
          whitespace
          key = string
          raise InvalidPlanError, "Duplicate JSON object field #{key.inspect}" if keys.key?(key)

          keys[key] = true
          whitespace
          consume(58)
          value
          whitespace
          break consume(125) if byte == 125

          consume(44)
        end
      end

      def array
        consume(91)
        whitespace
        return consume(93) if byte == 93

        loop do
          value
          whitespace
          break consume(93) if byte == 93

          consume(44)
        end
      end

      def string
        start = @index
        consume(34)
        loop do
          current = byte
          raise InvalidPlanError, "Unterminated JSON string" unless current

          if current == 92
            @index += 2
          elsif current == 34
            @index += 1
            return JSON.parse(@source.byteslice(start...@index))
          else
            @index += 1
          end
        end
      end

      def literal(expected)
        actual = @source.byteslice(@index, expected.bytesize)
        raise InvalidPlanError, "Invalid plan JSON literal" unless actual == expected

        @index += expected.bytesize
      end

      def number
        match = NUMBER.match(@source, @index)
        raise InvalidPlanError, "Invalid plan JSON value" unless match && match.begin(0) == @index

        @index = match.end(0)
      end

      def whitespace
        @index += 1 while [9, 10, 13, 32].include?(byte)
      end

      def consume(expected)
        raise InvalidPlanError, "Invalid plan JSON structure" unless byte == expected

        @index += 1
      end

      def byte
        @source.getbyte(@index)
      end
    end

    # One approved create or update operation.
    class Change < Resources::Value
      fields :resource_type, :resource_identity, :operation, :api_maturity,
             :before, :after, :reversible, :rollback

      def self.from_h(raw)
        hash = Plan.string_keyed_hash(raw, "change")
        Plan.exact_keys!(hash, field_names.map(&:to_s), "change")
        new(**field_names.to_h { |name| [name, hash.fetch(name.to_s)] })
      rescue KeyError => error
        raise InvalidPlanError, "Missing plan change field #{error.key}"
      end
    end

    # Read-only drift, manual, or experimental information attached to a plan.
    class Finding < Resources::Value
      fields :severity, :code, :resource_identity, :message

      def self.from_h(raw)
        hash = Plan.string_keyed_hash(raw, "finding")
        Plan.exact_keys!(hash, field_names.map(&:to_s), "finding")
        new(**field_names.to_h { |name| [name, hash.fetch(name.to_s)] })
      rescue KeyError => error
        raise InvalidPlanError, "Missing plan finding field #{error.key}"
      end
    end

    attr_reader :format_version, :profile, :property_id, :snapshot_fingerprint, :changes, :findings

    def initialize(profile:, property_id:, snapshot_fingerprint:, changes:, findings:, format_version: FORMAT_VERSION)
      @format_version = self.class.integer(format_version, "format_version", expected: FORMAT_VERSION)
      @profile = self.class.pattern_string(profile, "profile", PROFILE)
      @property_id = self.class.pattern_string(property_id, "property_id", ID)
      @snapshot_fingerprint = self.class.pattern_string(snapshot_fingerprint, "snapshot_fingerprint", FINGERPRINT)
      @changes = validated_values(changes, Change, "changes", MAX_CHANGES)
      @findings = validated_values(findings, Finding, "findings", MAX_FINDINGS)
      validate_changes!
      validate_findings!
      @changes = Canonical.deep_freeze(@changes.sort_by do |change|
        [change.resource_type, change.resource_identity, change.operation]
      end)
      @findings = Canonical.deep_freeze(@findings.sort_by do |finding|
        [finding.severity, finding.code, finding.resource_identity]
      end)
      freeze
    end

    def empty?
      changes.empty?
    end

    def drift?
      !empty? || findings.any? { |finding| finding.severity == "drift" }
    end

    def to_h
      {
        "format_version" => format_version,
        "profile" => profile,
        "property_id" => property_id,
        "snapshot_fingerprint" => snapshot_fingerprint,
        "changes" => changes.map(&:to_h),
        "findings" => findings.map(&:to_h)
      }
    end

    def to_json(*_arguments)
      "#{JSON.pretty_generate(Canonical.normalize(to_h))}\n"
    end

    def write(path)
      expanded = File.expand_path(path)
      temporary = File.join(File.dirname(expanded),
                            ".#{File.basename(expanded)}.#{Process.pid}.#{SecureRandom.hex(6)}.tmp")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(to_json)
        file.flush
        file.fsync
      end
      File.rename(temporary, expanded)
      File.chmod(0o600, expanded)
      expanded
    rescue SystemCallError => error
      raise InvalidPlanError, "Cannot write plan #{Redaction.message(path)}: #{Redaction.message(error.message)}"
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end

    def self.load(path)
      contents = File.binread(path, MAX_BYTES + 1)
      raise InvalidPlanError, "Plan exceeds #{MAX_BYTES} bytes" if contents.bytesize > MAX_BYTES

      parsed = JSON.parse(contents, max_nesting: 100)
      DuplicateKeyDetector.new(contents).call
      from_h(parsed)
    rescue JSON::ParserError => error
      raise InvalidPlanError, "Invalid plan JSON: #{Redaction.message(error.message)}"
    rescue SystemCallError => error
      raise InvalidPlanError, "Cannot read plan #{Redaction.message(path)}: #{Redaction.message(error.message)}"
    end

    def self.from_h(raw)
      hash = string_keyed_hash(raw, "plan")
      exact_keys!(hash, %w[format_version profile property_id snapshot_fingerprint changes findings], "plan")
      changes = array(hash.fetch("changes"), "plan.changes").map { |change| Change.from_h(change) }
      findings = array(hash.fetch("findings"), "plan.findings").map { |finding| Finding.from_h(finding) }

      new(
        format_version: hash.fetch("format_version"),
        profile: hash.fetch("profile"),
        property_id: hash.fetch("property_id"),
        snapshot_fingerprint: hash.fetch("snapshot_fingerprint"),
        changes:,
        findings:
      )
    rescue KeyError => error
      raise InvalidPlanError, "Missing plan field #{error.key}"
    end

    def self.string_keyed_hash(value, path)
      raise InvalidPlanError, "#{path} must be an object" unless value.is_a?(Hash)
      raise InvalidPlanError, "#{path} keys must be strings" unless value.keys.all?(String)

      value
    end

    def self.array(value, path)
      raise InvalidPlanError, "#{path} must be an array" unless value.is_a?(Array)

      value
    end

    def self.exact_keys!(hash, allowed, path)
      unknown = hash.keys - allowed
      missing = allowed - hash.keys
      raise InvalidPlanError, "Unknown #{path} field #{unknown.first}" unless unknown.empty?
      raise InvalidPlanError, "Missing #{path} field #{missing.first}" unless missing.empty?
    end

    def self.pattern_string(value, path, pattern, maximum: 500)
      unless value.is_a?(String) && value.length.between?(1, maximum) && pattern.match?(value) &&
             !CONTROL_CHARACTERS.match?(value)
        raise InvalidPlanError, "Invalid #{path}"
      end

      value.dup.freeze
    end

    def self.printable_string(value, path, minimum: 1, maximum: 500)
      unless value.is_a?(String) && value.length.between?(minimum, maximum) && !CONTROL_CHARACTERS.match?(value) &&
             !Redaction.credential_shaped?(value)
        raise InvalidPlanError, "Invalid #{path}"
      end

      value
    end

    def self.integer(value, path, expected: nil)
      raise InvalidPlanError, "Invalid #{path}" unless value.is_a?(Integer)
      raise InvalidPlanError, "Unsupported #{path} #{value.inspect}" if expected && value != expected

      value
    end

    private

    def validated_values(values, type, path, maximum)
      self.class.array(values, path)
      raise InvalidPlanError, "#{path} exceeds #{maximum} entries" if values.length > maximum
      raise InvalidPlanError, "#{path} must contain #{type.name} values" unless values.all?(type)

      values.dup
    end

    def validate_changes!
      changes.each_with_index { |change, index| validate_change!(change, "changes[#{index}]") }
      identities = changes.map { |change| [change.resource_type, change.resource_identity] }
      return if identities.uniq.length == identities.length

      raise InvalidPlanError,
            "Plan contains duplicate resource changes"
    end

    def validate_change!(change, path)
      enum!(change.resource_type, RESOURCE_TYPES, "#{path}.resource_type")
      enum!(change.operation, OPERATIONS, "#{path}.operation")
      enum!(change.api_maturity, API_MATURITIES, "#{path}.api_maturity")
      boolean!(change.reversible, "#{path}.reversible")
      self.class.printable_string(change.rollback, "#{path}.rollback", maximum: 500)
      validate_operation!(change, path)
      validate_payload!(change, path)
    end

    def validate_operation!(change, path)
      allowed = case change.resource_type
                when "key_event"
                  ["create"]
                when "data_stream", "retention"
                  ["update"]
                else
                  OPERATIONS
                end
      return if allowed.include?(change.operation)

      raise InvalidPlanError, "Unsupported #{change.operation} operation for #{change.resource_type} at #{path}"
    end

    def validate_payload!(change, path)
      if change.operation == "create"
        raise InvalidPlanError, "#{path}.before must be null for create" unless change.before.nil?

        validate_create!(change, path)
      else
        before = payload_hash(change.before, "#{path}.before")
        after = payload_hash(change.after, "#{path}.after")
        validate_update!(change, before, after, path)
      end
    end

    def validate_create!(change, path)
      after = payload_hash(change.after, "#{path}.after")
      fields = RESOURCE_FIELDS.fetch(change.resource_type)
      self.class.exact_keys!(after, fields, "#{path}.after")
      validate_resource_values!(change.resource_type, after, "#{path}.after", named: false, desired: true)
      validate_identity!(change, after, path)
    end

    def validate_update!(change, before, after, path)
      fields = NAMED_DEFINITION_FIELDS.fetch(change.resource_type, RESOURCE_FIELDS.fetch(change.resource_type))
      self.class.exact_keys!(before, fields, "#{path}.before")
      self.class.exact_keys!(after, fields, "#{path}.after")
      validate_resource_values!(change.resource_type, before, "#{path}.before", named: true, desired: false)
      validate_resource_values!(change.resource_type, after, "#{path}.after", named: true, desired: true)
      validate_identity!(change, after, path)
      validate_immutable_fields!(change.resource_type, before, after, path)
      validate_property_resource_name!(change.resource_type, before, path)
      validate_property_resource_name!(change.resource_type, after, path)
    end

    def payload_hash(value, path)
      hash = self.class.string_keyed_hash(value, path)
      reject_secret_keys!(hash, path)
      hash
    end

    def validate_resource_values!(resource_type, payload, path, named:, desired:)
      case resource_type
      when "data_stream"
        validate_data_stream_values!(payload, path, desired:)
      when "retention"
        validate_retention_values!(payload, path)
      when "key_event"
        validate_key_event_values!(payload, path)
      when "custom_dimension"
        validate_custom_dimension_values!(payload, path, named:, desired:)
      when "custom_metric"
        validate_custom_metric_values!(payload, path, named:, desired:)
      end
    end

    def validate_data_stream_values!(payload, path, desired:)
      id_string!(payload.fetch("id"), "#{path}.id")
      resource_name!(payload.fetch("name"), "dataStreams", "#{path}.name")
      text!(payload.fetch("display_name"), "#{path}.display_name", minimum: 0, maximum: 100)
      enum!(payload.fetch("type"), ["web"], "#{path}.type")
      optional_uri!(payload.fetch("default_uri"), "#{path}.default_uri")
      raise InvalidPlanError, "Invalid #{path}.default_uri" if desired && payload.fetch("default_uri").nil?

      optional_text!(payload.fetch("measurement_id"), "#{path}.measurement_id", maximum: 64)
    end

    def validate_retention_values!(payload, path)
      resource_name!(payload.fetch("name"), "dataRetentionSettings", "#{path}.name", singleton: true)
      enum!(payload.fetch("event_data"), RETENTION_VALUES, "#{path}.event_data")
      enum!(payload.fetch("user_data"), USER_RETENTION_VALUES, "#{path}.user_data")
      boolean!(payload.fetch("reset_on_new_activity"), "#{path}.reset_on_new_activity")
    end

    def validate_key_event_values!(payload, path)
      event_name!(payload.fetch("event_name"), "#{path}.event_name")
      enum!(payload.fetch("counting_method"), %w[once_per_event once_per_session], "#{path}.counting_method")
    end

    def validate_custom_dimension_values!(payload, path, named:, desired:)
      resource_name!(payload.fetch("name"), "customDimensions", "#{path}.name") if named
      scope = payload.fetch("scope")
      maximum = scope == "user" ? 24 : 40
      parameter_name!(payload.fetch("parameter_name"), "#{path}.parameter_name", maximum:)
      display_name!(payload.fetch("display_name"), "#{path}.display_name", desired:)
      text!(payload.fetch("description"), "#{path}.description", minimum: 0, maximum: 150)
      enum!(scope, DIMENSION_SCOPES, "#{path}.scope")
      disallow_ads = payload.fetch("disallow_ads_personalization")
      boolean!(disallow_ads, "#{path}.disallow_ads_personalization")
      return unless disallow_ads && scope != "user"

      raise InvalidPlanError, "#{path}.disallow_ads_personalization is valid only for user scope"
    end

    def validate_custom_metric_values!(payload, path, named:, desired:)
      resource_name!(payload.fetch("name"), "customMetrics", "#{path}.name") if named
      parameter_name!(payload.fetch("parameter_name"), "#{path}.parameter_name")
      display_name!(payload.fetch("display_name"), "#{path}.display_name", desired:)
      text!(payload.fetch("description"), "#{path}.description", minimum: 0, maximum: 150)
      enum!(payload.fetch("scope"), ["event"], "#{path}.scope")
      measurement_unit = payload.fetch("measurement_unit")
      enum!(measurement_unit, METRIC_UNITS, "#{path}.measurement_unit")
      restricted_types = payload.fetch("restricted_metric_types")
      enum_array!(restricted_types, RESTRICTED_METRIC_TYPES, "#{path}.restricted_metric_types")
      validate_restricted_metric_types!(measurement_unit, restricted_types, path)
    end

    def validate_restricted_metric_types!(measurement_unit, restricted_types, path)
      if measurement_unit == "currency" && restricted_types.empty?
        raise InvalidPlanError, "#{path}.restricted_metric_types is required for a currency metric"
      end
      return if measurement_unit == "currency" || restricted_types.empty?

      raise InvalidPlanError, "#{path}.restricted_metric_types is valid only for a currency metric"
    end

    def validate_identity!(change, payload, path)
      expected = case change.resource_type
                 when "data_stream"
                   "stream:#{payload.fetch("id")}"
                 when "retention"
                   "property:#{property_id}:retention"
                 when "key_event"
                   "event:#{payload.fetch("event_name")}"
                 when "custom_dimension"
                   "#{payload.fetch("scope")}:#{payload.fetch("parameter_name")}"
                 when "custom_metric"
                   payload.fetch("parameter_name")
                 end
      return if change.resource_identity == expected

      raise InvalidPlanError, "#{path}.resource_identity does not match its payload"
    end

    def validate_immutable_fields!(resource_type, before, after, path)
      mutable = MUTABLE_FIELDS.fetch(resource_type)
      changed = (before.keys | after.keys).reject { |key| before[key] == after[key] }
      forbidden = changed - mutable
      raise InvalidPlanError, "#{path} changes immutable field #{forbidden.first}" unless forbidden.empty?
      raise InvalidPlanError, "#{path} update does not change any mutable field" if changed.empty?
    end

    def validate_property_resource_name!(resource_type, payload, path)
      return if resource_type == "key_event"

      expected = case resource_type
                 when "data_stream"
                   "properties/#{property_id}/dataStreams/#{payload.fetch("id")}"
                 when "retention"
                   "properties/#{property_id}/dataRetentionSettings"
                 when "custom_dimension", "custom_metric"
                   prefix = resource_type == "custom_dimension" ? "customDimensions" : "customMetrics"
                   payload.fetch("name").start_with?("properties/#{property_id}/#{prefix}/")
                 end
      valid = expected == true || payload.fetch("name") == expected
      raise InvalidPlanError, "#{path} resource belongs to a different property" unless valid
    end

    def validate_findings!
      findings.each_with_index do |finding, index|
        path = "findings[#{index}]"
        enum!(finding.severity, FINDING_SEVERITIES, "#{path}.severity")
        self.class.pattern_string(finding.code, "#{path}.code", NAME)
        text!(finding.resource_identity, "#{path}.resource_identity", minimum: 1, maximum: 200)
        text!(finding.message, "#{path}.message", minimum: 1, maximum: 1_000)
      end
    end

    def reject_secret_keys!(value, path)
      value.each do |key, child|
        raise InvalidPlanError, "Secret-shaped plan field #{path}.#{key} is forbidden" if SECRET_KEY.match?(key)

        reject_secret_keys!(child, "#{path}.#{key}") if child.is_a?(Hash)
      end
    end

    def enum!(value, allowed, path)
      return value if value.is_a?(String) && allowed.include?(value)

      raise InvalidPlanError, "Invalid #{path}"
    end

    def boolean!(value, path)
      return value if [true, false].include?(value)

      raise InvalidPlanError, "Invalid #{path}; expected true or false"
    end

    def id_string!(value, path)
      self.class.pattern_string(value, path, ID)
    end

    def event_name!(value, path)
      self.class.pattern_string(value, path, EVENT_NAME)
    end

    def parameter_name!(value, path, maximum: 40)
      self.class.pattern_string(value, path, PARAMETER_NAME, maximum:)
    end

    def text!(value, path, minimum:, maximum:)
      self.class.printable_string(value, path, minimum:, maximum:)
    end

    def display_name!(value, path, desired:)
      text!(value, path, minimum: 1, maximum: 82)
      return unless desired && !Configuration::Validator::DISPLAY_NAME.match?(value)

      raise InvalidPlanError, "Invalid #{path}"
    end

    def enum_array!(value, allowed, path)
      self.class.array(value, path)
      unless value.all? { |item| item.is_a?(String) && allowed.include?(item) }
        raise InvalidPlanError, "Invalid #{path}"
      end
      raise InvalidPlanError, "Duplicate values in #{path}" unless value.uniq.length == value.length
    end

    def optional_text!(value, path, maximum:)
      return if value.nil?

      text!(value, path, minimum: 1, maximum:)
    end

    def optional_uri!(value, path)
      return if value.nil?

      text!(value, path, minimum: 1, maximum: 2_048)
      uri = URI.parse(value)
      return if %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo

      raise InvalidPlanError, "Invalid #{path}"
    rescue URI::InvalidURIError
      raise InvalidPlanError, "Invalid #{path}"
    end

    def resource_name!(value, collection, path, singleton: false)
      suffix = singleton ? "" : "/[A-Za-z0-9_-]+"
      pattern = %r{\Aproperties/#{ID.source.delete_prefix("\\A").delete_suffix("\\z")}/#{collection}#{suffix}\z}
      self.class.pattern_string(value, path, pattern, maximum: 200)
    end
  end
end
