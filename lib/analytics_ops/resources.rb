# frozen_string_literal: true

# Gem-owned values returned at public API boundaries.

module AnalyticsOps
  module Resources
    # Immutable base class for gem-owned values at the Google client boundary.
    class Value
      class << self
        attr_reader :field_names

        def fields(*names)
          @field_names = names.freeze
          attr_reader(*names)
        end
      end

      def initialize(**values)
        unknown = values.keys - self.class.field_names
        missing = self.class.field_names - values.keys
        raise ArgumentError, "Unknown fields: #{unknown.join(", ")}" unless unknown.empty?
        raise ArgumentError, "Missing fields: #{missing.join(", ")}" unless missing.empty?

        values.each do |name, value|
          instance_variable_set("@#{name}", Canonical.immutable(value))
        end
        freeze
      end

      def to_h
        self.class.field_names.to_h { |name| [name.to_s, public_send(name)] }
      end

      def ==(other)
        other.instance_of?(self.class) && other.to_h == to_h
      end
      alias eql? ==

      def hash
        [self.class, to_h].hash
      end
    end

    # Accessible Analytics account summary.
    class Account < Value
      fields :id, :name, :display_name, :properties
    end

    # Normalized GA4 property.
    class Property < Value
      fields :id, :name, :display_name, :parent, :property_type, :can_edit
    end

    # Normalized web or application data stream.
    class DataStream < Value
      fields :id, :name, :display_name, :type, :default_uri, :measurement_id
    end

    # Property retention settings.
    class Retention < Value
      fields :name, :event_data, :user_data, :reset_on_new_activity
    end

    # Registered key event.
    class KeyEvent < Value
      fields :name, :event_name, :counting_method
    end

    # Registered custom dimension.
    class CustomDimension < Value
      fields :name, :parameter_name, :display_name, :description, :scope, :disallow_ads_personalization
    end

    # Registered custom metric.
    class CustomMetric < Value
      fields :name, :parameter_name, :display_name, :description, :scope, :measurement_unit,
             :restricted_metric_types
    end
  end
end
