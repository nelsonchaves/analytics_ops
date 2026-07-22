# frozen_string_literal: true

# Normalized remote state.

module AnalyticsOps
  # Normalized remote state. No generated Google objects escape into this value.
  class Snapshot
    attr_reader :property, :streams, :retention, :key_events, :custom_dimensions, :custom_metrics

    def initialize(property:, streams:, retention:, key_events:, custom_dimensions:, custom_metrics:)
      @property = property
      @streams = sort(streams, &:id)
      @retention = retention
      @key_events = sort(key_events, &:event_name)
      @custom_dimensions = sort(custom_dimensions) { |dimension| [dimension.scope, dimension.parameter_name] }
      @custom_metrics = sort(custom_metrics, &:parameter_name)
      freeze
    end

    def property_id
      property.id
    end

    def to_h
      {
        "property" => property.to_h,
        "streams" => streams.map(&:to_h),
        "retention" => retention&.to_h,
        "key_events" => key_events.map(&:to_h),
        "custom_dimensions" => custom_dimensions.map(&:to_h),
        "custom_metrics" => custom_metrics.map(&:to_h)
      }
    end

    def fingerprint
      Canonical.fingerprint(to_h)
    end

    private

    def sort(values, &)
      Canonical.deep_freeze(values.sort_by(&))
    end
  end
end
