# Authentication

Analytics Ops uses [Google Application Default Credentials (ADC)](https://cloud.google.com/docs/authentication/application-default-credentials)
through Google's official Ruby clients. It does not implement OAuth, store
tokens, or accept credential fields in configuration.

## Local read-only use

Use an identity that has read access to the target GA4 property:

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
- Never paste credentials into an issue, fixture, log, or report.
- Revoke or rotate credentials immediately after suspected exposure.
- Do not create a shared public OAuth client for this gem.

Analytics Ops redacts common credential patterns from translated errors, but
redaction is a final safety net—not a safe way to handle secrets.

Official Google setup references:

- [Admin API quickstart](https://developers.google.com/analytics/devguides/config/admin/v1/quickstart)
- [Data API quickstart](https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart-client-libraries)
