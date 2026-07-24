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

  it "applies immutable date overrides to standard reports and overview batches" do
    ranges = AnalyticsOps::Reports::Period.resolve(last_days: 7, compare: true)
    report_definition = AnalyticsOps::Reports::Catalog.fetch("calculator_completions").with_date_ranges(ranges)
    overview_definitions = AnalyticsOps::Reports::Catalog.overview.map do |definition|
      definition.with_date_ranges(ranges)
    end
    allow(data).to receive(:run).with(
      "123456789",
      an_object_having_attributes(to_h: report_definition.to_h)
    ).and_return(result)
    allow(data).to receive(:batch).with(
      "123456789",
      satisfy { |definitions| definitions.map(&:to_h) == overview_definitions.map(&:to_h) }
    ).and_return(
      overview_definitions.map do |definition|
        AnalyticsOps::Reports::Result.new(
          name: definition.name,
          kind: "standard",
          dimension_headers: definition.dimensions + ["dateRange"],
          metric_headers: definition.metrics,
          rows: [],
          row_count: 0,
          metadata: {}
        )
      end
    )

    expect(workspace.report("calculator_completions", date_ranges: ranges)).to equal(result)
    expect(workspace.overview(date_ranges: ranges).reports.length).to eq(5)
    expect(AnalyticsOps::Reports::Catalog.fetch("calculator_completions").date_ranges)
      .to eq(AnalyticsOps::Reports::Catalog::STANDARD_DATE_RANGE)
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

  it "returns a gem-owned immutable batched overview" do
    reports = AnalyticsOps::Reports::Catalog.overview.map do |definition|
      AnalyticsOps::Reports::Result.new(
        name: definition.name,
        kind: "standard",
        dimension_headers: definition.dimensions,
        metric_headers: definition.metrics,
        rows: [],
        row_count: 0,
        metadata: { "property_quota" => { "tokens_per_day" => { "consumed" => 5, "remaining" => 199_995 } } }
      )
    end
    allow(data).to receive(:batch).with("123456789", AnalyticsOps::Reports::Catalog.overview).and_return(reports)

    overview = workspace.overview

    expect(overview).to be_a(AnalyticsOps::Reports::OverviewResult)
    expect(overview).to be_frozen
    expect(overview.reports).to be_frozen
    expect(overview.property_quota.dig("tokens_per_day", "remaining")).to eq(199_995)
  end

  it "keeps overview property identifiers strictly string-typed" do
    expect do
      AnalyticsOps::Reports::OverviewResult.new(property_id: 123_456_789, reports: [result])
    end.to raise_error(AnalyticsOps::RemoteError, /property ID/)
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
      "google-analytics-admin", "google-analytics-data", "local_clock", "credential_scope"
    )
    expect(checks.dig("edit_capability", "status")).to eq("ok")
    expect(checks.dig("credential_scope", "status")).to eq("ok")
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

  it "requests edit-scoped service-account credentials only for apply" do
    service_account = AnalyticsOps::ServiceAccount.allocate
    edit_adapter = instance_double(AnalyticsOps::Clients::Admin)
    plan = AnalyticsOps::Plan.new(
      profile: "production",
      property_id: "123456789",
      snapshot_fingerprint: "sha256:#{"0" * 64}",
      changes: [],
      findings: []
    )
    result = instance_double(AnalyticsOps::Applier::Result)
    allow(AnalyticsOps::Clients::Admin).to receive(:new).and_return(edit_adapter)
    allow(AnalyticsOps::Applier).to receive(:new)
      .with(admin: edit_adapter)
      .and_return(instance_double(AnalyticsOps::Applier, call: result))
    edit_workspace = described_class.new(desired_state:, service_account:)

    expect(edit_workspace.apply(plan, confirm: true)).to equal(result)
    expect(AnalyticsOps::Clients::Admin).to have_received(:new).with(
      service_account:,
      access: :edit,
      transport: :grpc,
      timeout: nil,
      logger: nil
    )
  end
end
