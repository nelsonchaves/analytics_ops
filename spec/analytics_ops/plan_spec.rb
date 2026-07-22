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
  end
end
