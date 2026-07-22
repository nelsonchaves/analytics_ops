# frozen_string_literal: true

RSpec.describe AnalyticsOps do
  it "has a version number" do
    expect(AnalyticsOps::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
