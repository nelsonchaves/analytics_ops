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

  it "rejects duplicate YAML mapping keys before Psych can discard them" do
    source = valid_yaml.sub(
      'property_id: "${PROPERTY_ID}"',
      "property_id: \"111111111\"\n    property_id: \"222222222\""
    )

    expect { load_yaml(source) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Duplicate YAML mapping key "property_id"/)
  end

  it "bounds YAML nesting before converting the parsed tree" do
    nested = "version: 1\nprofiles: {}\nextra:\n#{(1..60).map { |depth| "#{"  " * depth}-" }.join("\n")} value\n"

    expect { load_yaml(nested) }
      .to raise_error(AnalyticsOps::ConfigurationError, /nesting exceeds/)
  end

  it "rejects secret-shaped configuration keys" do
    source = valid_yaml.sub("property_id:", "access_token: forbidden\n    property_id:")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Secret-shaped key/)
  end

  it "rejects credential-shaped configuration values without echoing them" do
    source = valid_yaml.sub("Published calculator identifier", "access_token=never-print-this")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError) do |error|
        expect(error.message).to include("Credential-shaped value")
        expect(error.message).not_to include("never-print-this")
      end
  end

  it "rejects compound secret-shaped keys and control characters" do
    secret = valid_yaml.sub("property_id:", "service_account_file: forbidden\n    property_id:")
    control = valid_yaml.sub("Published calculator identifier", '"bad\\u0000description"')
    delete_control = valid_yaml.sub("Calculator slug", '"Calculator\\u007fslug"')

    expect { load_yaml(secret, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Secret-shaped key/)
    expect { load_yaml(control, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /printable/)
    expect { load_yaml(delete_control, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /display_name/)
  end

  it "validates Google-compatible custom-definition display names" do
    source = valid_yaml.sub("Calculator slug", "Calculator-slug")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /letters, numbers, spaces, or underscores/)
  end

  it "requires an explicit restricted-data classification for currency metrics" do
    metric = [
      "    custom_metrics:",
      "      - parameter_name: estimate_total",
      "        display_name: Estimate total",
      "        scope: event",
      "        measurement_unit: currency",
      ""
    ].join("\n")
    missing = valid_yaml.sub("    custom_dimensions:", "#{metric}    custom_dimensions:")
    classified = missing.sub(
      "        measurement_unit: currency",
      "        measurement_unit: currency\n        restricted_metric_types: [revenue_data]"
    )

    expect { load_yaml(missing, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /requires cost_data or revenue_data/)
    expect(load_yaml(classified, environment: { "PROPERTY_ID" => "123456789" })
      .profile("production").custom_metrics.first.fetch("restricted_metric_types")).to eq(["revenue_data"])
  end

  it "rejects event-only retention durations for user data" do
    source = valid_yaml.sub("user_data: 14_months", "user_data: 26_months")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /user_data must be one of: 2_months, 14_months/)
  end

  it "bounds configured stream URIs before planning" do
    source = valid_yaml.sub("https://example.com", "https://example.com/#{"a" * 2_100}")

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /absolute HTTP or HTTPS URI/)
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

  it "rejects two local stream names that target the same GA4 stream" do
    source = valid_yaml.sub(
      "        default_uri: https://example.com",
      [
        "        default_uri: https://example.com",
        "      duplicate:",
        "        stream_id: \"987654321\""
      ].join("\n")
    )

    expect { load_yaml(source, environment: { "PROPERTY_ID" => "123456789" }) }
      .to raise_error(AnalyticsOps::ConfigurationError, /Duplicate identity.*streams.*987654321/)
  end

  it "keeps the published JSON Schema synchronized with the CLI schema" do
    path = File.expand_path("../../docs/configuration-schema-v1.json", __dir__)

    expect(JSON.parse(File.read(path))).to eq(AnalyticsOps::Configuration::SCHEMA)
  end
end
