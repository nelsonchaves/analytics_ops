# Troubleshooting

Start with:

```bash
analytics-ops doctor --format json
```

The command is read-only and checks both Google APIs.

## Configuration error

```text
ConfigurationError: ... property_id must be a numeric identifier encoded as a string
```

Quote numeric IDs:

```yaml
property_id: "123456789"
stream_id: "987654321"
```

Do not use account ID `100000001` or measurement ID `G-EXAMPLE1` in those
fields. Unknown keys, ERB, YAML aliases, missing environment variables, and
secret-shaped fields are intentionally rejected.

## Authentication failure (exit 66)

Create ADC again and ensure both APIs are enabled:

```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly"
```

If `GOOGLE_APPLICATION_CREDENTIALS` is set, confirm that it points to the
intended local credential file. Never add that path or file to configuration
or source control.

## Permission failure (exit 77)

The Google identity needs access inside the GA4 property. Cloud IAM alone is
not enough. Add the user or service-account identity to the property with a
read role; use an edit-capable role only for plan application.

Use `analytics-ops discover` to see accessible numeric property IDs.

## API or remote failure (exit 69)

Confirm that the Google Analytics Admin API and Data API are enabled in the
credential's Cloud project. Check the configuration ID and the error's typed
message. Invalid dimensions, metrics, custom definitions, or property
restrictions can also produce this status.

## Quota (exit 75) or timeout (exit 74)

Wait for Google quota to recover, reduce report frequency, or use a positive
`--timeout`. Do not blindly retry an apply after an uncertain response;
snapshot and replan so remote state is reconciled first.

## Drift status 2

This is expected automation behavior, not a crash. `audit` and `verify`
return 2 when managed state differs or a drift finding remains.

## Stale plan (exit 79)

Someone or something changed relevant remote state after the plan was created.
Generate a new plan, review it, and apply that new file. Never edit the saved
fingerprint.

## Partial apply (exit 80)

Read the reconciliation output. It lists applied, failed, and unattempted
operations. Verify the property, perform any deliberate manual rollback, then
generate a new plan. Do not rerun the old plan.

## A custom report fails

Confirm every requested dimension and metric is compatible and registered.
Event-scoped custom fields use names such as
`customEvent:calculator_slug`. Standard reports require a date range;
realtime reports reject date ranges and offsets.

Google thresholding, sampling, consent coverage, cardinality, and processing
delay can explain an empty or lower-than-expected result. Inspect
`result.metadata` in JSON output.

## Rails task cannot find a profile

Rails tasks default to `Rails.env`. The generator creates a
`development` profile. Add the intended profile or override it:

```bash
ANALYTICS_OPS_PROFILE=production bin/rake analytics:doctor
```

## Report a problem safely

Include the gem version, Ruby version, command name, exit status, and a minimal
configuration with obviously fake IDs. Do not include credentials, tokens,
authorization headers, real report rows, production plans, or private keys.
