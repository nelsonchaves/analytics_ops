# frozen_string_literal: true

RSpec.describe "public value immutability" do
  it "copies desired-state identity strings instead of freezing caller objects" do
    profile = +"production"
    property_id = +"123456789"

    state = build_desired_state(profile:, property_id:)

    expect(profile).not_to be_frozen
    expect(property_id).not_to be_frozen
    expect(state.profile).not_to equal(profile)
    expect(state.property_id).not_to equal(property_id)
    expect(state.profile).to be_frozen
    expect(state.property_id).to be_frozen
  end

  it "copies document and doctor collections instead of freezing caller containers" do
    state = build_desired_state
    profiles = { "production" => state }
    checks = [{ "name" => "configuration", "status" => "ok", "detail" => "valid" }]

    document = AnalyticsOps::Configuration::Document.new(version: 1, profiles:)
    doctor = AnalyticsOps::Workspace::DoctorResult.new(checks:)

    expect(profiles).not_to be_frozen
    expect(checks).not_to be_frozen
    expect(checks.first).not_to be_frozen
    expect(document.profiles).not_to equal(profiles)
    expect(doctor.checks).not_to equal(checks)
  end

  it "rejects foreign snapshot values instead of freezing caller-owned objects" do
    foreign = Object.new

    expect { snapshot(streams: [foreign]) }
      .to raise_error(ArgumentError, /streams must contain only/)
    expect(foreign).not_to be_frozen
  end

  it "deep-freezes shared report catalog inputs" do
    date_range = AnalyticsOps::Reports::Catalog::STANDARD_DATE_RANGE

    expect(date_range).to be_frozen
    expect(date_range.first).to be_frozen
  end
end
