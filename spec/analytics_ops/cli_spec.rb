# frozen_string_literal: true

# CLI integration coverage.

require "stringio"
require "tempfile"
require "tmpdir"
require "analytics_ops/cli"

RSpec.describe AnalyticsOps::CLI do
  def run(*arguments, workspace_loader: nil, connection_loader: nil, service_account_loader: nil,
          service_account_store: nil, mcp_server_loader: nil, portfolio_loader: nil, input: StringIO.new)
    out = StringIO.new
    err = StringIO.new
    service_account = instance_double(
      AnalyticsOps::ServiceAccount,
      path: "/tmp/obviously-fake-service-account.json"
    )
    service_account_loader ||= ->(**_options) { service_account }
    service_account_store ||= double("ServiceAccountStore", write: nil, selected_profile: nil)
    status = described_class.start(
      arguments,
      out:,
      err:,
      input:,
      workspace_loader:,
      connection_loader:,
      service_account_loader:,
      service_account_store:,
      mcp_server_loader:,
      portfolio_loader:
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
    expect(out).to include("Google Analytics 4 configuration as code", "--service-account PATH")
    expect(out).not_to include("--client-id-file", "--no-launch-browser")
    expect(err).to be_empty
  end

  it "prints the installed version" do
    status, out, err = run("version")

    expect(status).to eq(AnalyticsOps::CLI::SUCCESS)
    expect(out).to eq("#{AnalyticsOps::VERSION}\n")
    expect(err).to be_empty
  end

  it "starts the read-only MCP protocol without writing non-protocol output" do
    mcp_server = double("MCPServer", start: nil)
    mcp_server_loader = double("MCPServerLoader", call: mcp_server)

    status, output, error = run("mcp", mcp_server_loader:)

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to be_empty
    expect(error).to be_empty
    expect(mcp_server).to have_received(:start).once
    expect(mcp_server_loader).to have_received(:call).with(
      config: "config/analytics_ops.yml",
      profile: "production",
      connection: nil,
      store: kind_of(Object),
      workspace_loader: kind_of(Method),
      connection_loader: kind_of(Method),
      service_account_loader: kind_of(Proc),
      portfolio_loader: kind_of(Method),
      transport: :grpc,
      timeout: nil,
      logger: an_instance_of(Logger)
    )
  end

  it "rejects output formats for the MCP protocol" do
    status, output, error = run("mcp", "--json")

    expect(status).to eq(described_class::USAGE_ERROR)
    expect(output).to be_empty
    expect(JSON.parse(error).dig("error", "message")).to include("does not accept output formats")
  end

  it "rejects extra arguments for help and version" do
    expect(run("help", "extra").first).to eq(described_class::USAGE_ERROR)
    expect(run("version", "extra").first).to eq(described_class::USAGE_ERROR)
  end

  it "returns a stable usage status for an unknown command" do
    status, out, err = run("unknown")

    expect(status).to eq(AnalyticsOps::CLI::USAGE_ERROR)
    expect(out).to be_empty
    expect(err).to include("Unknown command: unknown")
  end

  it "returns structured JSON for an unknown command when requested" do
    status, output, error = run("unknown", "--json")

    expect(status).to eq(AnalyticsOps::CLI::USAGE_ERROR)
    expect(output).to be_empty
    expect(JSON.parse(error).dig("error", "message")).to include("Unknown command: unknown")
  end

  it "keeps JSON errors structured even when an earlier option is invalid" do
    status, output, error = run("report", "example", "--not-an-option", "--json")

    expect(status).to eq(AnalyticsOps::CLI::USAGE_ERROR)
    expect(output).to be_empty
    expect(JSON.parse(error).dig("error", "type")).to eq("InvalidOption")
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

  it "includes the saved connection name in successful JSON setup output" do
    connection = instance_double(AnalyticsOps::Connection, properties: [discovered_account])
    allow(connection).to receive(:verify)
      .with("123456789")
      .and_return(AnalyticsOps::Connection::Verification.new(property:))

    Dir.mktmpdir("analytics-ops-cli") do |directory|
      status, output, error = run(
        "setup", "--property", "123456789", "--non-interactive", "--json",
        "--config", File.join(directory, "analytics_ops.yml"),
        connection_loader: loader_for(connection)
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(JSON.parse(output).fetch("connection")).to eq("production")
      expect(error).to be_empty
    end
  end

  it "lists saved connections without loading Google or a workspace" do
    store = double(
      "ServiceAccountStore",
      summaries: [
        { "name" => "primary", "available" => true, "in_use" => true },
        { "name" => "client_b", "available" => false, "in_use" => false }
      ]
    )
    loader = ->(**_options) { raise "Google credentials must not load" }

    status, output, error = run(
      "connections",
      service_account_store: store,
      service_account_loader: loader,
      workspace_loader: ->(**_options) { raise "workspace must not load" }
    )

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("primary: ready · in use", "client_b: key unavailable")
    expect(error).to be_empty
  end

  it "lists and switches configured profiles without contacting Google" do
    Dir.mktmpdir("analytics-ops-cli") do |directory|
      config = File.join(directory, "analytics_ops.yml")
      File.write(config, <<~YAML)
        version: 1
        profiles:
          production:
            property_id: "123456789"
          client_b:
            property_id: "987654321"
      YAML
      store = double("ServiceAccountStore")
      allow(store).to receive(:selection).with(config:).and_return(
        "profile" => "production", "connection" => "primary"
      )
      allow(store).to receive(:profile_connection) do |profile:, **|
        profile == "production" ? "primary" : "client_b"
      end
      allow(store).to receive(:select)
        .with(config:, profile: "client_b", connection: nil)
        .and_return("profile" => "client_b", "connection" => "client_b")

      list_status, list_output, list_error = run(
        "profiles", "--config", config, service_account_store: store
      )
      use_status, use_output, use_error = run(
        "use", "client_b", "--config", config, service_account_store: store
      )

      expect([list_status, use_status]).to all(eq(described_class::SUCCESS))
      expect(list_output).to include("* production", "client_b", "connection client_b")
      expect(use_output).to include("Using profile client_b with connection client_b")
      expect([list_error, use_error]).to all(be_empty)
    end
  end

  it "uses the locally selected profile and connection automatically" do
    store = double("ServiceAccountStore", selected_profile: "client_b")
    service_account = instance_double(AnalyticsOps::ServiceAccount)
    credential_loader = double("ServiceAccountLoader", call: service_account)
    overview = AnalyticsOps::Reports::OverviewResult.new(property_id: "987654321", reports: [report_result])
    workspace = double("Workspace", overview:)
    workspace_loader = double("WorkspaceLoader", call: workspace)

    status, = run(
      "overview",
      service_account_store: store,
      service_account_loader: credential_loader,
      workspace_loader:
    )

    expect(status).to eq(described_class::SUCCESS)
    expect(credential_loader).to have_received(:call).with(
      path: nil,
      store:,
      connection: nil,
      config: "config/analytics_ops.yml",
      profile: "client_b"
    )
    expect(workspace_loader).to have_received(:call).with(
      config: "config/analytics_ops.yml",
      profile: "client_b",
      service_account:,
      transport: :grpc,
      timeout: nil,
      logger: an_instance_of(Logger)
    )
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

  it "loads and remembers an explicit service account only after successful setup" do
    connection = instance_double(AnalyticsOps::Connection, properties: [discovered_account])
    allow(connection).to receive(:verify)
      .with("123456789")
      .and_return(AnalyticsOps::Connection::Verification.new(property:))

    Dir.mktmpdir("analytics-ops-cli") do |directory|
      key_path = File.join(directory, "service-account.json")
      File.write(key_path, "{}")
      service_account = instance_double(AnalyticsOps::ServiceAccount, path: key_path)
      loader = double("ServiceAccountLoader", call: service_account)
      store = double("ServiceAccountStore", write: nil, selected_profile: nil)
      status, output, error = run(
        "setup", "--property", "123456789", "--config", File.join(directory, "analytics_ops.yml"),
        "--service-account", key_path,
        connection_loader: loader_for(connection),
        service_account_loader: loader,
        service_account_store: store
      )

      expect(status).to eq(described_class::SUCCESS)
      expect(output).to include("Connected production", "Next: analytics-ops overview")
      expect(error).to be_empty
      expect(loader).to have_received(:call).with(
        path: key_path,
        store:,
        connection: nil,
        config: File.join(directory, "analytics_ops.yml"),
        profile: "production"
      )
      expect(store).to have_received(:write).with(
        key_path,
        name: "production",
        config: File.join(directory, "analytics_ops.yml"),
        profile: "production"
      ).once
    end
  end

  it "returns authentication status when no service account has been configured" do
    loader = double("ServiceAccountLoader")
    allow(loader).to receive(:call).and_raise(
      AnalyticsOps::AuthenticationError,
      "No service account is configured; run analytics-ops setup --service-account PATH"
    )

    status, output, error = run(
      "setup", "--property", "123456789", "--non-interactive",
      service_account_loader: loader
    )

    expect(status).to eq(described_class::AUTHENTICATION_ERROR)
    expect(output).to be_empty
    expect(error).to include("No service account is configured", "setup --service-account")
  end

  it "rejects removed OAuth and gcloud setup options" do
    client_status, = run("setup", "--client-id-file", "/tmp/desktop.json")
    browser_status, = run("setup", "--no-launch-browser")

    expect(client_status).to eq(described_class::USAGE_ERROR)
    expect(browser_status).to eq(described_class::USAGE_ERROR)
  end

  it "does not remember a service account when property verification fails" do
    connection = instance_double(AnalyticsOps::Connection, properties: [discovered_account])
    allow(connection).to receive(:verify).and_raise(AnalyticsOps::AuthorizationError, "Property access denied")
    store = double("ServiceAccountStore", selected_profile: nil)
    allow(store).to receive(:write)

    status, output, error = run(
      "setup", "--property", "123456789",
      connection_loader: loader_for(connection),
      service_account_store: store
    )

    expect(status).to eq(described_class::AUTHORIZATION_ERROR)
    expect(output).to be_empty
    expect(error).to include("Property access denied")
    expect(store).not_to have_received(:write)
  end

  it "handles Ctrl-C without a Ruby backtrace in human or JSON output" do
    connection = instance_double(AnalyticsOps::Connection)
    allow(connection).to receive(:properties).and_raise(Interrupt)
    loader = loader_for(connection)

    human_status, human_output, human_error = run(
      "setup", "--property", "123456789", connection_loader: loader
    )
    json_status, json_output, json_error = run(
      "setup", "--property", "123456789", "--non-interactive", "--json", connection_loader: loader
    )

    expect([human_status, json_status]).to all(eq(described_class::INTERRUPTED))
    expect([human_output, json_output]).to all(be_empty)
    expect(human_error).to eq("Interrupt: Interrupted by user\n")
    expect(JSON.parse(json_error).fetch("error")).to eq(
      "message" => "Interrupted by user",
      "type" => "Interrupt"
    )
  end

  it "returns the existing remote status with an actionable disabled-API command" do
    connection = instance_double(AnalyticsOps::Connection)
    allow(connection).to receive(:properties)
      .and_raise(
        AnalyticsOps::RemoteError.new(
          "Google rejected the request",
          remote_reason: "SERVICE_DISABLED",
          remote_metadata: { "service" => "analyticsdata.googleapis.com" }
        )
      )

    status, output, error = run(
      "setup", "--property", "123456789",
      connection_loader: loader_for(connection)
    )

    expect(status).to eq(described_class::REMOTE_ERROR)
    expect(output).to be_empty
    expect(error).to include(
      "Google Analytics Admin API",
      "Google Analytics Data API",
      "service account"
    )
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

  it "visibly shortens long human report cells while preserving distinguishing endings" do
    prefix = "https://example.test/#{"a" * 70}"
    result = AnalyticsOps::Reports::Result.new(
      name: "landing_pages",
      kind: "standard",
      dimension_headers: ["landingPage"],
      metric_headers: ["sessions"],
      rows: [
        { "landingPage" => "#{prefix}/first-ending", "sessions" => "1" },
        { "landingPage" => "#{prefix}/second-ending", "sessions" => "1" }
      ],
      row_count: 2,
      metadata: {}
    )
    workspace = double("Workspace", report: result)

    status, output, error = run("report", "landing-pages", workspace_loader: loader_for(workspace))

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("…", "first-ending", "second-ending")
    expect(error).to be_empty
  end

  it "neutralizes formula cells hidden behind whitespace in CSV" do
    result = AnalyticsOps::Reports::Result.new(
      name: "example",
      kind: "standard",
      dimension_headers: ["eventName"],
      metric_headers: ["eventCount"],
      rows: [
        { "eventName" => "  =1+1", "eventCount" => "1" },
        { "eventName" => "\t@SUM(1,1)", "eventCount" => "2" },
        { "eventName" => "\u00a0+1", "eventCount" => "3" },
        { "eventName" => "safe\e[31mvalue", "eventCount" => "4" }
      ],
      row_count: 4,
      metadata: {}
    )
    workspace = double("Workspace", report: result)

    status, output, error = run("report", "example", "--csv", workspace_loader: loader_for(workspace))

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("'  =1+1", "'\t@SUM(1,1)", "'\u00a0+1")
    expect(output).not_to include("\e")
    expect(error).to be_empty
  end

  it "removes terminal controls from human discovery and report output" do
    unsafe_account = AnalyticsOps::Resources::Account.new(
      id: "100000001",
      name: "accounts/100000001",
      display_name: "Example\e[31m\nforged",
      properties: [property.to_h]
    )
    connection = instance_double(AnalyticsOps::Connection, properties: [unsafe_account])
    unsafe_result = AnalyticsOps::Reports::Result.new(
      name: "example",
      kind: "standard",
      dimension_headers: ["eventName"],
      metric_headers: ["eventCount"],
      rows: [{ "eventName" => "value\e[2J\nforged", "eventCount" => "1" }],
      row_count: 1,
      metadata: {}
    )
    workspace = double("Workspace", report: unsafe_result)

    _, properties_output, = run("properties", connection_loader: loader_for(connection))
    _, report_output, = run("report", "example", workspace_loader: loader_for(workspace))

    expect(properties_output).not_to include("\e", "\nforged")
    expect(report_output).not_to include("\e", "\nforged")
  end

  it "removes terminal controls from human snapshots" do
    unsafe_property = AnalyticsOps::Resources::Property.new(
      id: "123456789",
      name: "properties/123456789",
      display_name: "Example\e[2J\nforged",
      parent: "accounts/100000001",
      property_type: "ordinary",
      can_edit: true
    )
    workspace = double("Workspace", snapshot: snapshot(property: unsafe_property))

    status, output, error = run("snapshot", workspace_loader: loader_for(workspace))

    expect(status).to eq(described_class::SUCCESS)
    expect(output).not_to include("\e", "\nforged")
    expect(error).to be_empty
  end

  it "rejects conflicting output format options" do
    status, output, error = run("report", "example", "--json", "--csv")

    expect(status).to eq(described_class::USAGE_ERROR)
    expect(output).to be_empty
    expect(error).to include("output format")
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

  it "supports simple custom dates and equal preceding-period comparisons" do
    workspace = double("Workspace", report: report_result)
    ranges = [
      { "start_date" => "7daysAgo", "end_date" => "yesterday", "name" => "current" },
      { "start_date" => "14daysAgo", "end_date" => "8daysAgo", "name" => "previous" }
    ]

    status, = run(
      "report", "traffic", "--last", "7", "--compare",
      workspace_loader: loader_for(workspace)
    )

    expect(status).to eq(described_class::SUCCESS)
    expect(workspace).to have_received(:report).with("traffic", date_ranges: ranges)
  end

  it "validates report dates as usage errors" do
    expect(run("report", "traffic", "--from", "2026-07-01").first).to eq(described_class::USAGE_ERROR)
    expect(run("realtime", "--last", "7").first).to eq(described_class::USAGE_ERROR)
    expect(run("overview", "--last", "0").first).to eq(described_class::USAGE_ERROR)
  end

  it "renders a read-only multi-property portfolio" do
    result = AnalyticsOps::Portfolio::Result.new(
      entries: [
        AnalyticsOps::Portfolio::Entry.new(
          profile: "production",
          property_id: "123456789",
          period: "current",
          active_users: "12",
          sessions: "15",
          key_events: "3"
        )
      ],
      date_ranges: [{ "start_date" => "28daysAgo", "end_date" => "yesterday" }]
    )
    portfolio = double("Portfolio", overview: result)

    status, output, error = run("portfolio", portfolio_loader: ->(**) { portfolio })

    expect(status).to eq(described_class::SUCCESS)
    expect(output).to include("Portfolio overview", "production", "123456789", "15")
    expect(error).to be_empty
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
    expect(run("doctor", "--timeout", "Infinity").first).to eq(described_class::USAGE_ERROR)
    expect(run("doctor", "--service-account", __FILE__).first).to eq(described_class::USAGE_ERROR)
    expect(run("portfolio", "--connection", "primary").first).to eq(described_class::USAGE_ERROR)
    expect(run("profiles", "--profile", "production").first).to eq(described_class::USAGE_ERROR)
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

  it "shows the complete saved value before interactive confirmation" do
    ending = "VISIBLE-END"
    long_uri = "https://example.com/#{"a" * 1_100}#{ending}"
    desired = build_desired_state(
      streams: [
        {
          "name" => "web",
          "stream_id" => "987654321",
          "default_uri" => long_uri,
          "enhanced_measurement" => nil
        }
      ]
    )
    plan = AnalyticsOps::Planner.new(desired_state: desired, snapshot: snapshot).call
    workspace = double("Workspace")
    Tempfile.create(["analytics-ops-plan", ".json"]) do |file|
      plan.write(file.path)
      status, output, error = run(
        "apply", file.path, workspace_loader: loader_for(workspace), input: StringIO.new("no\n")
      )

      expect(status).to eq(described_class::USAGE_ERROR)
      expect(output).to include(ending)
      expect(error).to include("Apply was not confirmed")
    end
  end

  it "requires explicit non-interactive approval before JSON apply" do
    plan = AnalyticsOps::Planner.new(desired_state: build_desired_state, snapshot: snapshot).call
    input = double("Input")
    allow(input).to receive(:gets)
    Tempfile.create(["analytics-ops-plan", ".json"]) do |file|
      plan.write(file.path)
      status, output, error = run(
        "apply", file.path, "--json", workspace_loader: loader_for(double("Workspace")), input:
      )

      expect(status).to eq(described_class::USAGE_ERROR)
      expect(output).to be_empty
      expect(JSON.parse(error).dig("error", "message")).to include(
        "JSON apply requires --non-interactive --yes"
      )
      expect(input).not_to have_received(:gets)
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
