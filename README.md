# Analytics Ops

[![Gem Version](https://img.shields.io/gem/v/analytics_ops.svg)](https://rubygems.org/gems/analytics_ops)
[![CI](https://github.com/nelsonchaves/analytics_ops/actions/workflows/ci.yml/badge.svg)](https://github.com/nelsonchaves/analytics_ops/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/analytics_ops)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE.txt)

**Google Analytics 4 configuration as code and reporting for Ruby and Rails.**

Analytics Ops gives you a review-first way to inspect GA4, detect drift, run
useful reports, and apply a small set of safe configuration changes. The core
is plain Ruby; Rails support is optional.

## Three-command start

You need Ruby 3.2 or newer, access to a GA4 property, and a Google
service-account JSON key kept outside the repository.

```bash
gem install analytics_ops
analytics-ops setup --service-account /absolute/path/to/service-account.json
analytics-ops overview
```

`setup` lists the properties the service account can access, lets you choose
one, and creates the smallest valid `config/analytics_ops.yml` for the default
`production` profile. It securely remembers the key's path, so every later
command works without another authentication option. You do not need
`gcloud`, browser authorization, a property ID, or hand-written YAML.

`overview` makes one bounded batch request and shows totals, a daily trend,
traffic acquisition, landing pages, and devices for the previous 28 complete
days. Both commands are read-only in Google Analytics.

## Google Analytics setup (first time only)

The setup is easier when you keep these four separate things in mind:

| Item | What it does |
| --- | --- |
| Human Google Account | The account you use to sign in to Google Analytics and Google Cloud |
| GA4 account and property | Holds your website's analytics configuration and collected data |
| Google Cloud project | Owns API access, quota, and the service account; it does not hold your GA4 report data |
| Service account | The non-human identity Analytics Ops uses to call Google's APIs |

### A. Create GA4 only if you do not already have it

Already have a working GA4 property collecting website data? Skip to
[Create the Google Cloud project](#b-create-the-google-cloud-project).

1. Sign in at [Google Analytics](https://analytics.google.com).
2. Click **Start Measuring**, or open **Admin → Create → Account**.
3. Create an Analytics account.
4. Create a GA4 property and choose its reporting time zone and currency.
5. Create a Web data stream using your website URL.
6. Install the resulting Google tag or Measurement ID on your website.

Analytics Ops reads and manages an existing GA4 property. It does not install
the website tracking tag or send browser events.

### B. Create the Google Cloud project

1. Sign in at [Google Cloud](https://console.cloud.google.com).
2. Open the project selector and choose **New Project**.
3. Use a clear name such as **Analytics Ops**.
4. Choose **No organization** if you use a personal account. That is fine.
5. Create the project and make sure it is selected before continuing.

Google requires this separate project for API access, quota, and the service
account identity. Creating it does not create another GA4 account or move your
analytics data.

### C. Enable the two required APIs

In the selected Cloud project, open **APIs & Services → Library** and enable
exactly:

- **Google Analytics Admin API**
- **Google Analytics Data API**

You do not need the Gemini API.

### D. Create the service account

1. Open **IAM & Admin → Service Accounts**.
2. Click **Create service account**.
3. Use a name such as **Analytics Ops Local**.
4. Continue past the optional Cloud permissions step without assigning
   **Owner**, **Editor**, or another broad Cloud IAM role.
5. Finish creating the service account.
6. Copy its email address. It resembles:
   `analytics-ops@example-project.iam.gserviceaccount.com`.

Google Cloud IAM Editor and GA4 Editor are different roles. The service
account does not need the Cloud IAM Editor role.

### E. Download and protect the JSON key

1. Open the service account you just created.
2. Open **Keys**.
3. Choose **Add key → Create new key → JSON**.
4. Download the key.
5. Move it to a stable location outside every application repository.
6. On macOS or Linux, protect it with mode `0600`:

```bash
mkdir -p ~/.config/analytics_ops
chmod 700 ~/.config/analytics_ops
mv /path/to/downloaded-key.json \
  ~/.config/analytics_ops/service-account.json
chmod 600 ~/.config/analytics_ops/service-account.json
```

Protect this file like a password:

- Never commit it.
- Never paste its contents into chat, logs, screenshots, issues, or
  environment variables.
- Do not put it inside `config/analytics_ops.yml`.
- If it is exposed, revoke the key in Google Cloud and create a replacement.

### F. Give the service account GA4 access

1. Return to [Google Analytics](https://analytics.google.com).
2. Select the correct GA4 account and property.
3. Open **Admin**.
4. Choose **Property access management** for one property, or **Account access
   management** for every property in that GA4 account.
5. Click **+ → Add users**.
6. Paste the service-account email.
7. Disable **Notify new users by email**. A service account has no human
   inbox.
8. Select **Viewer** for reports, discovery, snapshots, doctor, and audit.
   Select **Editor** only if you plan to use reviewed `apply` operations
   later.
9. Do not grant **Administrator**. Analytics Ops does not manage GA4 users.
10. Click **Add**.

Your human Google Account must already have permission to manage users in
that GA4 account or property.

### G. Install and connect Analytics Ops

For a standalone installation:

```bash
gem install analytics_ops
analytics-ops setup \
  --service-account ~/.config/analytics_ops/service-account.json
```

For an application that uses Bundler, add:

```ruby
# Gemfile
gem "analytics_ops", "~> 0.2", group: :development
```

Then run:

```bash
bundle install
bundle exec analytics-ops setup \
  --service-account ~/.config/analytics_ops/service-account.json
```

Setup:

- validates the key
- verifies both Analytics APIs
- lists the GA4 properties the service account can access
- lets you choose a property
- creates `config/analytics_ops.yml`
- remembers only the key's absolute path in
  `~/.config/analytics_ops/connection.json`

### H. Verify the connection with read-only commands

```bash
bundle exec analytics-ops doctor
bundle exec analytics-ops properties
bundle exec analytics-ops overview
bundle exec analytics-ops report traffic --json
bundle exec analytics-ops realtime
bundle exec analytics-ops audit
```

Empty reports are normal for a new property. These checks are read-only in
GA4. Setup also makes no GA4 changes; it writes only the local configuration
and connection pointer.

`audit` exits with status `0` when configuration matches and status `2` when
it finds drift. Both are successful read-only results.

You do not need `gcloud`, a browser OAuth login, an OAuth consent screen, an
OAuth test-user list, or Gemini. An API key cannot authorize access to private
GA4 data.

`apply` is the mutating command. Do not run it until you have created and
reviewed a saved plan.

### I. Quick troubleshooting

- **No properties listed:** Add the exact service-account email to the correct
  GA4 account or property.
- **API disabled:** Select the correct Cloud project and confirm both
  Analytics APIs are enabled.
- **Permission denied:** Grant Viewer or Editor inside GA4. A Google Cloud IAM
  role does not grant access to GA4 data.
- **“This app is blocked” opens in a browser:** That is an obsolete OAuth
  flow. Analytics Ops 0.2 uses a service-account JSON key and does not launch
  browser authorization.
- **Key unavailable:** Run setup again with the key's new absolute path.
- **Key creation disabled:** An organization policy may prohibit downloaded
  service-account keys. Ask the Google Workspace or Cloud administrator.

Google's official guides cover
[GA4 account and property creation](https://support.google.com/analytics/answer/14183469?hl=en),
[Cloud project creation](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects),
[API enablement](https://docs.cloud.google.com/service-usage/docs/enable-disable),
[service-account creation](https://docs.cloud.google.com/iam/docs/service-accounts-create),
[JSON key creation](https://docs.cloud.google.com/iam/docs/keys-create-delete),
and [GA4 access management](https://support.google.com/analytics/answer/9305788?hl=en).

See the [live read-only smoke-test guide](docs/live-smoke-test.md) for a safe
real-app release test.

Already connected? List properties before creating configuration:

```bash
analytics-ops properties
analytics-ops discover # includes data streams
```

## The safe change workflow

```text
configuration → audit → saved plan → review → apply → verify
```

```bash
# Read-only: save a deterministic plan with mode 0600
bundle exec analytics-ops plan --output tmp/ga4-plan.json

# Review the JSON before doing anything
less tmp/ga4-plan.json

# Mutating: prints the exact saved operations and asks you to type yes
bundle exec analytics-ops apply tmp/ga4-plan.json

# Read-only: confirm managed settings now match
bundle exec analytics-ops verify
```

`apply` refreshes the remote snapshot, rejects stale plans, and executes only
the operations in the saved file. Ordinary plans never delete or archive
anything. If one operation fails, execution stops and reports what succeeded,
what failed, and what remains.

## Common commands

| Command | Purpose | Remote writes? |
| --- | --- | --- |
| `analytics-ops setup --service-account PATH` | Connect, choose a property, and create minimal configuration | No |
| `analytics-ops properties` | List accessible accounts and properties without configuration | No |
| `analytics-ops doctor` | Check configuration, credentials, APIs, property access, clients, and clock | No |
| `analytics-ops discover` | List accessible accounts, properties, and streams without configuration | No |
| `analytics-ops overview` | Show five useful reports in one bounded batch | No |
| `analytics-ops snapshot` | Print normalized managed remote state | No |
| `analytics-ops audit` | Show drift without writing a plan file | No |
| `analytics-ops plan --output FILE` | Review and save deterministic changes | No |
| `analytics-ops apply FILE` | Apply one reviewed, non-stale plan | **Yes** |
| `analytics-ops verify` | Check convergence | No |
| `analytics-ops report NAME` | Run a built-in standard report | No |
| `analytics-ops realtime` | Run the realtime-events report | No |
| `analytics-ops schema --format json` | Print the configuration schema | No |

Use `--json` or `--format json` for automation. CSV is available only for
individual reports:

```bash
bundle exec analytics-ops report landing-pages --csv
```

Friendly `traffic` and `landing-pages` aliases leave the original
`traffic_acquisition` and `landing_pages` names fully supported.

See [Commands](docs/commands.md) for every option and exit status.

## IDs: the quick distinction

Use fake values like these in examples and tests:

| Value | Example | Where it belongs |
| --- | --- | --- |
| Account ID | `100000001` | Discovery output only |
| Property ID | `123456789` | `property_id` in configuration and API requests |
| Stream ID | `987654321` | `stream_id` in configuration |
| Measurement ID | `G-EXAMPLE1` | Browser tagging; never use it as a stream ID |
| Cloud project | `example-analytics-project` | Owns enabled APIs, quota, and the service account |
| Service-account identity | `ga-reader@example-project.iam.gserviceaccount.com` | Granted GA4 access; its key is never this YAML |

## Ruby API

```ruby
workspace = AnalyticsOps::Workspace.load(
  "config/analytics_ops.yml",
  profile: "production"
)

plan = workspace.plan
plan.write("tmp/ga4-plan.json")

report = workspace.report("calculator_completions")
report.rows.each { |row| puts row.fetch("eventCount") }

overview = workspace.overview
puts overview.report("overview_totals").rows
```

Loading the gem, loading YAML, and booting Rails do not contact Google.
Network calls happen only when a workspace operation is invoked.

## Rails

```ruby
# Gemfile
gem "analytics_ops", require: "analytics_ops/rails", group: :development
```

```bash
bundle exec analytics-ops setup \
  --profile development \
  --service-account /absolute/path/to/service-account.json
bin/rails generate analytics_ops:install
bin/rake analytics:doctor
bin/rake analytics:overview
bin/rake 'analytics:report[traffic_acquisition]'
```

The integration is a Railtie, not an Engine. It adds a generator and operator
Rake tasks—no models, migrations, routes, controllers, views, JavaScript, or
boot-time network calls. See [Rails integration](docs/rails.md).

## What Analytics Ops does not do

- It does not inject browser analytics or manage consent banners.
- It stores only the service-account key's path in a mode-`0600` user file;
  it never copies the key, tokens, or report rows.
- It does not delete accounts, properties, streams, or unmanaged resources.
- It does not claim to manage settings that Google exposes only in the UI.
- Experimental declarations are findings only in version 0.2.0; they are not
  silently applied through Alpha APIs.

## Documentation

| Guide | Topic |
| --- | --- |
| [Authentication](docs/authentication.md) | One-time service-account setup and key safety |
| [Live smoke test](docs/live-smoke-test.md) | Real-app read-only verification and release gate |
| [Configuration](docs/configuration.md) | Complete strict YAML contract |
| [Commands](docs/commands.md) | CLI syntax, formats, and exit statuses |
| [Reports](docs/reports.md) | Built-in recipes and GA reporting limitations |
| [Rails](docs/rails.md) | Generator and Rake tasks |
| [Safety](docs/safety.md) | Plans, stale-state protection, rollback, and credentials |
| [Plan format](docs/plan-format.md) | Version-1 JSON contract |
| [API support](docs/api-support-matrix.md) | Exactly what is managed, manual, or unsupported |
| [Client compatibility](docs/google-client-compatibility.md) | Tested official Google gem versions |
| [Troubleshooting](docs/troubleshooting.md) | Common failures and fixes |
| [Architecture](docs/architecture.md) | Boundaries and data flow |

For development, run:

```bash
bin/setup
bin/check
```

Security issues belong in private vulnerability reporting; see
[SECURITY.md](SECURITY.md). Contributions follow [CONTRIBUTING.md](CONTRIBUTING.md).

Analytics Ops is MIT licensed and is not affiliated with, sponsored by, or
endorsed by Google LLC. Google Analytics is a trademark of Google LLC and is
named only to describe API compatibility.
