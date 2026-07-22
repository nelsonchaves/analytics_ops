# frozen_string_literal: true

require "google/analytics/admin/v1alpha"

RSpec.describe AnalyticsOps::Clients::Admin do
  let(:google) { Google::Analytics::Admin::V1alpha }
  let(:client) { double("GoogleAdminClient") }
  let(:adapter) { described_class.new(client:) }

  def change(resource_type:, operation:, identity:, before:, after:)
    AnalyticsOps::Plan::Change.new(
      resource_type:,
      resource_identity: identity,
      operation:,
      api_maturity: "beta",
      before:,
      after:,
      reversible: true,
      rollback: "Restore the prior value"
    )
  end

  it "proves account, property, and stream discovery request and response contracts" do
    account_request = nil
    stream_request = nil
    allow(client).to receive(:list_account_summaries) do |request|
      account_request = request
      [google::AccountSummary.new(
        account: "accounts/100000001",
        display_name: "Example account",
        property_summaries: [
          google::PropertySummary.new(
            property: "properties/123456789",
            display_name: "Example property",
            property_type: :PROPERTY_TYPE_ORDINARY
          )
        ]
      )]
    end
    allow(client).to receive(:list_data_streams) do |request|
      stream_request = request
      [google::DataStream.new(
        name: "properties/123456789/dataStreams/987654321",
        type: :WEB_DATA_STREAM,
        display_name: "Example web stream",
        web_stream_data: { default_uri: "https://example.test", measurement_id: "G-EXAMPLE1" }
      )]
    end

    accounts = adapter.discover

    expect(google::ListAccountSummariesRequest.new(account_request).page_size).to eq(200)
    expect(google::ListDataStreamsRequest.new(stream_request).parent).to eq("properties/123456789")
    expect(accounts.first.id).to eq("100000001")
    expect(accounts.first.properties.first.fetch("streams").first.fetch("measurement_id")).to eq("G-EXAMPLE1")
    expect(accounts).to be_frozen
    expect(accounts.first).to be_frozen
  end

  it "lists account and property summaries without fetching every stream" do
    allow(client).to receive(:list_account_summaries).and_return(
      [google::AccountSummary.new(
        account: "accounts/100000001",
        display_name: "Example account",
        property_summaries: [
          google::PropertySummary.new(
            property: "properties/123456789",
            display_name: "Example property",
            property_type: :PROPERTY_TYPE_ORDINARY
          )
        ]
      )]
    )
    allow(client).to receive(:list_data_streams)

    accounts = adapter.discover(include_streams: false)

    expect(accounts.first.properties.first).not_to have_key("streams")
    expect(client).not_to have_received(:list_data_streams)
  end

  it "proves all snapshot request shapes and normalizes generated responses" do
    requests = {}
    allow(client).to receive(:get_property) do |request|
      requests[:get_property] = request
      google::Property.new(
        name: "properties/123456789",
        display_name: "Example property",
        parent: "accounts/100000001",
        property_type: :PROPERTY_TYPE_ORDINARY
      )
    end
    allow(client).to receive(:list_data_streams) do |request|
      requests[:list_data_streams] = request
      [google::DataStream.new(
        name: "properties/123456789/dataStreams/987654321",
        type: :WEB_DATA_STREAM,
        display_name: "Example web stream",
        web_stream_data: { default_uri: "https://example.test", measurement_id: "G-EXAMPLE1" }
      )]
    end
    allow(client).to receive(:get_data_retention_settings) do |request|
      requests[:get_data_retention_settings] = request
      google::DataRetentionSettings.new(
        name: "properties/123456789/dataRetentionSettings",
        event_data_retention: :FOURTEEN_MONTHS,
        user_data_retention: :FOURTEEN_MONTHS,
        reset_user_data_on_new_activity: false
      )
    end
    allow(client).to receive(:list_key_events) do |request|
      requests[:list_key_events] = request
      [google::KeyEvent.new(
        name: "properties/123456789/keyEvents/1",
        event_name: "calculation_completed",
        counting_method: :ONCE_PER_EVENT
      )]
    end
    allow(client).to receive(:list_custom_dimensions) do |request|
      requests[:list_custom_dimensions] = request
      [google::CustomDimension.new(
        name: "properties/123456789/customDimensions/1",
        parameter_name: "calculator_slug",
        display_name: "Calculator slug",
        description: "Published calculator identifier",
        scope: :EVENT,
        disallow_ads_personalization: false
      )]
    end
    allow(client).to receive(:list_custom_metrics) do |request|
      requests[:list_custom_metrics] = request
      [google::CustomMetric.new(
        name: "properties/123456789/customMetrics/1",
        parameter_name: "project_value",
        display_name: "Project value",
        description: "Estimated project value",
        scope: :EVENT,
        measurement_unit: :CURRENCY,
        restricted_metric_type: [:REVENUE_DATA]
      )]
    end

    result = adapter.snapshot("123456789")

    expect(google::GetPropertyRequest.new(requests.fetch(:get_property)).name).to eq("properties/123456789")
    expect(google::ListDataStreamsRequest.new(requests.fetch(:list_data_streams)).page_size).to eq(200)
    expect(google::GetDataRetentionSettingsRequest.new(requests.fetch(:get_data_retention_settings)).name)
      .to eq("properties/123456789/dataRetentionSettings")
    expect(google::ListKeyEventsRequest.new(requests.fetch(:list_key_events)).parent).to eq("properties/123456789")
    expect(google::ListCustomDimensionsRequest.new(requests.fetch(:list_custom_dimensions)).parent)
      .to eq("properties/123456789")
    expect(google::ListCustomMetricsRequest.new(requests.fetch(:list_custom_metrics)).parent)
      .to eq("properties/123456789")
    expect(result.retention.event_data).to eq("14_months")
    expect(result.custom_dimensions.first.scope).to eq("event")
    expect(result.custom_metrics.first.measurement_unit).to eq("currency")
    expect(result.custom_metrics.first.restricted_metric_types).to eq(["revenue_data"])
  end

  it "proves every supported mutation request against pinned protobuf coercion" do
    requests = {}
    %i[
      update_data_stream
      update_data_retention_settings
      create_key_event
      create_custom_dimension
      update_custom_dimension
      create_custom_metric
      update_custom_metric
    ].each do |method_name|
      allow(client).to receive(method_name) do |request|
        requests[method_name] = request
        Object.new
      end
    end

    stream_before = stream.to_h
    adapter.apply_change(
      change(
        resource_type: "data_stream", operation: "update", identity: "stream:987654321",
        before: stream_before, after: stream_before.merge("default_uri" => "https://new.example.test")
      ),
      property_id: "123456789"
    )
    retention_before = retention.to_h
    adapter.apply_change(
      change(
        resource_type: "retention", operation: "update", identity: "property:123456789:retention",
        before: retention_before, after: retention_before.merge("event_data" => "14_months")
      ),
      property_id: "123456789"
    )
    adapter.apply_change(
      change(
        resource_type: "key_event", operation: "create", identity: "event:calculation_completed", before: nil,
        after: { "event_name" => "calculation_completed", "counting_method" => "once_per_session" }
      ),
      property_id: "123456789"
    )
    dimension_create = {
      "parameter_name" => "category", "display_name" => "Category", "description" => "Calculator category",
      "scope" => "event", "disallow_ads_personalization" => false
    }
    adapter.apply_change(
      change(
        resource_type: "custom_dimension", operation: "create", identity: "event:category",
        before: nil, after: dimension_create
      ),
      property_id: "123456789"
    )
    dimension_before = custom_dimension.to_h
    adapter.apply_change(
      change(
        resource_type: "custom_dimension", operation: "update", identity: "event:calculator_slug",
        before: dimension_before, after: dimension_before.merge("description" => "Updated description")
      ),
      property_id: "123456789"
    )
    metric_create = {
      "parameter_name" => "estimate_total", "display_name" => "Estimate total", "description" => "Estimate",
      "scope" => "event", "measurement_unit" => "currency", "restricted_metric_types" => ["revenue_data"]
    }
    adapter.apply_change(
      change(
        resource_type: "custom_metric", operation: "create", identity: "estimate_total",
        before: nil, after: metric_create
      ),
      property_id: "123456789"
    )
    metric_before = custom_metric.to_h
    adapter.apply_change(
      change(
        resource_type: "custom_metric", operation: "update", identity: "project_value",
        before: metric_before, after: metric_before.merge("description" => "Updated estimate")
      ),
      property_id: "123456789"
    )

    stream_request = google::UpdateDataStreamRequest.new(requests.fetch(:update_data_stream))
    expect(stream_request.data_stream.web_stream_data.default_uri).to eq("https://new.example.test")
    expect(stream_request.update_mask.paths).to eq(["web_stream_data.default_uri"])
    retention_request = google::UpdateDataRetentionSettingsRequest.new(requests.fetch(:update_data_retention_settings))
    expect(retention_request.data_retention_settings.event_data_retention).to eq(:FOURTEEN_MONTHS)
    key_event_request = google::CreateKeyEventRequest.new(requests.fetch(:create_key_event))
    expect(key_event_request.key_event.counting_method).to eq(:ONCE_PER_SESSION)
    dimension_create_request = google::CreateCustomDimensionRequest.new(requests.fetch(:create_custom_dimension))
    expect(dimension_create_request.custom_dimension.scope).to eq(:EVENT)
    dimension_update_request = google::UpdateCustomDimensionRequest.new(requests.fetch(:update_custom_dimension))
    expect(dimension_update_request.update_mask.paths).to include("description")
    metric_create_request = google::CreateCustomMetricRequest.new(requests.fetch(:create_custom_metric))
    expect(metric_create_request.custom_metric.measurement_unit).to eq(:CURRENCY)
    expect(metric_create_request.custom_metric.restricted_metric_type).to eq([:REVENUE_DATA])
    metric_update_request = google::UpdateCustomMetricRequest.new(requests.fetch(:update_custom_metric))
    expect(metric_update_request.update_mask.paths).to contain_exactly("display_name", "description")
  end

  it "maps official failures to typed, redacted errors" do
    stub_const("Google::Cloud::UnauthenticatedError", Class.new(StandardError))
    allow(client).to receive(:get_property)
      .and_raise(Google::Cloud::UnauthenticatedError, "access_token=secret-token")

    expect { adapter.snapshot("123456789") }
      .to raise_error(AnalyticsOps::AuthenticationError) { |error| expect(error.message).not_to include("secret-token") }
  end

  it "maps timeouts from official client transports" do
    stub_const("Google::Cloud::DeadlineExceededError", Class.new(StandardError))
    allow(client).to receive(:get_property).and_raise(Google::Cloud::DeadlineExceededError, "deadline")

    expect { adapter.snapshot("123456789") }.to raise_error(AnalyticsOps::TimeoutError)
  end

  it "maps raw socket failures to a typed remote error" do
    allow(client).to receive(:get_property).and_raise(SocketError, "connection reset")

    expect { adapter.snapshot("123456789") }.to raise_error(AnalyticsOps::RemoteError, /connection reset/)
  end

  it "translates failures raised while a paginated response fetches later pages" do
    response = Object.new
    allow(response).to receive(:to_a).and_raise(SocketError, "second page failed")
    allow(client).to receive(:list_account_summaries).and_return(response)

    expect { adapter.discover }.to raise_error(AnalyticsOps::RemoteError, /second page failed/)
  end

  it "strictly validates public client options and property IDs" do
    expect { described_class.new(client:, transport: nil) }
      .to raise_error(AnalyticsOps::ConfigurationError, /transport/)
    expect { described_class.new(client:, timeout: 0) }
      .to raise_error(AnalyticsOps::ConfigurationError, /timeout/)
    expect { adapter.snapshot(123_456_789) }
      .to raise_error(AnalyticsOps::ConfigurationError, /property ID/)
  end

  it "rejects malformed booleans in normalized Admin responses" do
    allow(client).to receive(:get_property).and_return(
      google::Property.new(name: "properties/123456789", display_name: "Example property")
    )
    allow(client).to receive(:list_data_streams).and_return([])
    allow(client).to receive(:get_data_retention_settings).and_return(
      {
        name: "properties/123456789/dataRetentionSettings",
        event_data_retention: :FOURTEEN_MONTHS,
        user_data_retention: :FOURTEEN_MONTHS,
        reset_user_data_on_new_activity: "false"
      }
    )
    allow(client).to receive(:list_key_events).and_return([])
    allow(client).to receive(:list_custom_dimensions).and_return([])
    allow(client).to receive(:list_custom_metrics).and_return([])

    expect { adapter.snapshot("123456789") }
      .to raise_error(AnalyticsOps::RemoteError, /invalid boolean/)
  end

  it "does not coerce malformed remote strings" do
    allow(client).to receive(:get_property).and_return(
      { name: 123_456_789, display_name: "Example property" }
    )

    expect { adapter.snapshot("123456789") }
      .to raise_error(AnalyticsOps::RemoteError, /invalid property name/)
  end

  it "rejects snapshot resources returned for another property" do
    allow(client).to receive(:get_property).and_return(
      google::Property.new(name: "properties/123456789", display_name: "Example property")
    )
    allow(client).to receive(:list_data_streams).and_return(
      [google::DataStream.new(name: "properties/999999999/dataStreams/987654321", type: :WEB_DATA_STREAM)]
    )
    allow(client).to receive(:get_data_retention_settings).and_return(
      google::DataRetentionSettings.new(name: "properties/123456789/dataRetentionSettings")
    )
    allow(client).to receive(:list_key_events).and_return([])
    allow(client).to receive(:list_custom_dimensions).and_return([])
    allow(client).to receive(:list_custom_metrics).and_return([])

    expect { adapter.snapshot("123456789") }
      .to raise_error(AnalyticsOps::RemoteError, /different property/)
  end

  it "does not expose generated Google objects publicly" do
    allow(client).to receive(:get_property).and_return(
      google::Property.new(name: "properties/123456789", display_name: "Example property")
    )
    allow(client).to receive(:list_data_streams).and_return([])
    allow(client).to receive(:get_data_retention_settings).and_return(
      google::DataRetentionSettings.new(name: "properties/123456789/dataRetentionSettings")
    )
    allow(client).to receive(:list_key_events).and_return([])
    allow(client).to receive(:list_custom_dimensions).and_return([])
    allow(client).to receive(:list_custom_metrics).and_return([])

    result = adapter.snapshot("123456789")

    expect(result).to be_a(AnalyticsOps::Snapshot)
    expect(result.property).to be_a(AnalyticsOps::Resources::Property)
    expect(result.to_h.to_s).not_to include("Google::Analytics")
  end
end
