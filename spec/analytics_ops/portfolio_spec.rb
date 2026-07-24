# frozen_string_literal: true

require "tmpdir"

RSpec.describe AnalyticsOps::Portfolio do
  def totals_result(profile, compared: false)
    dimensions = compared ? ["dateRange"] : []
    row = {
      "activeUsers" => profile == "client_b" ? "8" : "12",
      "sessions" => profile == "client_b" ? "10" : "15",
      "keyEvents" => profile == "client_b" ? "2" : "3"
    }
    row["dateRange"] = "current" if compared
    AnalyticsOps::Reports::Result.new(
      name: "overview_totals",
      kind: "standard",
      dimension_headers: dimensions,
      metric_headers: %w[activeUsers sessions keyEvents],
      rows: [row],
      row_count: 1,
      metadata: {}
    )
  end

  it "summarizes every configured profile through its own saved connection" do
    Dir.mktmpdir("analytics-ops-portfolio") do |directory|
      config = File.join(directory, "analytics_ops.yml")
      File.write(config, <<~YAML)
        version: 1
        profiles:
          production:
            property_id: "123456789"
          client_b:
            property_id: "987654321"
      YAML
      saved_store = instance_double(AnalyticsOps::ServiceAccount::Store)
      credential_loader = double("CredentialLoader")
      workspaces = {}
      service_accounts = {}
      %w[client_b production].each do |profile|
        service_account = instance_double(AnalyticsOps::ServiceAccount)
        service_accounts[profile] = service_account
        allow(credential_loader).to receive(:call)
          .with(store: saved_store, connection: nil, config:, profile:)
          .and_return(service_account)
        workspaces[profile] = double("Workspace")
        allow(workspaces.fetch(profile)).to receive(:report).and_return(totals_result(profile))
      end
      expected_config = config
      workspace_loader = lambda do |config:, profile:, service_account:, transport:, timeout:, logger:|
        expect(config).to eq(expected_config)
        expect(service_account).to equal(service_accounts.fetch(profile))
        expect([transport, timeout, logger]).to eq([:grpc, nil, nil])
        workspaces.fetch(profile)
      end
      portfolio = described_class.new(
        config:,
        store: saved_store,
        service_account_loader: credential_loader,
        workspace_loader:
      )

      result = portfolio.overview

      expect(result.entries.map(&:profile)).to eq(%w[client_b production])
      expect(result.entries.map(&:property_id)).to eq(%w[987654321 123456789])
      expect(result.entries.map(&:active_users)).to eq(%w[8 12])
      expect(result).to be_frozen
      expect(result.entries).to be_frozen
    end
  end

  it "preserves the current/previous labels returned for comparisons" do
    desired = build_desired_state
    service_account = instance_double(AnalyticsOps::ServiceAccount)
    workspace = double("Workspace", report: totals_result("production", compared: true))
    document = AnalyticsOps::Configuration::Document.new(
      version: 1,
      profiles: { "production" => desired }
    )
    allow(AnalyticsOps::Configuration).to receive(:load).and_return(document)
    portfolio = described_class.new(
      config: "/tmp/obviously-fake-analytics-ops.yml",
      service_account_loader: ->(**) { service_account },
      workspace_loader: ->(**) { workspace }
    )
    ranges = AnalyticsOps::Reports::Period.resolve(last_days: 7, compare: true)

    result = portfolio.overview(date_ranges: ranges)

    expect(result.entries.first.period).to eq("current")
    expect(result.date_ranges).to eq(ranges)
    expect(workspace).to have_received(:report).with(
      an_object_having_attributes(date_ranges: ranges)
    )
  end
end
