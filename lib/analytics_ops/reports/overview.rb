# frozen_string_literal: true

module AnalyticsOps
  module Reports
    # Internal catalog for the small reports shown by Workspace#overview.
    module Overview
      DEFINITIONS = [
        Definition.new(
          name: "overview_totals",
          kind: "standard",
          dimensions: [],
          metrics: %w[activeUsers sessions keyEvents],
          date_ranges: Catalog::STANDARD_DATE_RANGE,
          limit: 1
        ),
        Definition.new(
          name: "overview_trend",
          kind: "standard",
          dimensions: %w[date],
          metrics: %w[activeUsers sessions keyEvents],
          date_ranges: Catalog::STANDARD_DATE_RANGE,
          order_bys: [{ "dimension" => "date", "desc" => false }],
          limit: 31
        ),
        Definition.new(
          name: "overview_acquisition",
          kind: "standard",
          dimensions: %w[sessionDefaultChannelGroup],
          metrics: %w[sessions activeUsers keyEvents],
          date_ranges: Catalog::STANDARD_DATE_RANGE,
          order_bys: [{ "metric" => "sessions", "desc" => true }],
          limit: 10
        ),
        Definition.new(
          name: "overview_landing_pages",
          kind: "standard",
          dimensions: %w[landingPagePlusQueryString],
          metrics: %w[sessions activeUsers keyEvents],
          date_ranges: Catalog::STANDARD_DATE_RANGE,
          order_bys: [{ "metric" => "sessions", "desc" => true }],
          limit: 10
        ),
        Definition.new(
          name: "overview_devices",
          kind: "standard",
          dimensions: %w[deviceCategory],
          metrics: %w[activeUsers sessions keyEvents],
          date_ranges: Catalog::STANDARD_DATE_RANGE,
          order_bys: [{ "metric" => "activeUsers", "desc" => true }],
          limit: 10
        )
      ].freeze
    end
  end
end
