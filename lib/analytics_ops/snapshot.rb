# frozen_string_literal: true

# Normalized remote state.

module AnalyticsOps
  # Normalized remote state. No generated Google objects escape into this value.
  class Snapshot
    attr_reader :property, :streams, :retention, :key_events, :custom_dimensions, :custom_metrics

    def initialize(property:, streams:, retention:, key_events:, custom_dimensions:, custom_metrics:)
      unless property.is_a?(Resources::Property)
        raise ArgumentError, "property must be an AnalyticsOps::Resources::Property"
      end
      unless retention.nil? || retention.is_a?(Resources::Retention)
        raise ArgumentError, "retention must be an AnalyticsOps::Resources::Retention or nil"
      end

      @property = property
      @streams = sorted_resources(streams, Resources::DataStream, "streams", &:id)
      @retention = retention
      @key_events = sorted_resources(key_events, Resources::KeyEvent, "key_events", &:event_name)
      @custom_dimensions = sorted_resources(
        custom_dimensions, Resources::CustomDimension, "custom_dimensions"
      ) do |item|
        [item.scope, item.parameter_name]
      end
      @custom_metrics = sorted_resources(custom_metrics, Resources::CustomMetric, "custom_metrics", &:parameter_name)
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

    def sorted_resources(values, type, label, &)
      unless values.is_a?(Array) && values.all?(type)
        raise ArgumentError, "#{label} must contain only #{type.name} values"
      end

      Canonical.deep_freeze(values.sort_by(&))
    end
  end
end
