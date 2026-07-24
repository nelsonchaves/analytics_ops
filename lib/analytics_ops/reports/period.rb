# frozen_string_literal: true

require "date"

module AnalyticsOps
  module Reports
    # Builds bounded GA4 date ranges for simple CLI and AI report requests.
    module Period
      DEFAULT_DAYS = 28
      MAX_DAYS = 1_825
      ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/

      module_function

      def resolve(last_days: nil, start_date: nil, end_date: nil, compare: false)
        validate_compare!(compare)
        validate_combination!(last_days:, start_date:, end_date:)
        return nil if last_days.nil? && start_date.nil? && !compare

        if start_date
          absolute_ranges(start_date:, end_date:, compare:)
        else
          relative_ranges(last_days || DEFAULT_DAYS, compare)
        end
      end

      def relative_ranges(days, compare)
        validate_days!(days)
        current = {
          "start_date" => "#{days}daysAgo",
          "end_date" => "yesterday"
        }
        return Canonical.immutable([current]) unless compare

        current["name"] = "current"
        previous = {
          "start_date" => "#{days * 2}daysAgo",
          "end_date" => "#{days + 1}daysAgo",
          "name" => "previous"
        }
        Canonical.immutable([current, previous])
      end
      private_class_method :relative_ranges

      def absolute_ranges(start_date:, end_date:, compare:)
        start_value = parse_date!(start_date, "--from")
        end_value = parse_date!(end_date, "--to")
        raise InvalidRequestError, "--from must not be after --to" if start_value > end_value

        current = {
          "start_date" => start_value.iso8601,
          "end_date" => end_value.iso8601
        }
        days = (end_value - start_value).to_i + 1
        raise InvalidRequestError, "Date range cannot exceed #{MAX_DAYS} days" if days > MAX_DAYS
        return Canonical.immutable([current]) unless compare

        previous_end = start_value - 1
        previous_start = previous_end - (days - 1)
        current["name"] = "current"
        previous = {
          "start_date" => previous_start.iso8601,
          "end_date" => previous_end.iso8601,
          "name" => "previous"
        }
        Canonical.immutable([current, previous])
      end
      private_class_method :absolute_ranges

      def validate_combination!(last_days:, start_date:, end_date:)
        if last_days && (start_date || end_date)
          raise InvalidRequestError, "Use either --last or --from with --to, not both"
        end
        return if start_date.nil? == end_date.nil?

        raise InvalidRequestError, "--from and --to must be used together"
      end
      private_class_method :validate_combination!

      def validate_days!(value)
        return if value.is_a?(Integer) && value.between?(1, MAX_DAYS)

        raise InvalidRequestError, "--last must be between 1 and #{MAX_DAYS} days"
      end
      private_class_method :validate_days!

      def validate_compare!(value)
        return if [true, false].include?(value)

        raise InvalidRequestError, "--compare must be true or false"
      end
      private_class_method :validate_compare!

      def parse_date!(value, option)
        raise InvalidRequestError, "#{option} must use YYYY-MM-DD" unless value.is_a?(String) && ISO_DATE.match?(value)

        Date.iso8601(value)
      rescue Date::Error
        raise InvalidRequestError, "#{option} must be a real calendar date"
      end
      private_class_method :parse_date!
    end
  end
end
