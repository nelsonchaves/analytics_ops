# frozen_string_literal: true

RSpec.describe AnalyticsOps::Workspace do
  let(:admin) { instance_double(AnalyticsOps::Clients::Admin) }
  let(:data) { instance_double(AnalyticsOps::Clients::Data) }
  let(:desired_state) { build_desired_state }
  let(:workspace) { described_class.new(desired_state:, admin:, data:) }
  let(:result) do
    AnalyticsOps::Reports::Result.new(
      name: "calculator_completions",
      kind: "standard",
      dimension_headers: %w[eventName],
      metric_headers: %w[eventCount],
      rows: [{ "eventName" => "calculation_completed", "eventCount" => "12" }],
      row_count: 1,
      metadata: {}
    )
  end

  it "injects the Data adapter independently from the Admin adapter" do
    definition = AnalyticsOps::Reports::Catalog.fetch("calculator_completions")
    allow(admin).to receive(:snapshot)
    allow(data).to receive(:run).with("123456789", definition).and_return(result)

    expect(workspace.report("calculator_completions")).to equal(result)
    expect(admin).not_to have_received(:snapshot)
  end

  it "runs the default realtime recipe" do
    definition = AnalyticsOps::Reports::Catalog.fetch("realtime_events")
    realtime_result = AnalyticsOps::Reports::Result.new(
      name: "realtime_events",
      kind: "realtime",
      dimension_headers: [],
      metric_headers: [],
      rows: [],
      row_count: 0,
      metadata: {}
    )
    allow(data).to receive(:run).with("123456789", definition).and_return(realtime_result)

    expect(workspace.realtime).to equal(realtime_result)
  end

  it "rejects a realtime definition passed to report" do
    definition = AnalyticsOps::Reports::Catalog.fetch("realtime_events")

    expect { workspace.report(definition) }
      .to raise_error(AnalyticsOps::InvalidRequestError, /realtime, not standard/)
  end

  it "checks credentials, both APIs, property access, compatibility, edit access, and clock sanity" do
    allow(admin).to receive(:snapshot).with("123456789").and_return(snapshot)
    allow(admin).to receive(:property_access).with("123456789").and_return(property)
    allow(admin).to receive(:capabilities).and_return("data_retention" => true)
    allow(admin).to receive(:compatibility).and_return(
      "package" => "google-analytics-admin", "version" => "0.8.0", "requirement" => "~> 0.8.0",
      "supported" => true, "transport" => "grpc"
    )
    allow(data).to receive(:compatibility).and_return(
      "package" => "google-analytics-data", "version" => "0.9.0", "requirement" => "~> 0.9.0",
      "supported" => true, "transport" => "grpc"
    )
    allow(data).to receive(:run).and_return(result)

    doctor = workspace.doctor
    checks = doctor.checks.to_h { |check| [check.fetch("name"), check] }

    expect(doctor).to be_success
    expect(checks.keys).to include(
      "configuration", "credentials", "admin_api", "data_api", "property_access", "edit_capability",
      "google-analytics-admin", "google-analytics-data", "local_clock", "oauth_scopes"
    )
    expect(checks.dig("edit_capability", "status")).to eq("ok")
    expect(checks.dig("oauth_scopes", "status")).to eq("unknown")
    expect(data).to have_received(:run).with(
      "123456789",
      an_object_having_attributes(name: "doctor_connectivity", limit: 1, kind: "standard")
    )
  end

  it "preserves typed credential failures without calling the Data API" do
    allow(admin).to receive(:snapshot).and_raise(AnalyticsOps::AuthenticationError, "credentials unavailable")
    allow(data).to receive(:run)

    expect { workspace.doctor }.to raise_error(AnalyticsOps::AuthenticationError)
    expect(data).not_to have_received(:run)
  end
end
