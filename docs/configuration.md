# Configuration

Analytics Ops reads strict, versioned YAML. The file describes desired GA4
state; it never contains credentials.

For the normal first run, let setup create the file after you choose a
property:

```bash
analytics-ops setup --service-account /absolute/path/to/service-account.json
```

Setup writes only a quoted property ID under the `production` profile. It
will reuse a matching file but will not overwrite an existing profile that
targets another property.

## Smallest valid file

```yaml
version: 1

profiles:
  production:
    property_id: "123456789"
```

Numeric identifiers must stay quoted. `property_id` is a GA4 property ID,
not account ID `100000001`, stream ID `987654321`, or measurement ID
`G-EXAMPLE1`.

Use it with:

```bash
analytics-ops doctor
analytics-ops audit
```

The default path is `config/analytics_ops.yml`; the default profile is
`production`. Change them with `--config` and `--profile`.

## Complete example

All identifiers below are fake:

```yaml
version: 1

profiles:
  production:
    property_id: "${GA4_PROPERTY_ID}"

    streams:
      web:
        stream_id: "${GA4_STREAM_ID}"
        default_uri: "https://www.example.test"

        # Accepted only as an explicit experimental declaration.
        # Version 0.2.0 reports a finding and does not apply this setting.
        enhanced_measurement:
          enabled: true
          experimental: true

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

      - parameter_name: customer_segment
        display_name: Customer segment
        description: Broad non-sensitive segment
        scope: user
        disallow_ads_personalization: true

    custom_metrics:
      - parameter_name: estimate_total
        display_name: Estimate total
        description: Non-sensitive calculated estimate
        scope: event
        measurement_unit: currency
        # Google requires currency metrics to be classified explicitly.
        restricted_metric_types:
          - revenue_data

    # Checklist findings only; Analytics Ops does not claim to manage these.
    manual_requirements:
      - email_redaction_enabled
      - consent_mode_reviewed

    # Explicit declaration only in 0.2.0; never silently applied.
    google_signals:
      state: disabled
      experimental: true
```

## Managed fields

### Streams

`streams` is keyed by a local readable name. Each entry requires a numeric
`stream_id`. For a web stream, `default_uri` may be an absolute HTTP or
HTTPS URI without embedded credentials. Analytics Ops can update an existing
web stream URI; it does not automatically create or delete streams.

### Retention

All three fields are required when `retention` is present:

- `event_data`: `2_months`, `14_months`, `26_months`, `38_months`, or
  `50_months`
- `user_data`: `2_months` or `14_months`
- `reset_on_new_activity`: `true` or `false`

The 26-, 38-, and 50-month event periods are available only to Analytics 360
properties. Google does not allow those periods for user data, so Analytics
Ops rejects them locally. An API rejection for an ineligible event period is
returned as a typed error; the gem never substitutes a different period.

### Key events

`key_events` is a unique list of event names. Missing events are created with
`once_per_event` counting. Existing key events are not deleted or renamed.

### Custom dimensions

Required fields are `parameter_name`, `display_name`, and `scope`.
Supported scopes are `event`, `user`, and `item`.
`disallow_ads_personalization` is valid only for user-scoped dimensions.
Display names must start with a letter and contain only letters, numbers,
spaces, and underscores, matching Google's create/update contract.

Identity is `scope + parameter_name`; display name and description are
mutable. Immutable conflicts are findings, not automatic replacement.

### Custom metrics

Required fields are `parameter_name`, `display_name`, and
`scope: event`. Units are:

`standard`, `currency`, `feet`, `meters`, `kilometers`, `miles`,
`milliseconds`, `seconds`, `minutes`, and `hours`.

A `currency` metric also requires `restricted_metric_types` containing
`cost_data`, `revenue_data`, or both. This classification controls restricted
data access in Google Analytics, so Analytics Ops never guesses it. The field
must be omitted or empty for non-currency metrics.

Identity is `parameter_name`. Scope, unit, and restricted-data classification
are treated as immutable; Analytics Ops will not archive and recreate a
conflicting metric.

## Environment variables

Only the literal form `${UPPER_CASE_NAME}` is expanded, and interpolation
happens after safe YAML parsing:

```bash
export GA4_PROPERTY_ID=123456789
export GA4_STREAM_ID=987654321
analytics-ops doctor
```

Missing or malformed variables fail validation. There is no ERB, command
execution, YAML alias support, or Ruby-object deserialization.

## Strict safety rules

- The file is limited to 1 MiB.
- YAML nesting is bounded and duplicate mapping keys are rejected.
- Unknown fields fail closed.
- Secret-shaped fields and credential-shaped values fail closed.
- Numeric identifiers must be YAML strings.
- User-visible strings reject control characters.
- Duplicate resource identities fail validation.
- Configuration loading never contacts Google.

The machine-readable contract is
[configuration-schema-v1.json](configuration-schema-v1.json). Print the same
schema from the installed gem with:

```bash
analytics-ops schema --format json
```
