# frozen_string_literal: true

require "stringio"
require "analytics_ops/cli"

RSpec.describe AnalyticsOps::CLI do
  def run(*arguments)
    out = StringIO.new
    err = StringIO.new
    status = described_class.start(arguments, out:, err:)

    [status, out.string, err.string]
  end

  it "shows help without contacting a provider" do
    status, out, err = run("help")

    expect(status).to eq(AnalyticsOps::CLI::SUCCESS)
    expect(out).to include("Google Analytics 4 configuration as code")
    expect(err).to be_empty
  end

  it "prints the installed version" do
    status, out, err = run("version")

    expect(status).to eq(AnalyticsOps::CLI::SUCCESS)
    expect(out).to eq("#{AnalyticsOps::VERSION}\n")
    expect(err).to be_empty
  end

  it "returns a stable usage status for an unknown command" do
    status, out, err = run("unknown")

    expect(status).to eq(AnalyticsOps::CLI::USAGE_ERROR)
    expect(out).to be_empty
    expect(err).to include("Unknown command: unknown")
  end
end
