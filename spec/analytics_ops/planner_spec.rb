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
end
