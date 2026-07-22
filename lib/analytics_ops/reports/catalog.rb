# frozen_string_literal: true

module AnalyticsOps
  module Reports
    # Small built-in catalog focused on acquisition and calculator outcomes.
    module Catalog
      STANDARD_DATE_RANGE = Canonical.immutable(
        [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }]
      )
      ALIASES = {
        "traffic" => "traffic_acquisition",
        "landing-pages" => "landing_pages"
      }.freeze
      CALCULATOR = "customEvent:calculator_slug"
      EVENT_FILTER = lambda do |value, match_type = "exact"|
        { "field" => "eventName", "match_type" => match_type, "value" => value }
      end

      DEFINITIONS = [
        Definition.new(
          name: "traffic_acquisition",
          kind: "standard",
          dimensions: %w[sessionDefaultChannelGroup sessionSource sessionMedium],
          metrics: %w[sessions totalUsers keyEvents],
          date_ranges: STANDARD_DATE_RANGE,
          order_bys: [{ "metric" => "sessions", "desc" => true }],
          limit: 250
        ),
        Definition.new(
          name: "landing_pages",
          kind: "standard",
          dimensions: %w[landingPagePlusQueryString],
          metrics: %w[sessions totalUsers keyEvents],
          date_ranges: STANDARD_DATE_RANGE,
          order_bys: [{ "metric" => "sessions", "desc" => true }],
          limit: 500
        ),
        Definition.new(
          name: "calculator_completions",
          kind: "standard",
          dimensions: ["eventName", CALCULATOR],
          metrics: %w[eventCount totalUsers],
          date_ranges: STANDARD_DATE_RANGE,
          dimension_filter: EVENT_FILTER.call("calculation_completed"),
          order_bys: [{ "metric" => "eventCount", "desc" => true }],
          limit: 500
        ),
        Definition.new(
          name: "shares_and_prints",
          kind: "standard",
          dimensions: ["eventName", CALCULATOR],
          metrics: %w[eventCount totalUsers],
          date_ranges: STANDARD_DATE_RANGE,
          dimension_filter: EVENT_FILTER.call("^(result_shared|result_printed)$", "full_regexp"),
          order_bys: [{ "metric" => "eventCount", "desc" => true }],
          limit: 500
        ),
        Definition.new(
          name: "related_calculator_navigation",
          kind: "standard",
          dimensions: ["eventName", CALCULATOR, "customEvent:related_calculator_slug"],
          metrics: %w[eventCount totalUsers],
          date_ranges: STANDARD_DATE_RANGE,
          dimension_filter: EVENT_FILTER.call("related_calculator_clicked"),
          order_bys: [{ "metric" => "eventCount", "desc" => true }],
          limit: 500
        ),
        Definition.new(
          name: "commercial_outbound_clicks",
          kind: "standard",
          dimensions: ["eventName", CALCULATOR, "customEvent:outbound_destination"],
          metrics: %w[eventCount totalUsers],
          date_ranges: STANDARD_DATE_RANGE,
          dimension_filter: EVENT_FILTER.call("commercial_outbound_clicked"),
          order_bys: [{ "metric" => "eventCount", "desc" => true }],
          limit: 500
        ),
        Definition.new(
          name: "realtime_events",
          kind: "realtime",
          dimensions: %w[eventName],
          metrics: %w[eventCount activeUsers],
          order_bys: [{ "metric" => "eventCount", "desc" => true }],
          limit: 100
        )
      ].to_h { |definition| [definition.name, definition] }.freeze

      module_function

      def fetch(name, kind: nil)
        requested = name.to_s
        canonical = ALIASES.fetch(requested, requested)
        definition = DEFINITIONS.fetch(canonical) do
          available = (names + ALIASES.keys).sort.join(", ")
          raise InvalidRequestError, "Unknown report #{name.inspect}; available reports: #{available}"
        end
        if kind && definition.kind != kind.to_s
          raise InvalidRequestError, "Report #{name} is #{definition.kind}, not #{kind}"
        end

        definition
      end

      def names
        DEFINITIONS.keys.sort.freeze
      end

      def aliases
        ALIASES.dup.freeze
      end

      def overview
        Overview::DEFINITIONS
      end
    end
  end
end
