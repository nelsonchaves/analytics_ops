# frozen_string_literal: true

RSpec.describe AnalyticsOps::Reports::Definition do
  subject(:definition) do
    described_class.new(
      name: "example_report",
      kind: "standard",
      dimensions: %w[eventName],
      metrics: %w[eventCount],
      date_ranges: [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }],
      dimension_filter: { "field" => "eventName", "match_type" => "exact", "value" => "calculation_completed" },
      metric_filter: { "field" => "eventCount", "operation" => "greater_than", "value" => 0 },
      order_bys: [{ "metric" => "eventCount", "desc" => true }],
      limit: 250
    )
  end

  it "creates deeply immutable definitions" do
    expect(definition).to be_frozen
    expect(definition.dimensions).to be_frozen
    expect(definition.dimension_filter).to be_frozen
    expect(definition.to_h.fetch("limit")).to eq(250)
  end

  it "provides every required built-in recipe" do
    expect(AnalyticsOps::Reports::Catalog.names).to contain_exactly(
      "traffic_acquisition",
      "landing_pages",
      "calculator_completions",
      "shares_and_prints",
      "related_calculator_navigation",
      "commercial_outbound_clicks",
      "realtime_events"
    )
    expect(AnalyticsOps::Reports::Catalog::DEFINITIONS.values).to all(be_frozen)
  end

  it "keeps canonical recipe names while accepting friendly aliases" do
    expect(AnalyticsOps::Reports::Catalog.fetch("traffic").name).to eq("traffic_acquisition")
    expect(AnalyticsOps::Reports::Catalog.fetch("landing-pages").name).to eq("landing_pages")
    expect(AnalyticsOps::Reports::Catalog.names).not_to include("traffic", "landing-pages")
  end

  it "defines five small immutable overview reports" do
    overview = AnalyticsOps::Reports::Catalog.overview

    expect(overview.length).to eq(5)
    expect(overview).to be_frozen
    expect(overview).to all(be_frozen)
    expect(overview.sum(&:limit)).to be <= 62
  end

  it "rejects malformed names, dates, filters, orders, and limits" do
    base = {
      name: "example",
      kind: "standard",
      dimensions: %w[eventName],
      metrics: %w[eventCount],
      date_ranges: [{ "start_date" => "2026-02-30", "end_date" => "yesterday" }]
    }
    expect { described_class.new(**base) }.to raise_error(AnalyticsOps::InvalidRequestError, /date/i)
    expect { described_class.new(**base, date_ranges: [], name: "Bad name") }
      .to raise_error(AnalyticsOps::InvalidRequestError, /name/i)
    expect do
      described_class.new(**base, date_ranges: [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }],
                                  dimension_filter: { "field" => "city", "match_type" => "exact", "value" => "x" })
    end.to raise_error(AnalyticsOps::InvalidRequestError, /unselected dimension/i)
    expect do
      described_class.new(**base, date_ranges: [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }],
                                  order_bys: [{ "metric" => "sessions" }])
    end.to raise_error(AnalyticsOps::InvalidRequestError, /unselected metric/i)
    expect do
      described_class.new(**base, date_ranges: [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }], limit: 0)
    end.to raise_error(AnalyticsOps::InvalidRequestError, /limit/i)
  end

  it "accepts only documented date formats and rejects reversed relative ranges" do
    base = {
      name: "example",
      kind: "standard",
      dimensions: [],
      metrics: ["activeUsers"]
    }

    expect do
      described_class.new(
        **base,
        date_ranges: [{ "start_date" => "2026-W01-1", "end_date" => "2026-01-07" }]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /date/i)
    expect do
      described_class.new(
        **base,
        date_ranges: [{ "start_date" => "today", "end_date" => "yesterday" }]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /start_date/)
    expect do
      described_class.new(
        **base,
        date_ranges: [{ "start_date" => "1daysAgo", "end_date" => "28daysAgo" }]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /start_date/)
  end

  it "rejects reserved or duplicate date-range names" do
    base = {
      name: "example",
      kind: "standard",
      dimensions: [],
      metrics: ["activeUsers"]
    }

    expect do
      described_class.new(
        **base,
        date_ranges: [{ "start_date" => "7daysAgo", "end_date" => "yesterday", "name" => "date_range_1" }]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /name/i)
    expect do
      described_class.new(
        **base,
        date_ranges: [
          { "start_date" => "28daysAgo", "end_date" => "15daysAgo", "name" => "comparison" },
          { "start_date" => "14daysAgo", "end_date" => "yesterday", "name" => "comparison" }
        ]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /unique/i)
  end

  it "accepts only finite int64 or double numeric filter values" do
    attributes = {
      name: "example",
      kind: "standard",
      dimensions: [],
      metrics: ["activeUsers"],
      date_ranges: [{ "start_date" => "7daysAgo", "end_date" => "yesterday" }]
    }

    [Rational(1, 2), (2**63), Float::INFINITY].each do |value|
      expect do
        described_class.new(
          **attributes,
          metric_filter: { "field" => "activeUsers", "operation" => "greater_than", "value" => value }
        )
      end.to raise_error(AnalyticsOps::InvalidRequestError, /finite.*Integer.*Float/i)
    end
  end

  it "rejects duplicate ordering clauses" do
    expect do
      described_class.new(
        name: "example",
        kind: "standard",
        dimensions: ["date"],
        metrics: ["activeUsers"],
        date_ranges: [{ "start_date" => "7daysAgo", "end_date" => "yesterday" }],
        order_bys: [
          { "metric" => "activeUsers", "desc" => true },
          { "metric" => "activeUsers", "desc" => false }
        ]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /unique/i)
  end

  it "rejects dates and filter values containing control characters" do
    expect do
      described_class.new(
        name: "example",
        kind: "standard",
        dimensions: %w[eventName],
        metrics: %w[eventCount],
        date_ranges: [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }],
        dimension_filter: { "field" => "eventName", "match_type" => "exact", "value" => "bad\nvalue" }
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError)
  end

  it "enforces standard and realtime query shapes" do
    expect do
      described_class.new(
        name: "realtime",
        kind: "realtime",
        dimensions: %w[eventName],
        metrics: %w[eventCount],
        date_ranges: [{ "start_date" => "today", "end_date" => "today" }]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /Realtime reports cannot include date ranges/)

    expect do
      described_class.new(
        name: "standard",
        kind: "standard",
        dimensions: %w[eventName],
        metrics: %w[eventCount]
      )
    end.to raise_error(AnalyticsOps::InvalidRequestError, /require a date range/)
  end
end
