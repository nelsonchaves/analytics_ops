# frozen_string_literal: true

require "json"
require "tmpdir"
require "analytics_ops/mcp_server"

RSpec.describe AnalyticsOps::MCPServer do
  def request(mcp_server, method, params = nil)
    message = { "jsonrpc" => "2.0", "id" => 1, "method" => method }
    message["params"] = params if params
    JSON.parse(mcp_server.server.handle_json(JSON.generate(message)))
  end

  def config_file
    Dir.mktmpdir("analytics-ops-mcp") do |directory|
      path = File.join(directory, "analytics_ops.yml")
      File.write(path, <<~YAML)
        version: 1
        profiles:
          production:
            property_id: "123456789"
      YAML
      yield path
    end
  end

  def store(profile: "production")
    instance_double(
      AnalyticsOps::ServiceAccount::Store,
      selection: { "profile" => profile, "connection" => "primary" },
      selected_profile: profile,
      profile_connection: "primary",
      summaries: [{ "name" => "primary", "available" => true, "in_use" => true }]
    )
  end

  it "exposes only explicitly annotated read-only tools" do
    server = described_class.new(store: store)
    tools = request(server, "tools/list").dig("result", "tools")
    names = tools.map { |tool| tool.fetch("name") }

    expect(names).to contain_exactly(
      "analytics_list_profiles",
      "analytics_list_connections",
      "analytics_list_properties",
      "analytics_doctor",
      "analytics_snapshot",
      "analytics_audit",
      "analytics_overview",
      "analytics_run_report",
      "analytics_portfolio",
      "analytics_realtime"
    )
    expect(names.join(" ")).not_to match(/\b(?:apply|create|delete|mutate|plan|update)\b/)
    expect(tools).to all(
      satisfy do |tool|
        tool.dig("annotations", "readOnlyHint") == true &&
          tool.dig("annotations", "destructiveHint") == false
      end
    )
  end

  it "does not load credentials, a workspace, or Google clients while starting" do
    credential_loader = ->(**) { raise "credentials must remain lazy" }
    workspace_loader = ->(**) { raise "workspace must remain lazy" }
    connection_loader = ->(**) { raise "connection must remain lazy" }

    server = described_class.new(
      store: store,
      service_account_loader: credential_loader,
      workspace_loader:,
      connection_loader:
    )

    expect(request(server, "tools/list").dig("result", "tools").length).to eq(10)
  end

  it "rejects unsafe local defaults before defining tools" do
    expect { described_class.new(config: "bad\npath", store: store) }
      .to raise_error(AnalyticsOps::ConfigurationError, /configuration path/)
    expect { described_class.new(profile: :production, store: store) }
      .to raise_error(AnalyticsOps::ConfigurationError, /profile/)
  end

  it "uses the selected profile and connection for a structured overview response" do
    config_file do |config|
      service_account = instance_double(AnalyticsOps::ServiceAccount)
      credential_loader = double("CredentialLoader", call: service_account)
      workspace = double("Workspace", overview: { "property_id" => "123456789", "reports" => [] })
      workspace_loader = double("WorkspaceLoader", call: workspace)
      saved_store = store
      server = described_class.new(
        config:,
        store: saved_store,
        service_account_loader: credential_loader,
        workspace_loader:
      )

      result = request(
        server,
        "tools/call",
        "name" => "analytics_overview",
        "arguments" => {}
      ).fetch("result")

      expect(result.fetch("isError", false)).to be(false)
      expect(result.fetch("structuredContent")).to eq(
        "property_id" => "123456789",
        "reports" => []
      )
      expect(credential_loader).to have_received(:call).with(
        store: saved_store,
        connection: nil,
        config:,
        profile: "production"
      )
      expect(workspace_loader).to have_received(:call).with(
        config:,
        profile: "production",
        service_account:,
        transport: :grpc,
        timeout: nil,
        logger: nil
      )
    end
  end

  it "returns safe structured tool errors without exposing secrets" do
    config_file do |config|
      workspace = double("Workspace")
      allow(workspace).to receive(:report)
        .and_raise(AnalyticsOps::RemoteError, "authorization=Bearer secret-token")
      server = described_class.new(
        config:,
        store: store,
        service_account_loader: ->(**) { instance_double(AnalyticsOps::ServiceAccount) },
        workspace_loader: ->(**) { workspace }
      )

      result = request(
        server,
        "tools/call",
        "name" => "analytics_run_report",
        "arguments" => { "report" => "traffic" }
      ).fetch("result")
      payload = result.fetch("structuredContent").fetch("error")

      expect(result.fetch("isError")).to be(true)
      expect(payload.fetch("type")).to eq("RemoteError")
      expect(payload.fetch("message")).to include("[REDACTED]")
      expect(JSON.generate(result)).not_to include("secret-token")
    end
  end

  it "passes bounded date comparisons to report tools" do
    config_file do |config|
      workspace = double("Workspace", report: { "rows" => [] })
      server = described_class.new(
        config:,
        store: store,
        service_account_loader: ->(**) { instance_double(AnalyticsOps::ServiceAccount) },
        workspace_loader: ->(**) { workspace }
      )

      result = request(
        server,
        "tools/call",
        "name" => "analytics_run_report",
        "arguments" => { "report" => "traffic", "last_days" => 7, "compare" => true }
      ).fetch("result")

      expect(result.fetch("isError", false)).to be(false)
      expect(workspace).to have_received(:report).with(
        "traffic",
        date_ranges: [
          { "start_date" => "7daysAgo", "end_date" => "yesterday", "name" => "current" },
          { "start_date" => "14daysAgo", "end_date" => "8daysAgo", "name" => "previous" }
        ]
      )
    end
  end

  it "returns a read-only summary across configured properties" do
    portfolio = double("Portfolio", overview: { "entries" => [{ "profile" => "production" }] })
    server = described_class.new(
      store: store,
      portfolio_loader: ->(**) { portfolio }
    )

    result = request(
      server,
      "tools/call",
      "name" => "analytics_portfolio",
      "arguments" => {}
    ).fetch("result")

    expect(result.fetch("isError", false)).to be(false)
    expect(result.dig("structuredContent", "entries", 0, "profile")).to eq("production")
    expect(portfolio).to have_received(:overview).once
  end

  it "rejects unknown arguments before any workspace is loaded" do
    workspace_loader = double("WorkspaceLoader", call: nil)
    server = described_class.new(store: store, workspace_loader:)

    response = request(
      server,
      "tools/call",
      "name" => "analytics_overview",
      "arguments" => { "unexpected" => true }
    )

    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content", 0, "text")).to include("Invalid arguments")
    expect(workspace_loader).not_to have_received(:call)
  end
end
