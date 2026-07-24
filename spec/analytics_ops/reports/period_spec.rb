# frozen_string_literal: true

RSpec.describe AnalyticsOps::Reports::Period do
  it "builds a bounded complete-day range" do
    expect(described_class.resolve(last_days: 7)).to eq(
      [{ "start_date" => "7daysAgo", "end_date" => "yesterday" }]
    )
  end

  it "builds an equally long preceding comparison range" do
    expect(described_class.resolve(last_days: 7, compare: true)).to eq(
      [
        { "start_date" => "7daysAgo", "end_date" => "yesterday", "name" => "current" },
        { "start_date" => "14daysAgo", "end_date" => "8daysAgo", "name" => "previous" }
      ]
    )
    expect(described_class.resolve(compare: true).first.fetch("start_date")).to eq("28daysAgo")
  end

  it "builds absolute and preceding calendar ranges" do
    expect(
      described_class.resolve(
        start_date: "2026-07-01",
        end_date: "2026-07-07",
        compare: true
      )
    ).to eq(
      [
        { "start_date" => "2026-07-01", "end_date" => "2026-07-07", "name" => "current" },
        { "start_date" => "2026-06-24", "end_date" => "2026-06-30", "name" => "previous" }
      ]
    )
  end

  it "returns nil when no override or comparison was requested" do
    expect(described_class.resolve).to be_nil
  end

  it "rejects conflicting, incomplete, malformed, reversed, or excessive ranges" do
    expect do
      described_class.resolve(last_days: 7, start_date: "2026-07-01", end_date: "2026-07-07")
    end.to raise_error(AnalyticsOps::InvalidRequestError, /either --last/)
    expect { described_class.resolve(start_date: "2026-07-01") }
      .to raise_error(AnalyticsOps::InvalidRequestError, /used together/)
    expect { described_class.resolve(start_date: "2026-02-30", end_date: "2026-03-01") }
      .to raise_error(AnalyticsOps::InvalidRequestError, /real calendar date/)
    expect { described_class.resolve(start_date: "2026-07-08", end_date: "2026-07-01") }
      .to raise_error(AnalyticsOps::InvalidRequestError, /must not be after/)
    expect { described_class.resolve(last_days: described_class::MAX_DAYS + 1) }
      .to raise_error(AnalyticsOps::InvalidRequestError, /between 1/)
    expect { described_class.resolve(start_date: "2020-01-01", end_date: "2026-07-01") }
      .to raise_error(AnalyticsOps::InvalidRequestError, /cannot exceed/)
  end
end
