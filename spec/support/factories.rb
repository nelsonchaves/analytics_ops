# frozen_string_literal: true

# Fake-only domain factories.

module AnalyticsOpsFactories
  def property(id: "123456789")
    AnalyticsOps::Resources::Property.new(
      id:,
      name: "properties/#{id}",
      display_name: "Example property",
      parent: "accounts/1000",
      property_type: "ordinary",
      can_edit: true
    )
  end

  def stream(id: "987654321", default_uri: "https://old.example.com")
    AnalyticsOps::Resources::DataStream.new(
      id:,
      name: "properties/123456789/dataStreams/#{id}",
      display_name: "Web",
      type: "web",
      default_uri:,
      measurement_id: "G-EXAMPLE"
    )
  end

  def retention(event_data: "2_months")
    AnalyticsOps::Resources::Retention.new(
      name: "properties/123456789/dataRetentionSettings",
      event_data:,
      user_data: "14_months",
      reset_on_new_activity: false
    )
  end

  def key_event(name = "existing_event")
    AnalyticsOps::Resources::KeyEvent.new(
      name: "properties/123456789/keyEvents/#{name}",
      event_name: name,
      counting_method: "once_per_event"
    )
  end

  def custom_dimension(description: "Old description")
    AnalyticsOps::Resources::CustomDimension.new(
      name: "properties/123456789/customDimensions/1",
      parameter_name: "calculator_slug",
      display_name: "Calculator slug",
      description:,
      scope: "event",
      disallow_ads_personalization: false
    )
  end

  def custom_metric
    AnalyticsOps::Resources::CustomMetric.new(
      name: "properties/123456789/customMetrics/1",
      parameter_name: "project_value",
      display_name: "Project value",
      description: "Estimated project value",
      scope: "event",
      measurement_unit: "currency"
    )
  end

  def snapshot(**overrides)
    values = {
      property: property,
      streams: [stream],
      retention: retention,
      key_events: [key_event],
      custom_dimensions: [custom_dimension],
      custom_metrics: [custom_metric]
    }.merge(overrides)
    AnalyticsOps::Snapshot.new(**values)
  end

  def build_desired_state(**overrides)
    values = {
      profile: "production",
      property_id: "123456789",
      streams: [
        {
          "name" => "web",
          "stream_id" => "987654321",
          "default_uri" => "https://example.com",
          "enhanced_measurement" => nil
        }
      ],
      retention: { "event_data" => "14_months", "user_data" => "14_months", "reset_on_new_activity" => false },
      key_events: %w[calculation_completed existing_event],
      custom_dimensions: [
        {
          "parameter_name" => "calculator_slug",
          "display_name" => "Calculator slug",
          "description" => "Published calculator identifier",
          "scope" => "event",
          "disallow_ads_personalization" => false
        }
      ],
      custom_metrics: [
        {
          "parameter_name" => "project_value",
          "display_name" => "Project value",
          "description" => "Estimated project value",
          "scope" => "event",
          "measurement_unit" => "currency"
        }
      ],
      manual_requirements: ["email_redaction_enabled"],
      google_signals: nil
    }.merge(overrides)
    AnalyticsOps::DesiredState.new(**values)
  end
end
