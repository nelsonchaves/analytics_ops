# frozen_string_literal: true

# CLI integration coverage.

require "stringio"
require "tempfile"
require "tmpdir"
require "analytics_ops/cli"

RSpec.describe AnalyticsOps::CLI do
  def run(*arguments, workspace_loader: nil, connection_loader: nil, command_runner: nil, input: StringIO.new)
    out = StringIO.new
    err = StringIO.new
    status = described_class.start(
      arguments,
      out:,
      err:,
      input:,
      workspace_loader:,
      connection_loader:,
      command_runner:
    )

    [status, out.string, err.string]
  end

  def loader_for(workspace)
    ->(**_options) { workspace }
  end

  def discovered_account
    AnalyticsOps::Resources::Account.new(
      id: "100000001",
      name: "accounts/100000001",
      display_name: "Example account",
      properties: [property.to_h]
    )
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

  it "discovers properties before a configuration or workspace exists" do
    connection = instance_double(AnalyticsOps::Connection, properties: [discovered_account])
    workspace_loader = ->(**_options) { raise "workspace must not load" }

    status, output, error = run(
      "properties",
      connection_loader: loader_for(connection),
      workspace_loader:
    )

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("Example account", "Example property", "123456789")
    expect(output).not_to include("Stream")
    expect(error).to be_empty
  end

  it "keeps detailed discover configuration-free" do
    account = AnalyticsOps::Resources::Account.new(
      id: "100000001",
      name: "accounts/100000001",
      display_name: "Example account",
      properties: [property.to_h.merge("streams" => [stream.to_h])]
    )
    connection = instance_double(AnalyticsOps::Connection, discover: [account])
    workspace_loader = ->(**_options) { raise "workspace must not load" }

    status, output, error = run(
      "discover",
      connection_loader: loader_for(connection),
      workspace_loader:
    )

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("Property 123456789", "Stream 987654321")
    expect(error).to be_empty
  end

  it "sets up a selected property and writes valid production configuration" do
    connection = instance_double(AnalyticsOps::Connection, properties: [discovered_account])
    verification = AnalyticsOps::Connection::Verification.new(property:)
    allow(connection).to receive(:verify).with("123456789").and_return(verification)

    Dir.mktmpdir("analytics-ops-cli") do |directory|
      path = File.join(directory, "config", "analytics_ops.yml")
      status, output, error = run(
        "setup", "--property", "123456789", "--config", path,
        connection_loader: loader_for(connection)
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(output).to include("Connected production", "Next: analytics-ops overview")
      expect(error).to be_empty
      expect(AnalyticsOps::Configuration.load(path).profile("production").property_id).to eq("123456789")
    end
  end

  it "shows account context and accepts a numbered property choice" do
    first = property(id: "111111111").to_h.merge("display_name" => "Alpha property")
    account = AnalyticsOps::Resources::Account.new(
      id: "100000001",
      name: "accounts/100000001",
      display_name: "Example account",
      properties: [first, property.to_h]
    )
    connection = instance_double(AnalyticsOps::Connection, properties: [account])
    allow(connection).to receive(:verify)
      .with("123456789")
      .and_return(AnalyticsOps::Connection::Verification.new(property:))

    Dir.mktmpdir("analytics-ops-cli") do |directory|
      status, output, error = run(
        "setup", "--config", File.join(directory, "analytics_ops.yml"),
        connection_loader: loader_for(connection), input: StringIO.new("2\n")
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(output).to include("Choose a Google Analytics property", "Example account", "Property number:")
      expect(error).to be_empty
    end
  end

  it "runs official gcloud authentication once and retries setup" do
    connection = instance_double(AnalyticsOps::Connection)
    calls = 0
    allow(connection).to receive(:properties) do
      calls += 1
      raise AnalyticsOps::AuthenticationError, "credentials unavailable" if calls == 1

      [discovered_account]
    end
    allow(connection).to receive(:verify)
      .with("123456789")
      .and_return(AnalyticsOps::Connection::Verification.new(property:))
    runner = double("CommandRunner", available?: true, run: true)

    Dir.mktmpdir("analytics-ops-cli") do |directory|
      client_id_file = File.join(directory, "desktop-oauth.json")
      File.write(client_id_file, "{}")
      status, output, error = run(
        "setup", "--property", "123456789", "--config", File.join(directory, "analytics_ops.yml"),
        "--client-id-file", client_id_file, "--no-launch-browser",
        connection_loader: loader_for(connection), command_runner: runner
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(output).to include("official gcloud ADC command", "replace the local ADC credentials")
      expect(error).to be_empty
      expect(runner).to have_received(:run) do |arguments, **_streams|
        expect(arguments).to include(
          "gcloud",
          "--client-id-file=#{client_id_file}",
          "--no-launch-browser",
          a_string_including("analytics.readonly")
        )
      end
    end
  end

  it "does not invoke login during non-interactive setup" do
    connection = instance_double(AnalyticsOps::Connection)
    allow(connection).to receive(:properties).and_raise(AnalyticsOps::AuthenticationError, "credentials unavailable")
    runner = double("CommandRunner")
    allow(runner).to receive(:available?)
    allow(runner).to receive(:run)

    status, output, error = run(
      "setup", "--property", "123456789", "--non-interactive",
      connection_loader: loader_for(connection), command_runner: runner
    )

    expect(status).to eq(described_class::AUTHENTICATION_ERROR)
    expect(output).to be_empty
    expect(error).to include("gcloud auth application-default login")
    expect(runner).not_to have_received(:available?)
    expect(runner).not_to have_received(:run)
  end

  it "returns the existing unsupported status when gcloud is unavailable" do
    connection = instance_double(AnalyticsOps::Connection)
    allow(connection).to receive(:properties).and_raise(AnalyticsOps::AuthenticationError, "credentials unavailable")
    runner = double("CommandRunner", available?: false)

    status, output, error = run(
      "setup", "--property", "123456789",
      connection_loader: loader_for(connection), command_runner: runner
    )

    expect(status).to eq(described_class::UNSUPPORTED)
    expect(output).to be_empty
    expect(error).to include("Google Cloud CLI is required")
  end

  it "explains the owned-client and headless fallbacks when Google login fails" do
    connection = instance_double(AnalyticsOps::Connection)
    allow(connection).to receive(:properties).and_raise(AnalyticsOps::AuthenticationError, "credentials unavailable")
    runner = double("CommandRunner", available?: true, run: false)

    status, output, error = run(
      "setup", "--property", "123456789",
      connection_loader: loader_for(connection), command_runner: runner
    )

    expect(status).to eq(described_class::AUTHENTICATION_ERROR)
    expect(output).to include("Google login is required")
    expect(error).to include("--client-id-file PATH", "--no-launch-browser")
  end

  it "returns the existing remote status with an actionable disabled-API command" do
    connection = instance_double(AnalyticsOps::Connection)
    allow(connection).to receive(:properties)
      .and_raise(AnalyticsOps::RemoteError, "SERVICE_DISABLED: API has not been used")

    status, output, error = run(
      "setup", "--property", "123456789",
      connection_loader: loader_for(connection)
    )

    expect(status).to eq(described_class::REMOTE_ERROR)
    expect(output).to be_empty
    expect(error).to include("gcloud services enable", "analyticsadmin.googleapis.com", "analyticsdata.googleapis.com")
  end

  it "renders report results as human, JSON, and safe CSV output" do
    workspace = double("Workspace", report: report_result)
    loader = loader_for(workspace)

    human_status, human, = run("report", "calculator_completions", workspace_loader: loader)
    json_status, json, = run("report", "calculator_completions", "--format", "json", workspace_loader: loader)
    csv_status, csv, = run("report", "calculator_completions", "--csv", workspace_loader: loader)

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

  it "renders a batched overview in human and JSON formats" do
    reports = AnalyticsOps::Reports::Catalog.overview.map do |definition|
      AnalyticsOps::Reports::Result.new(
        name: definition.name,
        kind: "standard",
        dimension_headers: definition.dimensions,
        metric_headers: definition.metrics,
        rows: [],
        row_count: 0,
        metadata: {}
      )
    end
    overview = AnalyticsOps::Reports::OverviewResult.new(property_id: "123456789", reports:)
    workspace = double("Workspace", overview:)

    human_status, human, = run("overview", workspace_loader: loader_for(workspace))
    json_status, json, = run("overview", "--json", workspace_loader: loader_for(workspace))

    expect([human_status, json_status]).to all(eq(described_class::SUCCESS))
    expect(human).to include("Overview for property 123456789", "Traffic acquisition")
    expect(JSON.parse(json).fetch("reports").length).to eq(5)
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
