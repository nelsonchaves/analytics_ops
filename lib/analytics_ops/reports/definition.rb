# frozen_string_literal: true

require "date"

module AnalyticsOps
  module Reports
    # Immutable, gem-owned description of one Data API query.
    class Definition
      KINDS = %w[standard realtime].freeze
      API_NAME = /\A[a-z][a-zA-Z0-9_]*(?::[a-zA-Z][a-zA-Z0-9_]*)?\z/
      REPORT_NAME = /\A[a-z][a-z0-9_]{0,63}\z/
      RANGE_NAME = /\A[a-z][a-z0-9_]{0,39}\z/
      ABSOLUTE_DATE = /\A\d{4}-\d{2}-\d{2}\z/
      RELATIVE_DATE = /\A(\d{1,4})daysAgo\z/
      MATCH_TYPES = %w[exact begins_with ends_with contains full_regexp partial_regexp].freeze
      NUMERIC_OPERATIONS = %w[equal less_than less_than_or_equal greater_than greater_than_or_equal].freeze
      MAX_LIMIT = 100_000
      INT64_RANGE = (-(2**63))..((2**63) - 1)

      attr_reader :name, :kind, :dimensions, :metrics, :date_ranges,
                  :dimension_filter, :metric_filter, :order_bys, :offset, :limit

      def initialize(name:, kind:, dimensions:, metrics:, date_ranges: [], dimension_filter: nil,
                     metric_filter: nil, order_bys: [], offset: 0, limit: 100)
        @name = validate_name(name)
        @kind = validate_kind(kind)
        @dimensions = api_names(dimensions, "dimensions", minimum: 0, maximum: realtime_kind?(kind) ? 4 : 9)
        @metrics = api_names(metrics, "metrics", minimum: 1, maximum: 10)
        @date_ranges = ranges(date_ranges)
        @dimension_filter = string_filter(dimension_filter)
        @metric_filter = numeric_filter(metric_filter)
        @order_bys = orders(order_bys)
        @offset = integer(offset, "offset", minimum: 0, maximum: 1_000_000_000)
        @limit = integer(limit, "limit", minimum: 1, maximum: MAX_LIMIT)
        validate_shape!
        freeze
      end

      def realtime?
        kind == "realtime"
      end

      def to_h
        {
          "name" => name,
          "kind" => kind,
          "dimensions" => dimensions,
          "metrics" => metrics,
          "date_ranges" => date_ranges,
          "dimension_filter" => dimension_filter,
          "metric_filter" => metric_filter,
          "order_bys" => order_bys,
          "offset" => offset,
          "limit" => limit
        }
      end

      private

      def validate_name(value)
        return value.dup.freeze if value.is_a?(String) && REPORT_NAME.match?(value)

        raise InvalidRequestError, "Report name is invalid"
      end

      def validate_kind(value)
        return value.dup.freeze if value.is_a?(String) && KINDS.include?(value)

        raise InvalidRequestError, "Report kind must be standard or realtime"
      end

      def realtime_kind?(value)
        value == "realtime"
      end

      def api_names(values, label, minimum:, maximum:)
        unless values.is_a?(Array) && values.length.between?(minimum, maximum) &&
               values.all? { |value| valid_api_name?(value) }
          raise InvalidRequestError,
                "Report #{label} must contain #{minimum} to #{maximum} valid Data API names"
        end
        unless values.uniq.length == values.length
          raise InvalidRequestError,
                "Report #{label} must not contain duplicates"
        end

        Canonical.immutable(values)
      end

      def valid_api_name?(value)
        value.is_a?(String) && value.length <= 128 && API_NAME.match?(value)
      end

      def ranges(values)
        raise InvalidRequestError, "date_ranges must be an array" unless values.is_a?(Array)
        raise InvalidRequestError, "A report can contain at most four date ranges" if values.length > 4

        normalized = values.map { |range| normalize_range(range) }
        names = normalized.filter_map { |range| range["name"] }
        invalid!("Date range names must be unique") unless names.uniq.length == names.length

        Canonical.immutable(normalized)
      end

      def normalize_range(range)
        hash = string_hash(range, "date range", %w[start_date end_date name])
        start_date = date(hash.fetch("start_date") { invalid!("Missing start_date") })
        end_date = date(hash.fetch("end_date") { invalid!("Missing end_date") })
        validate_date_order!(start_date, end_date)
        result = { "start_date" => start_date, "end_date" => end_date }
        return result unless hash.key?("name")

        range_name = hash.fetch("name")
        valid = range_name.is_a?(String) && RANGE_NAME.match?(range_name) &&
                !range_name.start_with?("date_range_")
        invalid!("Date range name is invalid or reserved") unless valid
        result.merge("name" => range_name)
      end

      def date(value)
        invalid!("Invalid report date") unless value.is_a?(String)
        return value if %w[today yesterday].include?(value)

        relative = RELATIVE_DATE.match(value)
        return value if relative && relative[1].to_i <= 3650

        invalid!("Invalid report date") unless ABSOLUTE_DATE.match?(value)

        Date.iso8601(value)
        value
      rescue Date::Error
        invalid!("Invalid report date")
      end

      def validate_date_order!(start_date, end_date)
        if ABSOLUTE_DATE.match?(start_date) && ABSOLUTE_DATE.match?(end_date)
          return if Date.iso8601(start_date) <= Date.iso8601(end_date)
        else
          start_offset = relative_date_offset(start_date)
          end_offset = relative_date_offset(end_date)
          return unless start_offset && end_offset
          return if start_offset >= end_offset
        end

        invalid!("Report start_date must not be after end_date")
      end

      def relative_date_offset(value)
        return 0 if value == "today"
        return 1 if value == "yesterday"

        RELATIVE_DATE.match(value)&.[](1)&.to_i
      end

      def string_filter(value)
        return nil if value.nil?

        hash = string_hash(value, "dimension filter", %w[field match_type value case_sensitive])
        field = hash.fetch("field") { invalid!("Missing filter field") }
        match_type = hash.fetch("match_type") { invalid!("Missing filter match_type") }
        filter_value = hash.fetch("value") { invalid!("Missing filter value") }
        unless valid_api_name?(field) && dimensions.include?(field) && MATCH_TYPES.include?(match_type) &&
               printable_string?(filter_value, maximum: 1_024)
          invalid!("Dimension filter is invalid or references an unselected dimension")
        end

        case_sensitive = hash.key?("case_sensitive") ? boolean(hash.fetch("case_sensitive"), "case_sensitive") : false
        Canonical.immutable(
          "field" => field,
          "match_type" => match_type,
          "value" => filter_value,
          "case_sensitive" => case_sensitive
        )
      end

      def numeric_filter(value)
        return nil if value.nil?

        hash = string_hash(value, "metric filter", %w[field operation value])
        field = hash.fetch("field") { invalid!("Missing metric filter field") }
        operation = hash.fetch("operation") { invalid!("Missing metric filter operation") }
        number = hash.fetch("value") { invalid!("Missing metric filter value") }
        valid = valid_api_name?(field) && metrics.include?(field) && NUMERIC_OPERATIONS.include?(operation)
        invalid!("Metric filter is invalid or references an unselected metric") unless valid
        unless valid_numeric_filter_value?(number)
          invalid!("Metric filter value must be a finite int64 Integer or Float")
        end

        Canonical.immutable("field" => field, "operation" => operation, "value" => number)
      end

      def valid_numeric_filter_value?(number)
        (number.is_a?(Integer) && INT64_RANGE.cover?(number)) || (number.is_a?(Float) && number.finite?)
      end

      def orders(values)
        raise InvalidRequestError, "order_bys must be an array" unless values.is_a?(Array)
        raise InvalidRequestError, "A report can contain at most ten order clauses" if values.length > 10

        normalized = values.map { |order| normalize_order(order) }
        identities = normalized.map { |order| order_identity(order) }
        invalid!("Report order clauses must reference unique fields") unless identities.uniq.length == identities.length

        Canonical.immutable(normalized)
      end

      def normalize_order(order)
        hash = string_hash(order, "report order", %w[metric dimension desc])
        selectors = %w[metric dimension].select { |key| hash.key?(key) }
        invalid!("Report order requires exactly one metric or dimension") unless selectors.length == 1

        selector = selectors.first
        api_name = hash.fetch(selector)
        selected = selector == "metric" ? metrics : dimensions
        valid = valid_api_name?(api_name) && selected.include?(api_name)
        invalid!("Report order references an unselected #{selector}") unless valid

        { selector => api_name, "desc" => hash.key?("desc") ? boolean(hash.fetch("desc"), "desc") : false }
      end

      def order_identity(order)
        selector = order.key?("metric") ? "metric" : "dimension"
        [selector, order.fetch(selector)]
      end

      def validate_shape!
        invalid!("Realtime reports cannot include date ranges") if realtime? && !date_ranges.empty?
        invalid!("Realtime reports do not support offset") if realtime? && offset.positive?
        invalid!("Standard reports require a date range") if !realtime? && date_ranges.empty?
      end

      def string_hash(value, label, allowed)
        raise InvalidRequestError, "#{label} must be an object" unless value.is_a?(Hash)
        raise InvalidRequestError, "#{label} keys must be strings" unless value.keys.all?(String)

        unknown = value.keys - allowed
        raise InvalidRequestError, "Unknown #{label} field #{unknown.first}" unless unknown.empty?

        value
      end

      def printable_string?(value, maximum:)
        value.is_a?(String) && !value.empty? && value.length <= maximum && !value.match?(/[\u0000-\u001f\u007f]/)
      end

      def boolean(value, label)
        return value if [true, false].include?(value)

        raise InvalidRequestError, "#{label} must be true or false"
      end

      def integer(value, label, minimum:, maximum:)
        return value if value.is_a?(Integer) && value.between?(minimum, maximum)

        raise InvalidRequestError, "Report #{label} must be between #{minimum} and #{maximum}"
      end

      def invalid!(message)
        raise InvalidRequestError, message
      end
    end
  end
end
