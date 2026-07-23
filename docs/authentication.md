# Authentication

Analytics Ops supports one authentication method: a Google service-account
JSON key.

It does not use `gcloud`, browser login, Desktop OAuth, Application Default
Credentials, `GOOGLE_APPLICATION_CREDENTIALS`, or API keys.

## One-time setup

You need a Google Cloud project only to own the service account, enable the two
Analytics APIs, and supply API quota. It does not need to be the project that
hosts your website.

1. In the Cloud project, enable:
   - Google Analytics Admin API
   - Google Analytics Data API
2. Open [Google Cloud service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts).
3. Create a service account named **Analytics Ops Local**. Do not grant broad
   Cloud IAM roles.
4. Open the service account, choose **Keys**, create a JSON key, and save it
   outside every source repository.
5. Copy the service-account email, such as
   `analytics-ops@example-project.iam.gserviceaccount.com`.
6. In GA4, open **Admin → Account access management → Add users**.
7. Add the service-account email:
   - **Viewer** is enough for reports, discovery, snapshots, and audits.
   - **Editor** is required if this identity will apply reviewed changes.
8. Connect Analytics Ops:

```bash
analytics-ops setup \
  --service-account /absolute/path/to/service-account.json
```

Setup verifies both APIs, lists the GA4 properties available to the service
account, lets you select one, and creates `config/analytics_ops.yml`.

After that, use normal commands without another credential option:

```bash
analytics-ops overview
analytics-ops report traffic
analytics-ops realtime
analytics-ops audit
```

## What Analytics Ops remembers

Analytics Ops writes this user-level file:

```text
~/.config/analytics_ops/connection.json
```

It contains only the absolute path to the service-account key. The connection
file is created atomically with mode `0600`, and its directory uses mode
`0700`. Analytics Ops does not copy the key or place its contents in project
configuration.

Keep the key in a stable location. Moving or deleting it requires setup again:

```bash
analytics-ops setup \
  --service-account /new/absolute/path/to/service-account.json
```

One service account can access several GA4 accounts. Add the same
service-account email at account level in each GA4 account.

## Read and edit access

Normal commands request only Google's `analytics.readonly` scope. The guarded
`apply` command requests `analytics.edit` in addition to read access.

Scopes do not grant GA4 access by themselves. The service account must also
have the matching Viewer or Editor role in GA4 Access Management.

Analytics Ops still requires a saved plan, explicit confirmation, and a fresh
matching snapshot before any apply. Merely configuring an Editor identity
does not cause writes.

## Automation

Use the same service-account setup non-interactively:

```bash
analytics-ops setup \
  --service-account /secure/path/service-account.json \
  --property 123456789 \
  --non-interactive \
  --json
```

Keep the JSON key in the CI platform's protected secret-file storage. Never
put its contents in an environment variable, command argument, repository, or
build log.

## Ruby API

The Ruby API can use an explicit service account without changing the saved
user connection:

```ruby
service_account = AnalyticsOps::ServiceAccount.new(
  "/secure/path/service-account.json"
)

workspace = AnalyticsOps::Workspace.load(
  "config/analytics_ops.yml",
  profile: "production",
  service_account: service_account
)
```

Loading the identity reads and validates the local key. It does not contact
Google. Network access starts only when a connection or workspace operation is
called.

## Values that are easy to confuse

| Value | Example | Meaning |
| --- | --- | --- |
| GA4 account ID | `100000001` | Analytics container shown by discovery |
| GA4 property ID | `123456789` | Numeric reporting and configuration boundary |
| Stream ID | `987654321` | Numeric data-stream resource |
| Measurement ID | `G-EXAMPLE1` | Browser tagging ID; not a property or stream ID |
| Cloud project | `example-analytics-project` | Owns APIs, quota, and the service account |
| Service-account email | `analytics-ops@example-project.iam.gserviceaccount.com` | Identity added to GA4 Access Management |
| Service-account JSON | A downloaded private key file | Secret used by Analytics Ops; never commit it |

An API key identifies a Cloud project but cannot authorize access to private
GA4 data or settings.

## Credential rules

- Never place the JSON key or its path in `analytics_ops.yml`.
- Never commit a service-account key.
- Never paste key contents into chat, issues, logs, screenshots, or reports.
- Never place production mutation credentials in a Rails web container.
- Revoke and replace a key immediately if it may have been exposed.
- Remove stale keys from the service account after rotation.

Official Google references:

- [Admin API quickstart](https://developers.google.com/analytics/devguides/config/admin/v1/quickstart)
- [Data API quickstart](https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart)
