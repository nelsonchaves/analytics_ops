# frozen_string_literal: true

module AnalyticsOps
  module Reports
    # Immutable normalized Data API response.
    class Result
      attr_reader :name, :kind, :dimension_headers, :metric_headers, :rows, :row_count, :metadata

      def initialize(name:, kind:, dimension_headers:, metric_headers:, rows:, row_count:, metadata:)
        @name = string(name, "name")
        @kind = kind_value(kind)
        @dimension_headers = normalize_headers(dimension_headers, "dimension_headers")
        @metric_headers = normalize_headers(metric_headers, "metric_headers")
        validate_header_uniqueness!
        @rows = normalized_rows(rows)
        @row_count = count(row_count)
        @metadata = hash(metadata, "metadata")
        freeze
      end

      def headers
        dimension_headers + metric_headers
      end

      def to_h
        {
          "name" => name,
          "kind" => kind,
          "dimension_headers" => dimension_headers,
          "metric_headers" => metric_headers,
          "rows" => rows,
          "row_count" => row_count,
          "metadata" => metadata
        }
      end

      private

      def string(value, label)
        return value.dup.freeze if value.is_a?(String) && !value.empty?

        raise RemoteError, "Report result #{label} is invalid"
      end

      def kind_value(value)
        return value.dup.freeze if Definition::KINDS.include?(value)

        raise RemoteError, "Report result kind is invalid"
      end

      def normalize_headers(values, label)
        unless values.is_a?(Array) && values.all? { |value| value.is_a?(String) && !value.empty? }
          raise RemoteError, "Report result #{label} is invalid"
        end

        Canonical.immutable(values)
      end

      def validate_header_uniqueness!
        raise RemoteError, "Report result headers are not unique" unless headers.uniq.length == headers.length
      end

      def normalized_rows(values)
        raise RemoteError, "Report result rows must be an array" unless values.is_a?(Array)

        normalized = values.map do |row|
          value = hash(row, "row")
          raise RemoteError, "Report result row fields do not match headers" unless value.keys.sort == headers.sort

          value
        end
        Canonical.immutable(normalized)
      end

      def count(value)
        return value if value.is_a?(Integer) && value >= rows.length

        raise RemoteError, "Report result row_count is invalid"
      end

      def hash(value, label)
        unless value.is_a?(Hash) && value.keys.all?(String)
          raise RemoteError, "Report result #{label} must be an object with string keys"
        end

        Canonical.immutable(value)
      end
    end
  end
end
