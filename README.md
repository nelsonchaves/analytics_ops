# Analytics Ops

**Google Analytics 4 configuration as code and reporting for Ruby and Rails.**

Analytics Ops gives you a review-first way to inspect GA4, detect drift, run
useful reports, and apply a small set of safe configuration changes. The core
is plain Ruby; Rails support is optional.

## Three-command start

You need Ruby 3.2 or newer, access to a GA4 property, and the
[Google Cloud CLI](https://cloud.google.com/sdk/docs/install).

```bash
gem install analytics_ops
analytics-ops setup
analytics-ops overview
```

`setup` uses Google's official Application Default Credentials flow, lists
the properties your Google identity can access, and lets you choose one. It
then creates the smallest valid `config/analytics_ops.yml` for the default
`production` profile. You do not need to find a property ID or write YAML.

`overview` makes one bounded batch request and shows totals, a daily trend,
traffic acquisition, landing pages, and devices for the previous 28 complete
days. Both commands are read-only in Google Analytics.

To use Analytics Ops inside an application's bundle instead:

```ruby
# Gemfile
gem "analytics_ops", "~> 0.2", group: :development
```

```bash
bundle install
bundle exec analytics-ops setup
bundle exec analytics-ops overview
```

Already authenticated? List properties before creating configuration:

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
| `analytics-ops setup` | Authenticate, choose a property, and create minimal configuration | No |
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
| OAuth client | A Cloud project client ID/secret | Owned by your application, never this YAML |
| Service-account identity | `ga-reader@example-project.iam.gserviceaccount.com` | Granted GA access; its key is never this YAML |

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
- It does not store credentials, tokens, report rows, or local state.
- It does not delete accounts, properties, streams, or unmanaged resources.
- It does not claim to manage settings that Google exposes only in the UI.
- Experimental declarations are findings only in version 0.2.0; they are not
  silently applied through Alpha APIs.

## Documentation

| Guide | Topic |
| --- | --- |
| [Authentication](docs/authentication.md) | ADC, scopes, service accounts, and safe automation |
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
