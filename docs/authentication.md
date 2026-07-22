# Authentication

Analytics Ops uses [Google Application Default Credentials (ADC)](https://cloud.google.com/docs/authentication/application-default-credentials)
through Google's official Ruby clients. It does not implement OAuth, store
tokens, or accept credential fields in configuration.

## Local read-only use without Google Cloud CLI

The simplest local route is a service account. Create one in the Cloud project
where the Analytics Admin and Data APIs are enabled, download its JSON key
outside every repository, and add the service account email in Google
Analytics Account or Property Access Management with the Viewer role.

Point Google's official clients to it for the current terminal:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/outside/repositories/analytics-ops-reader.json"
analytics-ops setup
```

No consent screen, Desktop OAuth client, browser login, or `gcloud`
installation is required. A normal API key cannot replace this identity
because it does not authorize access to private Analytics data. See the
[live smoke-test guide](live-smoke-test.md) for exact Cloud, GA4, host-app, and
cleanup steps.

## Local read-only use with your Google account

The easiest path is:

```bash
analytics-ops setup
```

Setup tests existing ADC first. If login is required, it runs the official
Google Cloud CLI command, then discovers properties and verifies both APIs.
Google stores the resulting ADC in its standard local credential location;
Analytics Ops never copies credentials into project files, plans, logs, or
report output. The login command may replace existing local ADC used by other
development tools, so setup tells you before it starts the command.

To create ADC yourself, use an identity that has read access to the target
GA4 property:

```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly"
```

Enable both APIs in the Google Cloud project used for authentication:

- Google Analytics Admin API
- Google Analytics Data API

Then run:

```bash
analytics-ops doctor
```

If Google's shared CLI client shows **This app is blocked** or cannot request
the Analytics scope for your account or organization, do not keep retrying it:

1. Open [Google Auth Platform clients](https://console.cloud.google.com/auth/clients)
   in the Cloud project where both Analytics APIs are enabled.
2. Choose **Create client**, then **Desktop app**.
3. Download the client JSON and keep it outside the repository.
4. Pass it directly to `gcloud` through setup:

```bash
analytics-ops setup --client-id-file path/to/desktop-oauth.json
```

Google's [Desktop client instructions](https://developers.google.com/workspace/guides/create-credentials#desktop-app)
and [`gcloud auth application-default login` reference](https://cloud.google.com/sdk/gcloud/reference/auth/application-default/login)
describe the same two pieces. The client file identifies your local OAuth
application; it is not a GA4 property ID or a service-account key.

On a headless or SSH machine:

```bash
analytics-ops setup --no-launch-browser
```

In non-interactive environments, setup never starts a login flow. Supply
working ADC and the property explicitly:

```bash
analytics-ops setup \
  --property 123456789 \
  --non-interactive \
  --json
```

`doctor` makes small read-only calls to both APIs. It confirms that Google
accepts the credentials and that the property can be read. The installed
clients do not expose a reliable contract for inspecting the scopes inside an
already-issued token, so `doctor` reports scope inspection as `unknown`
instead of guessing.

## Applying changes

Read-only credentials cannot apply a plan. Use a separately protected identity
with the `analytics.edit` scope and sufficient access to the GA4 property:

```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/analytics.edit"
```

Keep mutation credentials out of a deployed Rails web container. Apply plans
from an administrator workstation or a protected release job.

## Automation

Prefer one of these:

- A dedicated service account with only the GA properties and roles it needs.
- Workload Identity Federation, which avoids a long-lived JSON key.
- An explicitly injected Google credentials object when using the Ruby API.

Cloud IAM permission alone does not grant access to a GA4 property. Add the
service-account identity—such as
`ga-reader@example-project.iam.gserviceaccount.com`—to the property with the
appropriate Google Analytics role.

## Values that are easy to confuse

| Value | Example | Meaning |
| --- | --- | --- |
| Property ID | `123456789` | Numeric GA4 property identifier used by Admin and Data APIs |
| Stream ID | `987654321` | Numeric data-stream resource identifier |
| Measurement ID | `G-EXAMPLE1` | Web tagging identifier; not accepted as `property_id` or `stream_id` |
| Account ID | `100000001` | Numeric Analytics account identifier shown by discovery |
| OAuth client | Client ID and secret in your Cloud project | Starts a user OAuth flow; never put it in Analytics Ops YAML |
| Service account | An IAM email identity | Receives GA property access; a JSON private key is credential material |

## Credential rules

- Never put credentials, paths to credentials, access tokens, refresh tokens,
  private keys, API keys, or OAuth secrets in `analytics_ops.yml`.
- Never put credentials in a saved plan.
- Never commit service-account JSON.
- Never commit a downloaded Desktop OAuth client file.
- Never paste credentials into an issue, fixture, log, or report.
- Revoke or rotate credentials immediately after suspected exposure.
- Do not create a shared public OAuth client for this gem.

Analytics Ops redacts common credential patterns from translated errors, but
redaction is a final safety net—not a safe way to handle secrets.

Official Google setup references:

- [Admin API quickstart](https://developers.google.com/analytics/devguides/config/admin/v1/quickstart)
- [Data API quickstart](https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart-client-libraries)
