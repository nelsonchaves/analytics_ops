# frozen_string_literal: true

RSpec.describe AnalyticsOps::Clients::Data do
  let(:standard_definition) { AnalyticsOps::Reports::Catalog.fetch("calculator_completions") }
  let(:realtime_definition) { AnalyticsOps::Reports::Catalog.fetch("realtime_events") }
  let(:standard_response) do
    {
      dimension_headers: [{ name: "eventName" }, { name: "customEvent:calculator_slug" }],
      metric_headers: [{ name: "eventCount" }, { name: "totalUsers" }],
      rows: [
        {
          dimension_values: [{ value: "calculation_completed" }, { value: "concrete_volume" }],
          metric_values: [{ value: "42" }, { value: "36" }]
        }
      ],
      row_count: 1,
      metadata: {
        subject_to_thresholding: true,
        data_loss_from_other_row: false,
        currency_code: "USD",
        time_zone: "America/Los_Angeles",
        sampling_metadatas: [{ samples_read_count: 1_000, sampling_space_size: 2_000 }]
      },
      property_quota: { tokens_per_day: { consumed: 12, remaining: 99_988 } }
    }
  end
  let(:client) { double("GoogleDataClient") }
  let(:adapter) { described_class.new(client:) }

  it "translates a standard definition and normalizes the generated response" do
    request = nil
    allow(client).to receive(:run_report) do |value|
      request = value
      standard_response
    end

    result = adapter.run("123456789", standard_definition)

    expect(request).to include(
      property: "properties/123456789",
      dimensions: [{ name: "eventName" }, { name: "customEvent:calculator_slug" }],
      metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
      return_property_quota: true
    )
    expect(request.dig(:dimension_filter, :filter, :string_filter, :match_type)).to eq(:EXACT)
    expect(result.rows).to eq(
      [{
        "eventName" => "calculation_completed",
        "customEvent:calculator_slug" => "concrete_volume",
        "eventCount" => "42",
        "totalUsers" => "36"
      }]
    )
    expect(result.metadata.dig("property_quota", "tokens_per_day", "remaining")).to eq(99_988)
    expect(result.metadata.fetch("subject_to_thresholding")).to be(true)
    expect(result).to be_frozen
  end

  it "translates a realtime definition without date ranges or offsets" do
    request = nil
    allow(client).to receive(:run_realtime_report) do |value|
      request = value
      {
        dimension_headers: [{ name: "eventName" }],
        metric_headers: [{ name: "eventCount" }, { name: "activeUsers" }],
        rows: [],
        row_count: 0
      }
    end

    result = adapter.run("123456789", realtime_definition)

    expect(request).not_to have_key(:date_ranges)
    expect(request).not_to have_key(:offset)
    expect(result.kind).to eq("realtime")
  end

  it "coerces request hashes through the pinned official protobuf contracts" do
    require "google/analytics/data/v1beta"
    captured = nil
    allow(client).to receive(:run_report) do |request|
      captured = request
      standard_response
    end
    adapter.run("123456789", standard_definition)

    request = Google::Analytics::Data::V1beta::RunReportRequest.new(captured)

    expect(request.property).to eq("properties/123456789")
    expect(request.dimension_filter.filter.string_filter.match_type).to eq(:EXACT)
    expect(request.order_bys.first.metric.metric_name).to eq("eventCount")
  end

  it "coerces realtime and numeric-filter requests through official protobuf contracts" do
    require "google/analytics/data/v1beta"
    definition = AnalyticsOps::Reports::Definition.new(
      name: "realtime_filtered",
      kind: "realtime",
      dimensions: ["eventName"],
      metrics: ["eventCount"],
      metric_filter: { "field" => "eventCount", "operation" => "greater_than", "value" => 10 },
      limit: 10
    )
    captured = nil
    allow(client).to receive(:run_realtime_report) do |request|
      captured = request
      {
        dimension_headers: [{ name: "eventName" }],
        metric_headers: [{ name: "eventCount" }],
        rows: [],
        row_count: 0
      }
    end

    adapter.run("123456789", definition)
    request = Google::Analytics::Data::V1beta::RunRealtimeReportRequest.new(captured)

    expect(request.property).to eq("properties/123456789")
    expect(request.metric_filter.filter.numeric_filter.operation).to eq(:GREATER_THAN)
    expect(request.metric_filter.filter.numeric_filter.value.int64_value).to eq(10)
  end

  it "maps official client failures to typed, redacted Analytics Ops errors" do
    stub_const("Google::Cloud::PermissionDeniedError", Class.new(StandardError))
    allow(client).to receive(:run_report)
      .and_raise(Google::Cloud::PermissionDeniedError, "authorization=Bearer secret-token")

    expect { adapter.run("123456789", standard_definition) }
      .to raise_error(AnalyticsOps::AuthorizationError) { |error| expect(error.message).not_to include("secret-token") }
  end

  it "maps every documented operational error category" do
    mappings = {
      "Google::Cloud::UnauthenticatedError" => AnalyticsOps::AuthenticationError,
      "Google::Cloud::PermissionDeniedError" => AnalyticsOps::AuthorizationError,
      "Google::Cloud::ResourceExhaustedError" => AnalyticsOps::QuotaError,
      "Google::Cloud::DeadlineExceededError" => AnalyticsOps::TimeoutError,
      "Google::Cloud::InvalidArgumentError" => AnalyticsOps::InvalidRequestError,
      "Google::Cloud::UnknownError" => AnalyticsOps::RemoteError
    }

    mappings.each do |constant, expected|
      stub_const(constant, Class.new(StandardError))
      allow(client).to receive(:run_report).and_raise(Object.const_get(constant), "failure")

      expect { adapter.run("123456789", standard_definition) }.to raise_error(expected)
    end
  end

  it "rejects malformed response rows" do
    allow(client).to receive(:run_report).and_return(
      dimension_headers: [{ name: "eventName" }, { name: "customEvent:calculator_slug" }],
      metric_headers: [{ name: "eventCount" }, { name: "totalUsers" }],
      rows: [
        {
          dimension_values: [{ value: "calculation_completed" }],
          metric_values: [{ value: "1" }, { value: "1" }]
        }
      ],
      row_count: 1
    )

    expect { adapter.run("123456789", standard_definition) }
      .to raise_error(AnalyticsOps::RemoteError, /row.*not match/)
  end

  it "rejects a malformed response row count" do
    allow(client).to receive(:run_report).and_return(standard_response.merge(row_count: "not-a-number"))

    expect { adapter.run("123456789", standard_definition) }
      .to raise_error(AnalyticsOps::RemoteError, /invalid row count/)
  end

  it "logs only structured request metadata, never report rows" do
    logger = double("Logger", info: nil)
    logging_adapter = described_class.new(client:, logger:)
    allow(client).to receive(:run_report).and_return(standard_response)

    logging_adapter.run("123456789", standard_definition)

    expect(logger).to have_received(:info) do |message|
      expect(JSON.parse(message)).to include(
        "event" => "google_data_request",
        "method" => "run_report",
        "property" => "properties/123456789"
      )
      expect(message).not_to include("concrete_volume", "42")
    end
  end
end
