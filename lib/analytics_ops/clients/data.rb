# frozen_string_literal: true

module AnalyticsOps
  module Clients
    # Narrow adapter around Google's generated Data API client.
    class Data
      PACKAGE_REQUIREMENT = Gem::Requirement.new("~> 0.9.0")
      MATCH_TYPES = {
        "exact" => :EXACT,
        "begins_with" => :BEGINS_WITH,
        "ends_with" => :ENDS_WITH,
        "contains" => :CONTAINS,
        "full_regexp" => :FULL_REGEXP,
        "partial_regexp" => :PARTIAL_REGEXP
      }.freeze
      NUMERIC_OPERATIONS = {
        "equal" => :EQUAL,
        "less_than" => :LESS_THAN,
        "less_than_or_equal" => :LESS_THAN_OR_EQUAL,
        "greater_than" => :GREATER_THAN,
        "greater_than_or_equal" => :GREATER_THAN_OR_EQUAL
      }.freeze

      QUOTA_FIELDS = %i[
        tokens_per_day
        tokens_per_hour
        tokens_per_project_per_hour
        concurrent_requests
        server_errors_per_project_per_hour
        potentially_thresholded_requests_per_hour
      ].freeze

      def initialize(client: nil, credentials: nil, transport: :grpc, timeout: nil, logger: nil)
        transport = transport.to_sym
        raise ConfigurationError, "transport must be grpc or rest" unless %i[grpc rest].include?(transport)

        @client = client
        @credentials = credentials
        @transport = transport
        @timeout = timeout
        @logger = logger
      end

      def run(property_id, definition)
        unless definition.is_a?(Reports::Definition)
          raise InvalidRequestError, "report must be an AnalyticsOps::Reports::Definition"
        end

        response = if definition.realtime?
                     invoke(:run_realtime_report, realtime_request(property_id, definition))
                   else
                     invoke(:run_report, standard_request(property_id, definition))
                   end

        normalize_result(definition, response)
      end

      def batch(property_id, definitions)
        unless definitions.is_a?(Array) && definitions.length.between?(1, Reports::OverviewResult::MAX_REPORTS) &&
               definitions.all? { |definition| definition.is_a?(Reports::Definition) && !definition.realtime? }
          raise InvalidRequestError, "batch must contain 1 to 5 standard report definitions"
        end

        property = property_name(property_id)
        requests = definitions.map do |definition|
          standard_request(property_id, definition).reject { |key| key == :property }
        end
        response = invoke(:batch_run_reports, property:, requests:)
        reports = array_field(response, :reports)
        unless reports.length == definitions.length
          raise RemoteError, "Google Data API returned a batch size that does not match the request"
        end

        definitions.zip(reports).map { |definition, report| normalize_result(definition, report) }.freeze
      end

      def available?
        generated_client = translate_errors { client }
        generated_client.respond_to?(:run_report) && generated_client.respond_to?(:run_realtime_report) &&
          generated_client.respond_to?(:batch_run_reports)
      end

      def compatibility
        specification = Gem::Specification.find_by_name("google-analytics-data")
        {
          "package" => specification.name,
          "version" => specification.version.to_s,
          "requirement" => PACKAGE_REQUIREMENT.to_s,
          "supported" => PACKAGE_REQUIREMENT.satisfied_by?(specification.version),
          "transport" => @transport.to_s
        }.freeze
      rescue Gem::LoadError => error
        raise UnsupportedCapabilityError, Redaction.message(error.message)
      end

      private

      def client
        @client ||= begin
          require "google/analytics/data"
          Google::Analytics::Data.analytics_data(transport: @transport) do |config|
            config.credentials = @credentials if @credentials
            config.timeout = @timeout if @timeout
          end
        end
      end

      def standard_request(property_id, definition)
        common_request(property_id, definition).merge(
          offset: definition.offset,
          date_ranges: definition.date_ranges.map do |range|
            {
              start_date: range.fetch("start_date"),
              end_date: range.fetch("end_date"),
              name: range["name"]
            }.compact
          end
        )
      end

      def realtime_request(property_id, definition)
        common_request(property_id, definition)
      end

      def common_request(property_id, definition)
        {
          property: property_name(property_id),
          dimensions: definition.dimensions.map { |name| { name: } },
          metrics: definition.metrics.map { |name| { name: } },
          dimension_filter: filter_request(definition.dimension_filter),
          metric_filter: metric_filter_request(definition.metric_filter),
          order_bys: definition.order_bys.map { |order| order_request(order) },
          limit: definition.limit,
          return_property_quota: true
        }.compact
      end

      def filter_request(filter)
        return nil unless filter

        {
          filter: {
            field_name: filter.fetch("field"),
            string_filter: {
              match_type: MATCH_TYPES.fetch(filter.fetch("match_type")),
              value: filter.fetch("value"),
              case_sensitive: filter.fetch("case_sensitive")
            }
          }
        }
      end

      def metric_filter_request(filter)
        return nil unless filter

        number = filter.fetch("value")
        numeric_value = if number.is_a?(Integer)
                          { int64_value: number }
                        else
                          { double_value: number }
                        end
        {
          filter: {
            field_name: filter.fetch("field"),
            numeric_filter: {
              operation: NUMERIC_OPERATIONS.fetch(filter.fetch("operation")),
              value: numeric_value
            }
          }
        }
      end

      def order_request(order)
        selector = order.key?("metric") ? :metric : :dimension
        name_key = selector == :metric ? :metric_name : :dimension_name
        {
          selector => { name_key => order.fetch(selector.to_s) },
          desc: order.fetch("desc")
        }
      end

      def invoke(method_name, request)
        SafeLogging.write(
          @logger,
          :info,
          "google_data_request",
          "method" => method_name.to_s,
          "property" => request.fetch(:property)
        )
        generated_client = translate_errors { client }
        unless generated_client.respond_to?(method_name)
          raise UnsupportedCapabilityError, "Installed Google Data client does not support #{method_name}"
        end

        translate_errors { generated_client.public_send(method_name, request) }
      end

      def translate_errors
        yield
      rescue AnalyticsOps::Error
        raise
      rescue StandardError => error
        translated = case error.class.name
                     when /Unauthenticated|Google::Auth|Signet::Authorization/
                       AuthenticationError
                     when /PermissionDenied|Forbidden/
                       AuthorizationError
                     when /ResourceExhausted|TooManyRequests/
                       QuotaError
                     when /DeadlineExceeded|Timeout|ETIMEDOUT/
                       TimeoutError
                     when /InvalidArgument|FailedPrecondition|NotFound/
                       InvalidRequestError
                     when /Google::Cloud::|GRPC::|Faraday::|HTTP/
                       RemoteError
                     end
        raise unless translated

        raise translated, Redaction.message(error.message)
      end

      def normalize_result(definition, response)
        dimension_headers = array_field(response, :dimension_headers).map { |header| field(header, :name).to_s }
        metric_headers = array_field(response, :metric_headers).map { |header| field(header, :name).to_s }
        unless dimension_headers == definition.dimensions && metric_headers == definition.metrics
          raise RemoteError, "Google Data API returned headers that do not match the requested report"
        end

        rows = array_field(response, :rows).map do |row|
          dimensions = values(row, :dimension_values)
          metrics = values(row, :metric_values)
          unless dimensions.length == dimension_headers.length && metrics.length == metric_headers.length
            raise RemoteError, "Google Data API returned a row that does not match its headers"
          end

          dimension_headers.zip(dimensions).to_h.merge(metric_headers.zip(metrics).to_h)
        end

        Reports::Result.new(
          name: definition.name,
          kind: definition.kind,
          dimension_headers:,
          metric_headers:,
          rows:,
          row_count: response_row_count(response, rows.length),
          metadata: metadata(response)
        )
      end

      def values(row, name)
        array_field(row, name).map { |value| field(value, :value).to_s }
      end

      def metadata(response)
        response_metadata = field(response, :metadata)
        result = {
          "data_loss_from_other_row" => boolean?(field(response_metadata, :data_loss_from_other_row)),
          "subject_to_thresholding" => boolean?(field(response_metadata, :subject_to_thresholding)),
          "currency_code" => optional_string(field(response_metadata, :currency_code)),
          "time_zone" => optional_string(field(response_metadata, :time_zone)),
          "empty_reason" => optional_string(field(response_metadata, :empty_reason)),
          "sampling" => sampling(response_metadata),
          "property_quota" => quota(field(response, :property_quota))
        }
        result.reject { |_key, value| value.nil? || value == [] }
      end

      def sampling(response_metadata)
        array_field(response_metadata, :sampling_metadatas).map do |sample|
          {
            "samples_read_count" => integer(field(sample, :samples_read_count), 0),
            "sampling_space_size" => integer(field(sample, :sampling_space_size), 0)
          }
        end
      end

      def quota(value)
        return nil unless value

        QUOTA_FIELDS.each_with_object({}) do |name, result|
          status = field(value, name)
          next unless status

          result[name.to_s] = {
            "consumed" => integer(field(status, :consumed), 0),
            "remaining" => integer(field(status, :remaining), 0)
          }
        end
      end

      def property_name(property_id)
        id = property_id.to_s
        raise ConfigurationError, "Invalid property ID" unless id.match?(/\A\d{1,50}\z/)

        "properties/#{id}"
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

      def optional_string(value)
        string = value.to_s
        string.empty? ? nil : string
      end

      def integer(value, default)
        value.nil? ? default : Integer(value)
      rescue ArgumentError, TypeError
        default
      end

      def response_row_count(response, default)
        value = field(response, :row_count)
        value.nil? ? default : Integer(value)
      rescue ArgumentError, TypeError
        raise RemoteError, "Google Data API returned an invalid row count"
      end

      def boolean?(value)
        value == true
      end
    end
  end
end
