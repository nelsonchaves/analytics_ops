# frozen_string_literal: true

module AnalyticsOps
  module Configuration
    # Public machine-readable summary. Runtime validation also enforces
    # cross-field identity rules and printable user-visible values.
    SCHEMA = Canonical.deep_freeze(
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => "https://github.com/nelsonchaves/analytics_ops/blob/master/docs/configuration-schema-v1.json",
      "title" => "Analytics Ops configuration version 1",
      "type" => "object",
      "additionalProperties" => false,
      "required" => %w[version profiles],
      "properties" => {
        "version" => { "const" => 1 },
        "profiles" => {
          "type" => "object",
          "minProperties" => 1,
          "propertyNames" => { "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,63}$" },
          "additionalProperties" => { "$ref" => "#/$defs/profile" }
        }
      },
      "$defs" => {
        "id" => {
          "type" => "string",
          "pattern" => "^(?:[0-9]{1,50}|\\$\\{[A-Z][A-Z0-9_]*\\})$"
        },
        "profile" => {
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["property_id"],
          "properties" => {
            "property_id" => { "$ref" => "#/$defs/id" },
            "streams" => {
              "type" => "object",
              "propertyNames" => { "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,63}$" },
              "additionalProperties" => { "$ref" => "#/$defs/stream" }
            },
            "retention" => { "$ref" => "#/$defs/retention" },
            "google_signals" => { "$ref" => "#/$defs/googleSignals" },
            "key_events" => {
              "type" => "array", "uniqueItems" => true,
              "items" => { "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,39}$" }
            },
            "custom_dimensions" => { "type" => "array", "items" => { "$ref" => "#/$defs/customDimension" } },
            "custom_metrics" => { "type" => "array", "items" => { "$ref" => "#/$defs/customMetric" } },
            "manual_requirements" => {
              "type" => "array", "uniqueItems" => true,
              "items" => { "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,63}$" }
            }
          }
        },
        "stream" => {
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["stream_id"],
          "properties" => {
            "stream_id" => { "$ref" => "#/$defs/id" },
            "default_uri" => { "type" => "string", "maxLength" => 2_048, "pattern" => "^(?:https?://|\\$\\{)" },
            "enhanced_measurement" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[enabled experimental],
              "properties" => { "enabled" => { "type" => "boolean" }, "experimental" => { "const" => true } }
            }
          }
        },
        "retention" => {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[event_data user_data reset_on_new_activity],
          "properties" => {
            "event_data" => { "$ref" => "#/$defs/retentionValue" },
            "user_data" => { "$ref" => "#/$defs/userRetentionValue" },
            "reset_on_new_activity" => { "type" => "boolean" }
          }
        },
        "retentionValue" => { "enum" => Configuration::Validator::RETENTION_VALUES },
        "userRetentionValue" => { "enum" => Configuration::Validator::USER_RETENTION_VALUES },
        "googleSignals" => {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[state experimental],
          "properties" => { "state" => { "enum" => %w[enabled disabled] }, "experimental" => { "const" => true } }
        },
        "customDimension" => {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[parameter_name display_name scope],
          "properties" => {
            "parameter_name" => { "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,39}$" },
            "display_name" => {
              "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_ ]{0,81}$"
            },
            "description" => {
              "type" => "string", "maxLength" => 150, "pattern" => "^[^\\u0000-\\u001F\\u007F]*$"
            },
            "scope" => { "enum" => Configuration::Validator::DIMENSION_SCOPES },
            "disallow_ads_personalization" => { "type" => "boolean" }
          },
          "allOf" => [
            {
              "if" => { "properties" => { "scope" => { "const" => "user" } } },
              "then" => {
                "properties" => {
                  "parameter_name" => { "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,23}$" }
                }
              }
            },
            {
              "if" => {
                "required" => ["disallow_ads_personalization"],
                "properties" => { "disallow_ads_personalization" => { "const" => true } }
              },
              "then" => { "properties" => { "scope" => { "const" => "user" } } }
            }
          ]
        },
        "customMetric" => {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[parameter_name display_name scope],
          "properties" => {
            "parameter_name" => { "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_]{0,39}$" },
            "display_name" => {
              "type" => "string", "pattern" => "^[A-Za-z][A-Za-z0-9_ ]{0,81}$"
            },
            "description" => {
              "type" => "string", "maxLength" => 150, "pattern" => "^[^\\u0000-\\u001F\\u007F]*$"
            },
            "scope" => { "const" => "event" },
            "measurement_unit" => { "enum" => Configuration::Validator::METRIC_UNITS },
            "restricted_metric_types" => {
              "type" => "array", "uniqueItems" => true,
              "items" => { "enum" => Configuration::Validator::RESTRICTED_METRIC_TYPES }
            }
          },
          "allOf" => [
            {
              "if" => {
                "required" => ["measurement_unit"],
                "properties" => { "measurement_unit" => { "const" => "currency" } }
              },
              "then" => {
                "required" => ["restricted_metric_types"],
                "properties" => { "restricted_metric_types" => { "minItems" => 1 } }
              },
              "else" => { "properties" => { "restricted_metric_types" => { "maxItems" => 0 } } }
            }
          ]
        }
      }
    )
  end
end
