# frozen_string_literal: true

# Official Admin API boundary.

require_relative "admin_normalization"

module AnalyticsOps
  module Clients
    # Narrow adapter around Google's generated Admin client.
    class Admin
      include AdminNormalization

      PACKAGE_REQUIREMENT = Gem::Requirement.new("~> 0.8.0")
      RETENTION_TO_GOOGLE = {
        "2_months" => :TWO_MONTHS,
        "14_months" => :FOURTEEN_MONTHS,
        "26_months" => :TWENTY_SIX_MONTHS,
        "38_months" => :THIRTY_EIGHT_MONTHS,
        "50_months" => :FIFTY_MONTHS
      }.freeze
      GOOGLE_TO_RETENTION = RETENTION_TO_GOOGLE.invert.freeze
      STREAM_TYPES = {
        "WEB_DATA_STREAM" => "web",
        "ANDROID_APP_DATA_STREAM" => "android",
        "IOS_APP_DATA_STREAM" => "ios"
      }.freeze
      CAPABILITIES = {
        "account_property_discovery" => :list_account_summaries,
        "data_stream_discovery" => :list_data_streams,
        "data_retention" => :update_data_retention_settings,
        "key_events" => :create_key_event,
        "custom_dimensions" => :create_custom_dimension,
        "custom_metrics" => :create_custom_metric
      }.freeze

      def initialize(client: nil, service_account: nil, access: :read, transport: :grpc, timeout: nil, logger: nil)
        unless service_account.nil? || service_account.is_a?(ServiceAccount)
          raise ConfigurationError, "service_account must be an AnalyticsOps::ServiceAccount"
        end
        raise ConfigurationError, "access must be :read or :edit" unless %i[read edit].include?(access)

        @client = client
        @service_account = service_account
        @access = access
        @transport = validate_transport(transport)
        @timeout = validate_timeout(timeout)
        @logger = logger
      end

      def discover(include_streams: true)
        raise ConfigurationError, "include_streams must be true or false" unless [true, false].include?(include_streams)

        list(:list_account_summaries, page_size: 200).map do |summary|
          account_name = remote_string(field(summary, :account), "account name")
          properties = array_field(summary, :property_summaries).map do |property|
            normalized = normalize_property(property, can_edit: field(property, :can_edit))
            next normalized.to_h unless include_streams

            normalized.to_h.merge("streams" => list_streams(normalized.id).map(&:to_h))
          end
          properties.sort_by! { |property| property.fetch("id") }

          Resources::Account.new(
            id: resource_id(account_name),
            name: account_name,
            display_name: remote_string(field(summary, :display_name), "account display name"),
            properties:
          )
        end.sort_by(&:id).freeze
      end

      def property_access(property_id)
        expected_name = property_name(property_id)
        id = property_id
        list(:list_account_summaries, page_size: 200).each do |summary|
          array_field(summary, :property_summaries).each do |property|
            next unless resource_id(field(property, :property)) == id

            normalized = normalize_property(property, can_edit: field(property, :can_edit))
            return normalized if normalized.name == expected_name

            raise RemoteError, "Google Admin API returned a property name that does not match the request"
          end
        end

        raise AuthorizationError, "Configured property is not present in accessible account summaries"
      end

      def snapshot(property_id)
        property_name = property_name(property_id)
        property = normalize_property(get(:get_property, name: property_name), can_edit: nil)
        unless property.name == property_name
          raise RemoteError, "Google Admin API returned a property name that does not match the request"
        end

        streams = list_streams(property_id)
        retention = normalize_retention(get(:get_data_retention_settings,
                                            name: "#{property_name}/dataRetentionSettings"))
        key_events = list(:list_key_events, parent: property_name, page_size: 200).map do |value|
          normalize_key_event(value)
        end
        custom_dimensions = list(:list_custom_dimensions, parent: property_name, page_size: 200)
                            .map { |value| normalize_custom_dimension(value) }
        custom_metrics = list(:list_custom_metrics, parent: property_name, page_size: 200)
                         .map { |value| normalize_custom_metric(value) }
        validate_snapshot_names!(
          property: property_name,
          streams:,
          retention:,
          key_events:,
          dimensions: custom_dimensions,
          metrics: custom_metrics
        )

        Snapshot.new(
          property:,
          streams:,
          retention:,
          key_events:,
          custom_dimensions:,
          custom_metrics:
        )
      end

      def capabilities
        generated_client = translate_errors { client }
        CAPABILITIES.to_h { |name, method| [name, generated_client.respond_to?(method)] }.freeze
      end

      def compatibility
        specification = Gem::Specification.find_by_name("google-analytics-admin")
        Canonical.immutable(
          "package" => specification.name,
          "version" => specification.version.to_s,
          "requirement" => PACKAGE_REQUIREMENT.to_s,
          "supported" => PACKAGE_REQUIREMENT.satisfied_by?(specification.version),
          "transport" => @transport.to_s
        )
      rescue Gem::LoadError => error
        raise UnsupportedCapabilityError, Redaction.message(error.message)
      end

      def apply_change(change, property_id:)
        raise InvalidPlanError, "change must be an AnalyticsOps::Plan::Change" unless change.is_a?(Plan::Change)

        property_name(property_id)
        method_name, request = mutation(change, property_id)
        get(method_name, request)
        change
      end

      private

      def client
        @client ||= begin
          unless @service_account
            raise AuthenticationError, "Analytics Ops requires configured service-account credentials"
          end

          require "google/analytics/admin"
          Google::Analytics::Admin.analytics_admin_service(transport: @transport) do |config|
            config.credentials = @service_account.__send__(:credentials, access: @access)
            config.timeout = @timeout if @timeout
          end
        end
      end

      def list_streams(property_id)
        list(:list_data_streams, parent: property_name(property_id), page_size: 200).map do |stream|
          normalize_stream(stream)
        end
      end

      def list(method_name, request)
        response = invoke(method_name, request)
        translate_errors { response.respond_to?(:to_a) ? response.to_a : Array(response) }
      end

      def get(method_name, request)
        invoke(method_name, request)
      end

      def invoke(method_name, request)
        SafeLogging.write(
          @logger,
          :info,
          "google_admin_request",
          "method" => method_name.to_s,
          "resource" => request_resource(request)
        )
        generated_client = translate_errors { client }
        unless generated_client.respond_to?(method_name)
          raise UnsupportedCapabilityError, "Installed Google Admin client does not support #{method_name}"
        end

        translate_errors { generated_client.public_send(method_name, request) }
      end

      def request_resource(request)
        request[:name] || request[:parent] || request.dig(:data_stream, :name) ||
          request.dig(:data_retention_settings, :name)
      end

      def translate_errors(&)
        ErrorTranslation.call(&)
      end

      def mutation(change, property_id)
        case [change.resource_type, change.operation]
        when %w[data_stream update]
          update_data_stream_request(change.after, property_id)
        when %w[retention update]
          update_retention_request(change.after, property_id)
        when %w[key_event create]
          create_key_event_request(change.after, property_id)
        when %w[custom_dimension create]
          create_custom_dimension_request(change.after, property_id)
        when %w[custom_dimension update]
          update_custom_dimension_request(change.after, property_id)
        when %w[custom_metric create]
          create_custom_metric_request(change.after, property_id)
        when %w[custom_metric update]
          update_custom_metric_request(change.after, property_id)
        else
          raise UnsupportedCapabilityError,
                "Unsupported #{change.operation} operation for #{change.resource_type}"
        end
      end

      def update_data_stream_request(after, property_id)
        validate_resource_name!(after.fetch("name"), property_id, "dataStreams")
        [
          :update_data_stream,
          {
            data_stream: {
              name: after.fetch("name"),
              web_stream_data: { default_uri: after.fetch("default_uri") }
            },
            update_mask: { paths: ["web_stream_data.default_uri"] }
          }
        ]
      end

      def update_retention_request(after, property_id)
        expected_name = "#{property_name(property_id)}/dataRetentionSettings"
        unless after.fetch("name") == expected_name
          raise InvalidPlanError,
                "Retention resource belongs to a different property"
        end

        [
          :update_data_retention_settings,
          {
            data_retention_settings: {
              name: expected_name,
              event_data_retention: google_retention(after.fetch("event_data")),
              user_data_retention: google_retention(after.fetch("user_data")),
              reset_user_data_on_new_activity: after.fetch("reset_on_new_activity")
            },
            update_mask: { paths: %w[event_data_retention user_data_retention reset_user_data_on_new_activity] }
          }
        ]
      end

      def create_key_event_request(after, property_id)
        [
          :create_key_event,
          {
            parent: property_name(property_id),
            key_event: {
              event_name: after.fetch("event_name"),
              counting_method: key_event_counting_method(after.fetch("counting_method"))
            }
          }
        ]
      end

      def create_custom_dimension_request(after, property_id)
        [:create_custom_dimension, { parent: property_name(property_id), custom_dimension: dimension_payload(after) }]
      end

      def update_custom_dimension_request(after, property_id)
        validate_resource_name!(after.fetch("name"), property_id, "customDimensions")
        paths = %w[display_name description]
        paths << "disallow_ads_personalization" if after.fetch("scope") == "user"
        [
          :update_custom_dimension,
          {
            custom_dimension: dimension_payload(after).merge(name: after.fetch("name")),
            update_mask: { paths: }
          }
        ]
      end

      def dimension_payload(after)
        {
          parameter_name: after.fetch("parameter_name"),
          display_name: after.fetch("display_name"),
          description: after.fetch("description"),
          scope: after.fetch("scope").upcase.to_sym,
          disallow_ads_personalization: after.fetch("disallow_ads_personalization", false)
        }
      end

      def create_custom_metric_request(after, property_id)
        [:create_custom_metric, { parent: property_name(property_id), custom_metric: metric_payload(after) }]
      end

      def update_custom_metric_request(after, property_id)
        validate_resource_name!(after.fetch("name"), property_id, "customMetrics")
        [
          :update_custom_metric,
          {
            custom_metric: metric_payload(after).merge(name: after.fetch("name")),
            update_mask: { paths: %w[display_name description] }
          }
        ]
      end

      def metric_payload(after)
        {
          parameter_name: after.fetch("parameter_name"),
          display_name: after.fetch("display_name"),
          description: after.fetch("description"),
          scope: :EVENT,
          measurement_unit: after.fetch("measurement_unit").upcase.to_sym,
          restricted_metric_type: after.fetch("restricted_metric_types").map { |type| type.upcase.to_sym }
        }
      end

      def validate_resource_name!(name, property_id, collection)
        pattern = %r{\A#{Regexp.escape(property_name(property_id))}/#{collection}/[A-Za-z0-9_-]+\z}
        return if name.is_a?(String) && pattern.match?(name)

        raise InvalidPlanError, "Plan resource belongs to a different property"
      end

      def property_name(property_id)
        unless property_id.is_a?(String) && property_id.match?(/\A\d{1,50}\z/)
          raise ConfigurationError, "Invalid property ID; expected a numeric string"
        end

        "properties/#{property_id}"
      end

      def google_retention(value)
        RETENTION_TO_GOOGLE.fetch(value) do
          raise InvalidPlanError, "Unsupported retention duration #{value.inspect}"
        end
      end

      def key_event_counting_method(value)
        {
          "once_per_event" => :ONCE_PER_EVENT,
          "once_per_session" => :ONCE_PER_SESSION
        }.fetch(value) do
          raise InvalidPlanError, "Unsupported key event counting method #{value.inspect}"
        end
      end

      def normalize_retention_value(value)
        GOOGLE_TO_RETENTION.fetch(enum_symbol(value)) do
          normalize_enum(value, prefix: "RETENTION_DURATION_")
        end
      end

      def field(value, name)
        return nil if value.nil?
        return value.public_send(name) if value.respond_to?(name)
        return value[name] if value.respond_to?(:key?) && value.key?(name)
        return value[name.to_s] if value.respond_to?(:key?) && value.key?(name.to_s)

        nil
      end

      def array_field(value, name)
        Array(field(value, name))
      end

      def remote_boolean(value)
        return false if value.nil?
        return value if [true, false].include?(value)

        raise RemoteError, "Google Admin API returned an invalid boolean"
      end

      def optional_boolean(value)
        return nil if value.nil?

        remote_boolean(value)
      end

      def resource_id(name)
        id = remote_string(name, "resource name").split("/").last
        return id unless id.nil? || id.empty?

        raise RemoteError, "Google Admin API returned an invalid resource name"
      end

      def optional_string(value, label)
        return nil if value.nil?

        string = remote_string(value, label)
        string.empty? ? nil : string
      end

      def remote_string(value, label)
        raise RemoteError, "Google Admin API returned an invalid #{label}" unless value.is_a?(String)

        string = value.encode(Encoding::UTF_8)
        raise EncodingError unless string.valid_encoding?

        string
      rescue EncodingError
        raise RemoteError, "Google Admin API returned an invalid #{label}"
      end

      def normalize_enum(value, prefix: nil)
        name = enum_name(value)
        name = name.delete_prefix(prefix) if prefix
        name.downcase
      end

      def enum_name(value)
        value.respond_to?(:name) ? value.name.to_s : value.to_s
      end

      def enum_symbol(value)
        enum_name(value).upcase.to_sym
      end

      def validate_transport(value)
        transport = value.to_sym if value.respond_to?(:to_sym)
        return transport if %i[grpc rest].include?(transport)

        raise ConfigurationError, "transport must be grpc or rest"
      end

      def validate_timeout(value)
        return nil if value.nil?
        return value if [Integer, Float].any? { |type| value.is_a?(type) } && value.finite? && value.positive?

        raise ConfigurationError, "timeout must be a finite positive number"
      end
    end
  end
end
