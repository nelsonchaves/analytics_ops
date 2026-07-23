# Troubleshooting

Start with:

```bash
analytics-ops setup --service-account /absolute/path/to/service-account.json
analytics-ops properties
analytics-ops doctor --json
```

`properties` works without configuration. Setup verifies both APIs and creates
the minimal file; doctor performs the complete configured-property check.

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
secret- or credential-shaped material are intentionally rejected.

Currency custom metrics require an explicit restricted-data classification:

```yaml
measurement_unit: currency
restricted_metric_types: [revenue_data]
```

Use `cost_data`, `revenue_data`, or both according to the metric's meaning.
Analytics Ops will not guess. User-data retention accepts only `2_months` or
`14_months`; longer 360 periods apply only to event data.

## Authentication failure (exit 66)

Analytics Ops could not load or use the configured service account.

```bash
analytics-ops setup \
  --service-account /absolute/path/outside/repositories/service-account.json
```

Check that:

- the file still exists at that path
- it is a JSON key whose `type` is `service_account`
- the key has not been revoked in Google Cloud
- the Analytics Admin and Data APIs are enabled in its Cloud project
- the service-account email is added in GA4 Access Management

The saved pointer is `~/.config/analytics_ops/connection.json`. It contains
only the key path. Rerunning setup with `--service-account` safely replaces
that pointer after API verification succeeds.

Analytics Ops does not fall back to `gcloud`, browser login, Application
Default Credentials, `GOOGLE_APPLICATION_CREDENTIALS`, or API keys.

## Permission failure (exit 77)

The service-account identity needs access inside the GA4 property. Cloud IAM
alone is not enough. Add its email to GA4 Access Management with Viewer for
reads or Editor for plan application.

Use `analytics-ops properties` to see accessible numeric property IDs without
creating configuration. `discover` additionally retrieves streams.

## API or remote failure (exit 69)

Confirm that the Google Analytics Admin API and Data API are enabled in the
credential's Cloud project. Check the configuration ID and the error's typed
message. Invalid dimensions, metrics, custom definitions, or property
restrictions can also produce this status.

When setup recognizes disabled APIs, enable both APIs in the Google Cloud
project that owns the service account.

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
