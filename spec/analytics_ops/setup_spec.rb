# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe AnalyticsOps::Setup do
  def account_with(*properties)
    AnalyticsOps::Resources::Account.new(
      id: "100000001",
      name: "accounts/100000001",
      display_name: "Example account",
      properties: properties.map(&:to_h)
    )
  end

  it "selects the only accessible property and creates valid configuration" do
    connection = instance_double(
      AnalyticsOps::Connection,
      properties: [account_with(property)],
      verify: AnalyticsOps::Connection::Verification.new(property:)
    )

    Dir.mktmpdir("analytics-ops-setup") do |directory|
      path = File.join(directory, "config", "analytics_ops.yml")
      result = described_class.new(connection:, config: path, profile: "production").call

      expect(result).to be_created
      expect(result).to be_frozen
      expect(result.to_h).to include("status" => "configured", "profile" => "production")
      expect(AnalyticsOps::Configuration.load(path).profile("production").property_id).to eq("123456789")
      expect(connection).to have_received(:verify).with("123456789")
    end
  end

  it "accepts a numbered selection when several properties are available" do
    first = property(id: "111111111")
    connection = instance_double(
      AnalyticsOps::Connection,
      properties: [account_with(first, property)],
      verify: AnalyticsOps::Connection::Verification.new(property:)
    )
    output = StringIO.new

    Dir.mktmpdir("analytics-ops-setup") do |directory|
      described_class.new(
        connection:,
        config: File.join(directory, "analytics_ops.yml"),
        profile: "production",
        input: StringIO.new("2\n"),
        out: output
      ).call
    end

    expect(output.string).to include("Choose a Google Analytics property", "Example account")
    expect(connection).to have_received(:verify).with("123456789")
  end

  it "validates non-interactive input before contacting Google" do
    connection = instance_double(AnalyticsOps::Connection)

    expect do
      described_class.new(
        connection:,
        config: "config/analytics_ops.yml",
        profile: "production",
        noninteractive: true
      )
    end.to raise_error(AnalyticsOps::ConfigurationError, /requires a property ID/)
  end

  it "strictly validates boolean options and string property IDs" do
    connection = instance_double(AnalyticsOps::Connection)

    expect do
      described_class.new(
        connection:,
        config: "config/analytics_ops.yml",
        profile: "production",
        property_id: 123_456_789
      )
    end.to raise_error(AnalyticsOps::ConfigurationError, /numeric GA4 property ID/)
    expect do
      described_class.new(
        connection:,
        config: "config/analytics_ops.yml",
        profile: "production",
        noninteractive: "false"
      )
    end.to raise_error(AnalyticsOps::ConfigurationError, /true or false/)

    expect do
      described_class::Result.new(config_path: "config/analytics_ops.yml", profile: "production",
                                  property:, created: nil)
    end.to raise_error(ArgumentError, /distinct booleans/)
  end

  it "explains how to enable either API when property verification finds it disabled" do
    connection = instance_double(AnalyticsOps::Connection, properties: [account_with(property)])
    allow(connection).to receive(:verify)
      .and_raise(
        AnalyticsOps::RemoteError.new(
          "Google rejected the request",
          remote_reason: "SERVICE_DISABLED",
          remote_metadata: { "service" => "analyticsdata.googleapis.com" }
        )
      )

    expect do
      described_class.new(
        connection:,
        config: "config/analytics_ops.yml",
        profile: "production",
        property_id: "123456789"
      ).call
    end.to raise_error(
      AnalyticsOps::RemoteError,
      /Enable Google Analytics Admin API and Google Analytics Data API/
    )
  end

  it "does not guess API status by matching translated English message text" do
    connection = instance_double(AnalyticsOps::Connection, properties: [account_with(property)])
    original = AnalyticsOps::RemoteError.new("The API may be disabled, but no structured reason was provided")
    allow(connection).to receive(:verify).and_raise(original)

    expect do
      described_class.new(
        connection:,
        config: "config/analytics_ops.yml",
        profile: "production",
        property_id: "123456789"
      ).call
    end.to raise_error(AnalyticsOps::RemoteError, original.message)
  end
end
