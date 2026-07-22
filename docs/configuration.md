# Configuration contract

The primary configuration is safe, versioned YAML. It contains desired state,
never credentials.

```yaml
version: 1

profiles:
  production:
    property_id: "123456789"

    streams:
      web:
        stream_id: "987654321"
        default_uri: "https://example.com"
        enhanced_measurement:
          enabled: false

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

    manual_requirements:
      - email_redaction_enabled
      - ads_personalization_disabled
```

## Parsing rules

- Load with safe YAML parsing.
- Do not permit arbitrary Ruby objects or ERB.
- Unknown keys are errors.
- IDs remain strings even when numeric.
- Secret-shaped keys and credential material are invalid.
- Support only explicit `${VARIABLE_NAME}` environment interpolation.
- Missing environment variables are errors.
- Configuration migrations are explicit commands and never occur during
  `apply`.

## Identity rules

Resources use stable remote identities:

- Property and stream IDs.
- Event name for key events.
- Parameter name and scope for custom dimensions.
- Parameter name for custom metrics.

Display names are mutable descriptions and cannot identify resources.

This document defines the intended version-1 contract. The implementation is
not complete until schema fixtures, validation, and compatibility tests ship.
