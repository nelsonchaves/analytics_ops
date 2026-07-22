# frozen_string_literal: true

# Validated configuration state.

module AnalyticsOps
  # Validated, immutable desired state for one named profile.
  class DesiredState
    attr_reader :profile, :property_id, :streams, :retention, :key_events,
                :custom_dimensions, :custom_metrics, :manual_requirements,
                :google_signals

    def initialize(profile:, property_id:, streams:, retention:, key_events:, custom_dimensions:, custom_metrics:,
                   manual_requirements:, google_signals:)
      @profile = profile.freeze
      @property_id = property_id.freeze
      @streams = Canonical.immutable(streams)
      @retention = Canonical.immutable(retention)
      @key_events = Canonical.immutable(key_events)
      @custom_dimensions = Canonical.immutable(custom_dimensions)
      @custom_metrics = Canonical.immutable(custom_metrics)
      @manual_requirements = Canonical.immutable(manual_requirements)
      @google_signals = Canonical.immutable(google_signals)
      freeze
    end

    def to_h
      {
        "profile" => profile,
        "property_id" => property_id,
        "streams" => streams,
        "retention" => retention,
        "key_events" => key_events,
        "custom_dimensions" => custom_dimensions,
        "custom_metrics" => custom_metrics,
        "manual_requirements" => manual_requirements,
        "google_signals" => google_signals
      }
    end
  end
end
