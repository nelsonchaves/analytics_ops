# frozen_string_literal: true

module AnalyticsOps
  module Reports
    # Immutable normalized Data API response.
    class Result
      attr_reader :name, :kind, :dimension_headers, :metric_headers, :headers, :rows, :row_count, :metadata

      def initialize(name:, kind:, dimension_headers:, metric_headers:, rows:, row_count:, metadata:)
        @name = string(name, "name")
        @kind = kind_value(kind)
        @dimension_headers = normalize_headers(dimension_headers, "dimension_headers")
        @metric_headers = normalize_headers(metric_headers, "metric_headers")
        @headers = Canonical.immutable(@dimension_headers + @metric_headers)
        validate_header_uniqueness!
        @rows = normalized_rows(rows)
        @row_count = count(row_count)
        @metadata = normalized_metadata(metadata)
        freeze
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
        return value.dup.freeze if valid_utf8?(value) && !value.empty?

        raise RemoteError, "Report result #{label} is invalid"
      end

      def kind_value(value)
        return value.dup.freeze if Definition::KINDS.include?(value)

        raise RemoteError, "Report result kind is invalid"
      end

      def normalize_headers(values, label)
        valid = values.is_a?(Array) && values.all? do |value|
          valid_utf8?(value) && !value.empty? && value.length <= 128 && !value.match?(/[\u0000-\u001f\u007f]/)
        end
        raise RemoteError, "Report result #{label} is invalid" unless valid

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
          unless value.values.all? { |item| valid_utf8?(item) }
            raise RemoteError, "Report result row values must be valid UTF-8 strings"
          end

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

      def normalized_metadata(value)
        raise RemoteError, "Report result metadata must be an object" unless value.is_a?(Hash)

        validate_metadata_value!(value, "metadata")
        Canonical.immutable(value)
      end

      def validate_metadata_value!(value, path)
        case value
        when Hash
          raise RemoteError, "Report result #{path} keys must be strings" unless value.keys.all?(String)

          value.each { |key, child| validate_metadata_value!(child, "#{path}.#{key}") }
        when Array
          value.each.with_index { |child, index| validate_metadata_value!(child, "#{path}[#{index}]") }
        when String, Integer, TrueClass, FalseClass, NilClass
          raise RemoteError, "Report result #{path} must be valid UTF-8" if value.is_a?(String) && !valid_utf8?(value)
        when Float
          raise RemoteError, "Report result #{path} must be finite" unless value.finite?
        else
          raise RemoteError, "Report result #{path} has an unsupported value"
        end
      end

      def valid_utf8?(value)
        value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?
      end
    end
  end
end
