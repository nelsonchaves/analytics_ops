# frozen_string_literal: true

# Deterministic read-only planning.

module AnalyticsOps
  # Pure desired-vs-remote comparison. It never owns or contacts a client.
  class Planner
    def initialize(desired_state:, snapshot:)
      @desired = desired_state
      @snapshot = snapshot
      @changes = []
      @findings = []
    end

    def call
      unless @desired.property_id == @snapshot.property_id
        raise ConflictError,
              "Configured property #{@desired.property_id} does not match snapshot #{@snapshot.property_id}"
      end

      plan_streams
      plan_retention
      plan_key_events
      plan_custom_dimensions
      plan_custom_metrics
      add_manual_findings
      add_experimental_findings

      Plan.new(
        profile: @desired.profile,
        property_id: @desired.property_id,
        snapshot_fingerprint: @snapshot.fingerprint,
        changes: @changes,
        findings: @findings
      )
    end

    private

    def plan_streams
      remote = unique_index(@snapshot.streams, "data stream", &:id)
      @desired.streams.each { |desired| plan_stream(remote, desired) }
    end

    def plan_stream(remote, desired)
      stream = remote[desired.fetch("stream_id")]
      identity = "stream:#{desired.fetch("stream_id")}"
      unless stream
        finding("drift", "missing_stream", identity,
                "Configured data stream is not accessible; stream creation is not automatic")
        return
      end

      plan_stream_uri(stream, desired, identity)
      return unless desired["enhanced_measurement"]

      finding(
        "experimental",
        "enhanced_measurement_not_managed",
        identity,
        "Enhanced Measurement is declared but remains an experimental, non-applicable capability"
      )
    end

    def plan_stream_uri(stream, desired, identity)
      return unless desired["default_uri"] && stream.default_uri != desired["default_uri"]

      if stream.type == "web"
        update(
          "data_stream",
          identity,
          stream.to_h,
          stream.to_h.merge("default_uri" => desired.fetch("default_uri")),
          rollback: "Restore the previous web stream default URI"
        )
      else
        finding("drift", "non_web_default_uri", identity, "Only web streams have a configurable default URI")
      end
    end

    def plan_retention
      desired = @desired.retention
      return unless desired

      remote = @snapshot.retention
      unless remote
        finding("drift", "retention_unavailable", "property:#{@desired.property_id}:retention",
                "Data retention settings could not be discovered")
        return
      end

      current = remote.to_h
      after = current.merge(desired)
      return if equivalent?(current, after, %w[event_data user_data reset_on_new_activity])

      update(
        "retention",
        "property:#{@desired.property_id}:retention",
        current,
        after,
        rollback: "Restore the previous event and user retention durations and reset behavior"
      )
    end

    def plan_key_events
      remote = unique_index(@snapshot.key_events, "key event", &:event_name)
      @desired.key_events.each do |event_name|
        next if remote.key?(event_name)

        create(
          "key_event",
          "event:#{event_name}",
          { "event_name" => event_name, "counting_method" => "once_per_event" },
          rollback: "Delete the newly created key event in Google Analytics if rollback is required"
        )
      end
    end

    def plan_custom_dimensions
      remote = unique_index(@snapshot.custom_dimensions, "custom dimension") do |dimension|
        [dimension.scope, dimension.parameter_name]
      end

      @desired.custom_dimensions.each do |desired|
        identity_key = [desired.fetch("scope"), desired.fetch("parameter_name")]
        identity = identity_key.join(":").to_s
        current = remote[identity_key]
        unless current
          create("custom_dimension", identity, desired, rollback: "Archive the newly created custom dimension")
          next
        end

        before = current.to_h
        mutable = %w[display_name description]
        mutable << "disallow_ads_personalization" if desired.fetch("scope") == "user"
        after = before.merge(desired.slice(*mutable))
        next if equivalent?(before, after, mutable)

        update("custom_dimension", identity, before, after, rollback: "Restore the previous custom dimension metadata")
      end
    end

    def plan_custom_metrics
      remote = unique_index(@snapshot.custom_metrics, "custom metric", &:parameter_name)

      @desired.custom_metrics.each do |desired|
        identity = desired.fetch("parameter_name")
        current = remote[identity]
        unless current
          create("custom_metric", identity, desired, rollback: "Archive the newly created custom metric")
          next
        end

        before = current.to_h
        if before.fetch("scope") != desired.fetch("scope") ||
           before.fetch("measurement_unit") != desired.fetch("measurement_unit")
          finding("drift", "immutable_metric_conflict", "metric:#{identity}",
                  "Custom metric scope or measurement unit differs and will not be recreated automatically")
          next
        end

        mutable = %w[display_name description]
        after = before.merge(desired.slice(*mutable))
        next if equivalent?(before, after, mutable)

        update("custom_metric", identity, before, after, rollback: "Restore the previous custom metric metadata")
      end
    end

    def add_manual_findings
      @desired.manual_requirements.each do |requirement|
        finding("manual", "manual_requirement", requirement, "Verify #{requirement.tr("_", " ")} in Google Analytics")
      end
    end

    def add_experimental_findings
      return unless @desired.google_signals

      finding(
        "experimental",
        "google_signals_not_managed",
        "property:#{@desired.property_id}:google_signals",
        "Google Signals is declared but remains an experimental, non-applicable capability"
      )
    end

    def create(resource_type, identity, after, rollback:)
      @changes << Plan::Change.new(
        resource_type:,
        resource_identity: identity,
        operation: "create",
        api_maturity: "beta",
        before: nil,
        after: Canonical.normalize(after),
        reversible: true,
        rollback:
      )
    end

    def update(resource_type, identity, before, after, rollback:)
      @changes << Plan::Change.new(
        resource_type:,
        resource_identity: identity,
        operation: "update",
        api_maturity: "beta",
        before: Canonical.normalize(before),
        after: Canonical.normalize(after),
        reversible: true,
        rollback:
      )
    end

    def finding(severity, code, identity, message)
      @findings << Plan::Finding.new(severity:, code:, resource_identity: identity, message:)
    end

    def unique_index(values, resource)
      values.each_with_object({}) do |value, result|
        identity = yield(value)
        if result.key?(identity)
          raise ConflictError,
                "Ambiguous remote #{resource} identity #{Array(identity).join(":")}"
        end

        result[identity] = value
      end
    end

    def equivalent?(before, after, keys)
      keys.all? { |key| before[key] == after[key] }
    end
  end
end
