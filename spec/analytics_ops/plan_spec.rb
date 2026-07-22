# frozen_string_literal: true

require "tempfile"

RSpec.describe AnalyticsOps::Plan do
  def plan_hash
    AnalyticsOps::Planner.new(desired_state: build_desired_state, snapshot: snapshot).call.to_h
  end

  def copy(value)
    Marshal.load(Marshal.dump(value))
  end

  it "strictly validates every top-level scalar type" do
    {
      "format_version" => "1",
      "profile" => 1,
      "property_id" => 123_456_789,
      "snapshot_fingerprint" => nil
    }.each do |field, invalid|
      raw = copy(plan_hash)
      raw[field] = invalid

      expect { described_class.from_h(raw) }.to raise_error(AnalyticsOps::InvalidPlanError)
    end
  end

  it "rejects unknown and secret-shaped resource fields" do
    unknown = copy(plan_hash)
    unknown.fetch("changes").first.fetch("after")["surprise"] = true
    secret = copy(plan_hash)
    secret.fetch("changes").first.fetch("after")["access_token"] = "forbidden"

    expect { described_class.from_h(unknown) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /Unknown .* field surprise/)
    expect { described_class.from_h(secret) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /Secret-shaped plan field/)
  end

  it "rejects control characters in all user-visible fields" do
    raw = copy(plan_hash)
    raw.fetch("changes").first["rollback"] = "unsafe\nrollback"

    expect { described_class.from_h(raw) }.to raise_error(AnalyticsOps::InvalidPlanError, /rollback/)

    raw = copy(plan_hash)
    raw.fetch("findings").first["message"] = "unsafe\u0000message"

    expect { described_class.from_h(raw) }.to raise_error(AnalyticsOps::InvalidPlanError, /message/)
  end

  it "rejects credential-shaped text in saved plans" do
    raw = copy(plan_hash)
    raw.fetch("changes").first["rollback"] = "Bearer never-print-this"

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /rollback/)
  end

  it "rejects resource identities that do not match their payload" do
    raw = copy(plan_hash)
    raw.fetch("changes").first["resource_identity"] = "stream:000000001"

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /resource_identity does not match/)
  end

  it "rejects resource names targeting another property" do
    raw = copy(plan_hash)
    change = raw.fetch("changes").find { |value| value.fetch("resource_type") == "data_stream" }
    change.fetch("before")["name"] = "properties/999999999/dataStreams/987654321"
    change.fetch("after")["name"] = "properties/999999999/dataStreams/987654321"

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /different property/)
  end

  it "rejects forged changes to immutable resource fields" do
    raw = copy(plan_hash)
    change = raw.fetch("changes").find { |value| value.fetch("resource_type") == "custom_dimension" }
    change.fetch("after")["scope"] = "user"
    change["resource_identity"] = "user:calculator_slug"

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /immutable field scope/)
  end

  it "enforces the shorter Google limit for user-scoped dimension parameters" do
    raw = copy(plan_hash)
    raw["changes"] = [{
      "resource_type" => "custom_dimension",
      "resource_identity" => "user:#{"a" * 25}",
      "operation" => "create",
      "api_maturity" => "beta",
      "before" => nil,
      "after" => {
        "parameter_name" => "a" * 25,
        "display_name" => "User dimension",
        "description" => "",
        "scope" => "user",
        "disallow_ads_personalization" => false
      },
      "reversible" => true,
      "rollback" => "Archive the custom dimension"
    }]

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /parameter_name/)
  end

  it "rejects data-stream changes that the planner cannot safely generate" do
    non_web = copy(plan_hash)
    change = non_web.fetch("changes").find { |value| value.fetch("resource_type") == "data_stream" }
    change.fetch("before")["type"] = "android"
    change.fetch("after")["type"] = "android"

    expect { described_class.from_h(non_web) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /type/)

    missing_uri = copy(plan_hash)
    change = missing_uri.fetch("changes").find { |value| value.fetch("resource_type") == "data_stream" }
    change.fetch("after")["default_uri"] = nil

    expect { described_class.from_h(missing_uri) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /default_uri/)
  end

  it "rejects event-only retention durations for user data" do
    raw = copy(plan_hash)
    change = raw.fetch("changes").find { |value| value.fetch("resource_type") == "retention" }
    change.fetch("after")["user_data"] = "26_months"

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /user_data/)
  end

  it "allows ads-personalization exclusion only for user-scoped dimensions" do
    raw = copy(plan_hash)
    raw["changes"] = [{
      "resource_type" => "custom_dimension",
      "resource_identity" => "event:category",
      "operation" => "create",
      "api_maturity" => "beta",
      "before" => nil,
      "after" => {
        "parameter_name" => "category",
        "display_name" => "Category",
        "description" => "",
        "scope" => "event",
        "disallow_ads_personalization" => true
      },
      "reversible" => true,
      "rollback" => "Archive the custom dimension"
    }]

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /only for user scope/)
  end

  it "requires currency metrics to declare their restricted-data classification" do
    raw = copy(plan_hash)
    raw["changes"] = [{
      "resource_type" => "custom_metric",
      "resource_identity" => "estimate_total",
      "operation" => "create",
      "api_maturity" => "beta",
      "before" => nil,
      "after" => {
        "parameter_name" => "estimate_total",
        "display_name" => "Estimate total",
        "description" => "",
        "scope" => "event",
        "measurement_unit" => "currency",
        "restricted_metric_types" => []
      },
      "reversible" => true,
      "rollback" => "Archive the custom metric"
    }]

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /required for a currency metric/)
  end

  it "rejects Google-invalid desired display names while accepting legacy names in before values" do
    raw = copy(plan_hash)
    change = raw.fetch("changes").find { |value| value.fetch("resource_type") == "custom_dimension" }
    change.fetch("before")["display_name"] = "Legacy [name]"
    change.fetch("after")["display_name"] = "New-name"

    expect { described_class.from_h(raw) }
      .to raise_error(AnalyticsOps::InvalidPlanError, /display_name/)

    change.fetch("after")["display_name"] = "New name"
    expect { described_class.from_h(raw) }.not_to raise_error
  end

  it "rejects unsafe operations and unsupported resource-operation pairs" do
    raw = copy(plan_hash)
    raw.fetch("changes").first["operation"] = "delete"
    expect { described_class.from_h(raw) }.to raise_error(AnalyticsOps::InvalidPlanError, /operation/)

    raw = copy(plan_hash)
    change = raw.fetch("changes").find { |value| value.fetch("resource_type") == "key_event" }
    change["operation"] = "update"
    change["before"] = copy(change.fetch("after"))
    expect { described_class.from_h(raw) }.to raise_error(AnalyticsOps::InvalidPlanError, /Unsupported update/)
  end

  it "rejects duplicate JSON object fields" do
    Tempfile.create(["forged-plan", ".json"]) do |file|
      file.write(
        '{"format_version":1,"format_version":1,"profile":"production",' \
        '"property_id":"123456789","snapshot_fingerprint":"sha256:' \
        "#{"0" * 64}\",\"changes\":[],\"findings\":[]}"
      )
      file.flush

      expect { described_class.load(file.path) }
        .to raise_error(AnalyticsOps::InvalidPlanError, /Duplicate JSON object field/)
    end
  end

  it "preserves deterministic bytes after strict validation" do
    original = described_class.from_h(plan_hash)
    round_trip = described_class.from_h(JSON.parse(original.to_json))

    expect(round_trip.to_json).to eq(original.to_json)
  end

  it "publishes a strict version-1 JSON Schema for saved plans" do
    path = File.expand_path("../../docs/plan-schema-v1.json", __dir__)
    schema = JSON.parse(File.read(path))

    expect(schema.fetch("additionalProperties")).to be(false)
    expect(schema.dig("properties", "format_version", "const")).to eq(1)
    expect(schema.dig("$defs", "change", "oneOf").length).to eq(7)
    expect(schema.dig("$defs", "change", "additionalProperties")).to be(false)
    expect(schema.dig("$defs", "dataStreamAfter", "properties", "type", "const")).to eq("web")
    expect(schema.dig("$defs", "customDimensionCreate", "allOf")).not_to be_empty
  end
end
