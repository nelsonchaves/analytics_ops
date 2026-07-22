# Live read-only smoke test

Use this guide before releasing Analytics Ops or when proving a new
installation against a real application. The smoke test reads Google
Analytics and writes one temporary local configuration file. It never changes
Google Analytics.

## The four things Google names similarly

| Item | What it is | Example |
| --- | --- | --- |
| Google account | The human identity used to sign in to Google | `operator@example.test` |
| Analytics account | A GA4 container that owns one or more properties | Account ID `100000001` |
| GA4 property | The reporting and configuration boundary Analytics Ops reads | Property ID `123456789` |
| Google Cloud project | Enables APIs, owns quota, and owns service accounts or OAuth clients | `example-analytics-project` |

The Cloud project does not contain the website's analytics data. It identifies
the software calling Google, enables the Admin and Data APIs, and supplies
quota. Permission to a Cloud project does not grant permission to a GA4
account or property; the calling identity must also be added in Google
Analytics Access Management.

A standard API key is not sufficient. It identifies the Cloud project but not
a principal authorized to read private GA4 data. Use either a service account
or user OAuth.

## Enable the two APIs

In the selected Google Cloud project, enable:

- Google Analytics Admin API (`analyticsadmin.googleapis.com`)
- Google Analytics Data API (`analyticsdata.googleapis.com`)

The Admin API reads account, property, stream, retention, key-event, and custom
definition configuration. The Data API runs standard and realtime reports.
Both are required by `setup` and `doctor`.

## Simplest local authentication: service account, no CLI

This route does not require Google Cloud CLI, a consent screen, a Desktop OAuth
client, or a browser login.

1. Open [Google Cloud service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
   in the Cloud project that owns the enabled APIs.
2. Create a service account such as **Analytics Ops Local**. It does not need a
   broad Cloud IAM role merely to call the Analytics APIs.
3. Create one JSON key and download it directly to a secure location outside
   every source repository.
4. Copy only the service account email address—not the key contents.
5. In Google Analytics, open **Admin**, then **Account access management** or
   **Property access management**, and add that email. Use Viewer for this
   read-only smoke test. Adding it at account level grants the selected role to
   the account's properties; property level limits it to one property.
6. Point Google's official clients to the file for the current terminal:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/outside/repositories/analytics-ops-reader.json"
```

Analytics Ops does not read the JSON into configuration, a plan, logs, or
output. Google's official clients discover it through Application Default
Credentials. Keep the file out of shell history where practical, restrict its
filesystem permissions, and revoke the key if it is exposed.

For future reviewed mutations, the service-account identity needs an
edit-capable Analytics role. Do not grant that role for this smoke test, and do
not put mutation credentials in a Rails web container.

Google documents service-account authentication in both the
[Data API quickstart](https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart)
and [Admin API quickstart](https://developers.google.com/analytics/devguides/config/admin/v1/quickstart).

## Alternative: your Google user through Desktop OAuth

User OAuth is useful when one human already has access to many Analytics
accounts and adding a service account to each would be inconvenient.

Google Auth Platform asks for an audience:

- **Internal** is available only to an eligible Google Workspace organization
  and limits login to that organization.
- **External** supports ordinary Google accounts. While the application is in
  testing mode, add the signed-in Google account as a test user.

Create an owned **Desktop app** client in
[Google Auth Platform clients](https://console.cloud.google.com/auth/clients),
download its JSON outside all repositories, and run:

```bash
analytics-ops setup \
  --client-id-file /absolute/path/outside/repositories/desktop-oauth.json
```

Plain interactive setup uses Google Cloud CLI's shared OAuth client. Some
Google accounts show **This app is blocked** when that shared client requests
`analytics.readonly`. Repeating the same login will not fix it. Cancel, create
the owned Desktop client, add the test user when required, and use
`--client-id-file`. On macOS, the current Homebrew cask is:

```bash
brew install --cask gcloud-cli
```

The service-account route above avoids this entire OAuth and CLI flow.

## Test the current checkout through a real app

Temporarily point the host application's Gemfile at the local gem checkout:

```ruby
gem "analytics_ops",
    path: "/absolute/path/to/analytics_ops",
    group: :development
```

Then run `bundle install` in the host application. `bundle info analytics_ops`
must show the local checkout and version `0.2.0`.

### Preserve an existing configuration

Setup never overwrites a conflicting profile. If
`config/analytics_ops.yml` already exists, hold it outside the application
while testing:

```bash
analytics_smoke_backup="$(mktemp -d)"
cp config/analytics_ops.yml "$analytics_smoke_backup/original.yml"
mv config/analytics_ops.yml "$analytics_smoke_backup/held.yml"
```

Do not print the file. Although property and stream IDs are not credentials,
production identifiers and environment conventions do not belong in public
test output.

### Run the read-only commands

From the host application:

```bash
bundle install
bundle exec analytics-ops version
bundle info analytics_ops
bundle exec analytics-ops setup
bundle exec analytics-ops doctor
bundle exec analytics-ops overview
bundle exec analytics-ops report traffic --json
bundle exec analytics-ops realtime
bundle exec analytics-ops audit
```

Empty reports are acceptable for a property with little traffic. The smoke
test fails on authentication or authorization errors, malformed output,
crashes, or Google-client errors.

`audit` is read-only. Exit status `0` means the declared state converges; exit
status `2` means drift was found. Both are successful smoke-test outcomes.

During this test:

- Never run `analytics-ops apply`.
- Do not generate a plan for application.
- Never commit OAuth JSON, service-account JSON, ADC files, report rows,
  screenshots containing credentials, or temporary production identifiers.
- Do not paste credential contents into a terminal transcript, issue, or chat.

## Restore and clean the host application

After the commands finish, preserve the generated smoke file only long enough
to diagnose a failure, then restore the original configuration:

```bash
mv config/analytics_ops.yml "$analytics_smoke_backup/generated.yml"
cp "$analytics_smoke_backup/original.yml" config/analytics_ops.yml
cmp "$analytics_smoke_backup/original.yml" config/analytics_ops.yml
unset GOOGLE_APPLICATION_CREDENTIALS
```

After confirming the restoration, delete the temporary backup directory using
the operating system's normal secure cleanup process. Remove any accidental
credential copy from either repository immediately and rotate that key.

Keep the local path dependency until `0.2.0` is published. After publication,
replace it with:

```ruby
gem "analytics_ops", "~> 0.2", group: :development
```

Run `bundle install`, then confirm `bundle info analytics_ops` resolves version
`0.2.0` from RubyGems rather than the local path.

## Release gate

Do not tag while any live read-only command or local release check is failing.
Before release, require all of the following:

- The complete live smoke test passed.
- `bin/check`, package inspection, and `git diff --check` passed in the gem.
- Documentation and changelog describe the released behavior.
- The gem worktree is clean and the release commit is on `origin/master`.
- The version and changelog both say `0.2.0`.

Create and push an annotated tag only after those checks:

```bash
git tag -a v0.2.0 -m "Release Analytics Ops 0.2.0"
git push origin v0.2.0
```

The tag workflow repeats verification and publishes through RubyGems Trusted
Publishing. Never run a manual `gem push`, and never store a RubyGems API key
in the repository or GitHub Actions.
