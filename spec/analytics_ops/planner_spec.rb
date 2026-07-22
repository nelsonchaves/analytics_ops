# frozen_string_literal: true

# Planning contract coverage.

require "tmpdir"

RSpec.describe AnalyticsOps::Planner do
  subject(:plan) { described_class.new(desired_state:, snapshot: snapshot).call }

  let(:desired_state) { build_desired_state }

  it "produces only deterministic, non-destructive creates and updates" do
    expect(plan.changes.map { |change| [change.resource_type, change.operation] }).to contain_exactly(
      %w[data_stream update],
      %w[retention update],
      %w[key_event create],
      %w[custom_dimension update]
    )
    expect(plan.changes.map(&:operation)).not_to include("delete", "archive")
    expect(plan.to_json).to eq(described_class.new(desired_state:, snapshot: snapshot).call.to_json)
  end

  it "does not plan deletion of unmanaged remote resources" do
    remote = snapshot(key_events: [key_event, key_event("remote_only")])

    result = described_class.new(desired_state:, snapshot: remote).call

    expect(result.changes.none? { |change| change.resource_identity.include?("remote_only") }).to be(true)
  end

  it "round-trips the versioned plan format byte-for-byte" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "plan.json")
      plan.write(path)

      expect(AnalyticsOps::Plan.load(path).to_json).to eq(plan.to_json)
      expect(File.stat(path).mode & 0o777).to eq(0o600)
    end
  end

  it "stops on ambiguous remote identity" do
    remote = snapshot(custom_dimensions: [custom_dimension, custom_dimension])

    expect { described_class.new(desired_state:, snapshot: remote).call }
      .to raise_error(AnalyticsOps::ConflictError, /Ambiguous remote custom dimension/)
  end

  it "proves convergence by producing no changes for matching remote state" do
    converged = snapshot(
      streams: [stream(default_uri: "https://example.com")],
      retention: retention(event_data: "14_months"),
      key_events: [key_event, key_event("calculation_completed")],
      custom_dimensions: [custom_dimension(description: "Published calculator identifier")]
    )

    result = described_class.new(desired_state:, snapshot: converged).call

    expect(result.changes).to be_empty
    expect(result).not_to be_drift
  end

  it "carries restricted-data classification into currency metric creation" do
    remote = snapshot(custom_metrics: [])

    result = described_class.new(desired_state:, snapshot: remote).call
    metric = result.changes.find { |change| change.resource_type == "custom_metric" }

    expect(metric.after.fetch("restricted_metric_types")).to eq(["revenue_data"])
  end

  it "reports a restricted-data classification conflict without changing the metric" do
    conflicting_metric = AnalyticsOps::Resources::CustomMetric.new(
      **custom_metric.to_h.transform_keys(&:to_sym),
      restricted_metric_types: ["cost_data"]
    )
    remote = snapshot(custom_metrics: [conflicting_metric])

    result = described_class.new(desired_state:, snapshot: remote).call

    expect(result.changes.none? { |change| change.resource_type == "custom_metric" }).to be(true)
    expect(result.findings.map(&:code)).to include("immutable_metric_conflict")
  end

  it "reports an unsupported remote retention value instead of emitting an invalid plan" do
    unusual = AnalyticsOps::Resources::Retention.new(
      name: "properties/123456789/dataRetentionSettings",
      event_data: "unspecified",
      user_data: "14_months",
      reset_on_new_activity: false
    )

    result = described_class.new(desired_state:, snapshot: snapshot(retention: unusual)).call

    expect(result.changes.none? { |change| change.resource_type == "retention" }).to be(true)
    expect(result.findings.map(&:code)).to include("retention_unsupported")
  end
end
