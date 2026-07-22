# frozen_string_literal: true

# Apply safety coverage.

RSpec.describe AnalyticsOps::Applier do
  let(:remote_snapshot) { snapshot }
  let(:desired_state) { build_desired_state }
  let(:plan) { AnalyticsOps::Planner.new(desired_state:, snapshot: remote_snapshot).call }
  let(:admin) do
    instance_double(
      AnalyticsOps::Clients::Admin,
      snapshot: remote_snapshot,
      apply_change: nil
    )
  end

  it "requires explicit confirmation before it even refreshes remote state" do
    expect { described_class.new(admin:).call(plan) }
      .to raise_error(AnalyticsOps::ConfirmationRequiredError)
    expect(admin).not_to have_received(:snapshot)
  end

  it "rejects a stale plan before applying any operation" do
    allow(admin).to receive(:snapshot).and_return(snapshot(streams: []))

    expect { described_class.new(admin:).call(plan, confirm: true) }
      .to raise_error(AnalyticsOps::StalePlanError)
    expect(admin).not_to have_received(:apply_change)
  end

  it "applies exactly the ordered changes in the saved plan" do
    result = described_class.new(admin:).call(plan, confirm: true)

    expect(result.status).to eq("applied")
    expect(result.applied).to eq(plan.changes.map(&:to_h))
    expect(admin).to have_received(:apply_change).exactly(plan.changes.length).times
  end

  it "stops on first failure and returns reconciliation details" do
    allow(admin).to receive(:apply_change).and_raise(AnalyticsOps::RemoteError, "remote failure")

    expect { described_class.new(admin:).call(plan, confirm: true) }
      .to raise_error(AnalyticsOps::PartialApplyError) { |error| expect(error.result.status).to eq("partial") }
  end

  it "redacts remote failure details from partial-apply reconciliation" do
    allow(admin).to receive(:apply_change)
      .and_raise(AnalyticsOps::RemoteError, "authorization=Bearer secret-token")

    expect { described_class.new(admin:).call(plan, confirm: true) }
      .to raise_error(AnalyticsOps::PartialApplyError) do |error|
        expect(error.result.failed.fetch("message")).not_to include("secret-token")
      end
  end
end
