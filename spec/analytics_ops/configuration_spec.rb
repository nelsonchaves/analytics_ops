# frozen_string_literal: true

# Configuration contract coverage.

require "tempfile"
require "json"

RSpec.describe AnalyticsOps::Configuration do
  def load_yaml(source, environment: {})
    Tempfile.create(["analytics_ops", ".yml"]) do |file|
      file.write(source)
      file.flush
      return described_class.load(file.path, environment:)
    end
  end

  let(:valid_yaml) do
    <<~YAML
      version: 1
      profiles:
        production:
          property_id: "${PROPERTY_ID}"
          streams:
            web:
              stream_id: "987654321"
              default_uri: https://example.com
          retention:
            event_data: 14_months
            user_data: 14_months
            reset_on_new_activity: false
          key_events:
            - calculation_completed
          custom_dimensions:
            - parameter_name: calculator_slug
              display_name: Calculator slug
              description: Published calculator identifier
              scope: event
    YAML
  end

  it "loads a strict, immutable desired state without performing network I/O" do
    document = load_yaml(valid_yaml, environment: { "PROPERTY_ID" => "123456789" })
    profile = document.profile("production")

    expect(profile.property_id).to eq("123456789")
    expect(profile.streams.first.fetch("stream_id")).to eq("987654321")
    expect(profile).to be_frozen
    expect(profile.streams).to be_frozen
  end

  it "rejects unknown keys" do
    source = valid_yaml.sub("property_id:", "typo: true\n    property_id:")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Unknown configuration key/)
  end

  it "rejects numeric identifiers instead of silently coercing them" do
    source = valid_yaml.sub('"${PROPERTY_ID}"', "123456789")

    expect { load_yaml(source) }.to raise_error(AnalyticsOps::ConfigurationError, /must be a string/)
  end

  it "rejects missing environment variables" do
    expect { load_yaml(valid_yaml) }.to raise_error(AnalyticsOps::EnvironmentVariableError, /PROPERTY_ID/)
  end

  it "rejects YAML aliases and ERB" do
    expect { load_yaml("version: 1\nprofiles: &profiles {}\ncopy: *profiles\n") }
      .to raise_error(AnalyticsOps::ConfigurationError)
    expect { load_yaml("<%= ENV.fetch('PROPERTY_ID') %>") }
      .to raise_error(AnalyticsOps::ConfigurationError, /ERB/)
  end

  it "rejects secret-shaped configuration keys" do
    source = valid_yaml.sub("property_id:", "access_token: forbidden\n    property_id:")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Secret-shaped key/)
  end

  it "rejects compound secret-shaped keys and control characters" do
    secret = valid_yaml.sub("property_id:", "service_account_file: forbidden\n    property_id:")
    control = valid_yaml.sub("Published calculator identifier", '"bad\\u0000description"')

    expect { load_yaml(secret, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Secret-shaped key/)
    expect { load_yaml(control, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /printable/)
  end

  it "allows ads-personalization exclusion only on user-scoped dimensions" do
    source = valid_yaml.sub(
      "scope: event",
      "scope: event\n        disallow_ads_personalization: true"
    )

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /only for user scope/)
  end

  it "rejects duplicate key events and manual requirements" do
    duplicate_event = valid_yaml.sub(
      "      - calculation_completed",
      "      - calculation_completed\n      - calculation_completed"
    )
    duplicate_requirement = valid_yaml.sub(
      "    custom_dimensions:",
      "    manual_requirements:\n      - consent_mode_review\n      - consent_mode_review\n    custom_dimensions:"
    )

    expect { load_yaml(duplicate_event, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Duplicate value.*key_events/)
    expect { load_yaml(duplicate_requirement, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Duplicate value.*manual_requirements/)
  end

  it "keeps the published JSON Schema synchronized with the CLI schema" do
    path = File.expand_path("../../docs/configuration-schema-v1.json", __dir__)

    expect(JSON.parse(File.read(path))).to eq(AnalyticsOps::Configuration::SCHEMA)
  end
end
