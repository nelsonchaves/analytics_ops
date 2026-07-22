# frozen_string_literal: true

# CLI integration coverage.

require "stringio"
require "tempfile"
require "analytics_ops/cli"

RSpec.describe AnalyticsOps::CLI do
  def run(*arguments, workspace_loader: nil, input: StringIO.new)
    out = StringIO.new
    err = StringIO.new
    status = described_class.start(arguments, out:, err:, input:, workspace_loader:)

    [status, out.string, err.string]
  end

  def loader_for(workspace)
    ->(**_options) { workspace }
  end

  def report_result(kind: "standard")
    AnalyticsOps::Reports::Result.new(
      name: kind == "standard" ? "calculator_completions" : "realtime_events",
      kind:,
      dimension_headers: %w[eventName],
      metric_headers: %w[eventCount],
      rows: [{ "eventName" => "=unsafe", "eventCount" => "12" }],
      row_count: 1,
      metadata: {}
    )
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

  it "renders report results as human, JSON, and safe CSV output" do
    workspace = double("Workspace", report: report_result)
    loader = loader_for(workspace)

    human_status, human, = run("report", "calculator_completions", workspace_loader: loader)
    json_status, json, = run("report", "calculator_completions", "--format", "json", workspace_loader: loader)
    csv_status, csv, = run("report", "calculator_completions", "--format", "csv", workspace_loader: loader)

    expect([human_status, json_status, csv_status]).to all(eq(described_class::SUCCESS))
    expect(human).to include("Report calculator_completions", "eventName")
    expect(JSON.parse(json).fetch("rows").first.fetch("eventCount")).to eq("12")
    expect(csv).to eq("eventName,eventCount\n'=unsafe,12\n")
  end

  it "runs the default realtime recipe" do
    workspace = double("Workspace", realtime: report_result(kind: "realtime"))

    status, output, error = run("realtime", workspace_loader: loader_for(workspace))

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("realtime_events")
    expect(error).to be_empty
    expect(workspace).to have_received(:realtime).with("realtime_events")
  end

  it "accepts CSV only for report result commands" do
    status, output, error = run("schema", "--format", "csv")

    expect(status).to eq(described_class::USAGE_ERROR)
    expect(output).to be_empty
    expect(error).to include("CSV output is only valid for report results")
  end

  it "returns structured, redacted JSON errors" do
    workspace = double("Workspace")
    allow(workspace).to receive(:report)
      .and_raise(AnalyticsOps::RemoteError, "authorization=Bearer secret-token")

    status, output, error = run(
      "report", "calculator_completions", "--format", "json", workspace_loader: loader_for(workspace)
    )
    payload = JSON.parse(error).fetch("error")

    expect(status).to eq(described_class::REMOTE_ERROR)
    expect(output).to be_empty
    expect(payload.fetch("type")).to eq("RemoteError")
    expect(payload.fetch("message")).not_to include("secret-token")
  end

  it "strictly rejects extra arguments and command-only options" do
    expect(run("doctor", "extra").first).to eq(described_class::USAGE_ERROR)
    expect(run("audit", "--yes").first).to eq(described_class::USAGE_ERROR)
    expect(run("verify", "--output", "plan.json").first).to eq(described_class::USAGE_ERROR)
  end

  it "never prompts for non-interactive apply and requires --yes" do
    plan = AnalyticsOps::Planner.new(desired_state: build_desired_state, snapshot: snapshot).call
    input = double("Input")
    allow(input).to receive(:gets)
    Tempfile.create(["analytics-ops-plan", ".json"]) do |file|
      plan.write(file.path)
      status, output, error = run(
        "apply", file.path, "--non-interactive", workspace_loader: loader_for(double("Workspace")), input:
      )

      expect(status).to eq(described_class::USAGE_ERROR)
      expect(output).to include("before:", "after:")
      expect(error).to include("requires --yes")
      expect(input).not_to have_received(:gets)
    end
  end

  it "shows the exact saved plan before interactive confirmation" do
    plan = AnalyticsOps::Planner.new(desired_state: build_desired_state, snapshot: snapshot).call
    result = AnalyticsOps::Applier::Result.new(status: "applied", applied: plan.changes.map(&:to_h), failed: nil,
                                               remaining: [])
    workspace = double("Workspace")
    allow(workspace).to receive(:apply).and_return(result)
    Tempfile.create(["analytics-ops-plan", ".json"]) do |file|
      plan.write(file.path)
      status, output, error = run(
        "apply", file.path, workspace_loader: loader_for(workspace), input: StringIO.new("yes\n")
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(output).to include("before:", "after:", "https://old.example.com", "https://example.com")
      expect(error).to be_empty
      expect(workspace).to have_received(:apply).with(an_instance_of(AnalyticsOps::Plan), confirm: true)
    end
  end

  it "applies non-interactively only when --yes is explicit" do
    plan = AnalyticsOps::Planner.new(desired_state: build_desired_state, snapshot: snapshot).call
    result = AnalyticsOps::Applier::Result.new(status: "applied", applied: [], failed: nil, remaining: [])
    workspace = double("Workspace")
    allow(workspace).to receive(:apply).and_return(result)
    input = double("Input")
    allow(input).to receive(:gets)
    Tempfile.create(["analytics-ops-plan", ".json"]) do |file|
      plan.write(file.path)
      status, = run(
        "apply", file.path, "--non-interactive", "--yes", workspace_loader: loader_for(workspace), input:
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(input).not_to have_received(:gets)
      expect(workspace).to have_received(:apply).with(an_instance_of(AnalyticsOps::Plan), confirm: true)
    end
  end

  it "uses distinct stable statuses for typed operational failures" do
    cases = {
      AnalyticsOps::AuthenticationError => described_class::AUTHENTICATION_ERROR,
      AnalyticsOps::AuthorizationError => described_class::AUTHORIZATION_ERROR,
      AnalyticsOps::UnsupportedCapabilityError => described_class::UNSUPPORTED,
      AnalyticsOps::StalePlanError => described_class::STALE_PLAN,
      AnalyticsOps::QuotaError => described_class::QUOTA_ERROR,
      AnalyticsOps::TimeoutError => described_class::TIMEOUT_ERROR,
      AnalyticsOps::RemoteError => described_class::REMOTE_ERROR
    }

    cases.each do |error_class, expected_status|
      workspace = double("Workspace")
      allow(workspace).to receive(:doctor).and_raise(error_class, "failure")

      expect(run("doctor", workspace_loader: loader_for(workspace)).first).to eq(expected_status)
    end
  end
end
