# frozen_string_literal: true

RSpec.describe AnalyticsOps::Reports::Result do
  it "exposes deeply immutable headers and string-valued rows without freezing caller values" do
    dimension_headers = [+"eventName"]
    row_value = +"calculation_completed"
    rows = [{ "eventName" => row_value, "eventCount" => "12" }]

    result = described_class.new(
      name: "example",
      kind: "standard",
      dimension_headers:,
      metric_headers: ["eventCount"],
      rows:,
      row_count: 1,
      metadata: {}
    )

    expect(result.headers).to eq(%w[eventName eventCount])
    expect(result.headers).to be_frozen
    expect(result.headers).to equal(result.headers)
    expect(dimension_headers.first).not_to be_frozen
    expect(row_value).not_to be_frozen
    expect(result.rows.first.fetch("eventName")).not_to equal(row_value)
  end

  it "rejects non-string row values from malformed remote responses" do
    expect do
      described_class.new(
        name: "example",
        kind: "standard",
        dimension_headers: [],
        metric_headers: ["eventCount"],
        rows: [{ "eventCount" => 12 }],
        row_count: 1,
        metadata: {}
      )
    end.to raise_error(AnalyticsOps::RemoteError, /valid UTF-8 strings/)
  end

  it "rejects metadata that cannot be serialized safely" do
    [Float::NAN, Object.new, { unsafe: true }].each do |metadata|
      expect do
        described_class.new(
          name: "example",
          kind: "standard",
          dimension_headers: [],
          metric_headers: ["eventCount"],
          rows: [],
          row_count: 0,
          metadata: metadata.is_a?(Hash) ? metadata : { "value" => metadata }
        )
      end.to raise_error(AnalyticsOps::RemoteError)
    end

    expect do
      described_class.new(
        name: "example",
        kind: "standard",
        dimension_headers: [],
        metric_headers: ["eventCount"],
        rows: [],
        row_count: 0,
        metadata: []
      )
    end.to raise_error(AnalyticsOps::RemoteError, /metadata must be an object/)
  end

  it "rejects invalidly encoded remote text before JSON rendering" do
    invalid = "bad\xFF".dup.force_encoding(Encoding::UTF_8)

    expect do
      described_class.new(
        name: "example",
        kind: "standard",
        dimension_headers: [],
        metric_headers: ["eventCount"],
        rows: [{ "eventCount" => invalid }],
        row_count: 1,
        metadata: {}
      )
    end.to raise_error(AnalyticsOps::RemoteError, /valid UTF-8/)
  end
end
