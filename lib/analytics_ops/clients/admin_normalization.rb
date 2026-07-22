# frozen_string_literal: true

module AnalyticsOps
  module Clients
    # Internal normalization of generated Admin API responses into gem-owned values.
    module AdminNormalization
      private

      def normalize_property(value, can_edit:)
        name = remote_string(field(value, :property) || field(value, :name), "property name")
        Resources::Property.new(
          id: resource_id(name),
          name:,
          display_name: remote_string(field(value, :display_name), "property display name"),
          parent: optional_string(field(value, :parent), "property parent"),
          property_type: normalize_enum(field(value, :property_type), prefix: "PROPERTY_TYPE_"),
          can_edit: optional_boolean(can_edit)
        )
      end

      def normalize_stream(value)
        name = remote_string(field(value, :name), "data stream name")
        type = Admin::STREAM_TYPES.fetch(enum_name(field(value, :type)), "unspecified")
        web_data = field(value, :web_stream_data)
        Resources::DataStream.new(
          id: resource_id(name),
          name:,
          display_name: remote_string(field(value, :display_name), "data stream display name"),
          type:,
          default_uri: optional_string(field(web_data, :default_uri), "data stream default URI"),
          measurement_id: optional_string(field(web_data, :measurement_id), "measurement ID")
        )
      end

      def normalize_retention(value)
        Resources::Retention.new(
          name: remote_string(field(value, :name), "retention resource name"),
          event_data: normalize_retention_value(field(value, :event_data_retention)),
          user_data: normalize_retention_value(field(value, :user_data_retention)),
          reset_on_new_activity: remote_boolean(field(value, :reset_user_data_on_new_activity))
        )
      end

      def normalize_key_event(value)
        Resources::KeyEvent.new(
          name: remote_string(field(value, :name), "key event resource name"),
          event_name: remote_string(field(value, :event_name), "key event name"),
          counting_method: normalize_enum(field(value, :counting_method))
        )
      end

      def normalize_custom_dimension(value)
        Resources::CustomDimension.new(
          name: remote_string(field(value, :name), "custom dimension resource name"),
          parameter_name: remote_string(field(value, :parameter_name), "custom dimension parameter name"),
          display_name: remote_string(field(value, :display_name), "custom dimension display name"),
          description: remote_string(field(value, :description), "custom dimension description"),
          scope: normalize_enum(field(value, :scope), prefix: "DIMENSION_SCOPE_"),
          disallow_ads_personalization: remote_boolean(field(value, :disallow_ads_personalization))
        )
      end

      def normalize_custom_metric(value)
        Resources::CustomMetric.new(
          name: remote_string(field(value, :name), "custom metric resource name"),
          parameter_name: remote_string(field(value, :parameter_name), "custom metric parameter name"),
          display_name: remote_string(field(value, :display_name), "custom metric display name"),
          description: remote_string(field(value, :description), "custom metric description"),
          scope: normalize_enum(field(value, :scope), prefix: "METRIC_SCOPE_"),
          measurement_unit: normalize_enum(field(value, :measurement_unit), prefix: "MEASUREMENT_UNIT_"),
          restricted_metric_types: array_field(value, :restricted_metric_type).map do |type|
            normalize_enum(type, prefix: "RESTRICTED_METRIC_TYPE_")
          end.sort
        )
      end

      def validate_snapshot_names!(property:, streams:, retention:, key_events:, dimensions:, metrics:)
        valid = retention.name == "#{property}/dataRetentionSettings" &&
                resource_collection?(streams, property, "dataStreams") &&
                resource_collection?(key_events, property, "keyEvents") &&
                resource_collection?(dimensions, property, "customDimensions") &&
                resource_collection?(metrics, property, "customMetrics")
        return if valid

        raise RemoteError, "Google Admin API returned a resource belonging to a different property"
      end

      def resource_collection?(values, property, collection)
        pattern = %r{\A#{Regexp.escape(property)}/#{collection}/[A-Za-z0-9_-]+\z}
        values.all? { |value| pattern.match?(value.name) }
      end
    end
    private_constant :AdminNormalization
  end
end
