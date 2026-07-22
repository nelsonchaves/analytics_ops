# Analytics Ops

Google Analytics 4 configuration as code and reporting for Ruby and Rails.

Analytics Ops is an independent, open-source Ruby library and command-line
tool for auditing GA4 properties, planning configuration changes, applying
approved changes safely, and retrieving useful reports. It builds on Google's
official Ruby API clients instead of reimplementing authentication or API
transport.

> [!IMPORTANT]
> Analytics Ops is under active development and has not been released to
> RubyGems. The current repository establishes the public contracts and secure
> foundation; do not depend on unreleased administrative behavior.

## Why Analytics Ops?

Google provides capable generated clients, but operating multiple properties
still requires teams to remember settings and repeat UI work. Analytics Ops is
designed around a reviewable workflow:

```text
desired configuration
  -> audit
  -> plan
  -> explicit apply
  -> verify
  -> report
```

The core is plain Ruby. Rails support will be optional and will never perform
network requests during application boot or ordinary web requests.

## Status

The current executable intentionally exposes only `help` and `version` while
the read-only foundation is implemented:

```bash
bundle exec analytics-ops help
bundle exec analytics-ops version
```

The planned public workflow is:

```bash
analytics-ops doctor
analytics-ops discover
analytics-ops audit
analytics-ops plan
analytics-ops apply PATH_TO_PLAN
analytics-ops verify
analytics-ops report REPORT_NAME
analytics-ops realtime
```

Read-only is the default. Applying changes will require a saved plan, explicit
confirmation, and a matching remote-state fingerprint.

## Installation during development

Until the first RubyGems release, use a pinned Git revision:

```ruby
gem "analytics_ops",
  github: "nelsonchaves/analytics_ops",
  ref: "REPLACE_WITH_A_REVIEWED_COMMIT",
  group: :development
```

Do not use an unpinned branch for production or release automation.

After the first stable public release, installation will be:

```bash
bundle add analytics_ops --group development
```

## Authentication

Analytics Ops will use Google Application Default Credentials. It will support
local user OAuth, service accounts, Workload Identity Federation, and injected
Google credential objects without storing credentials itself.

Never commit service-account JSON, OAuth secrets, access tokens, or refresh
tokens. See [Authentication](docs/authentication.md) and
[Security](SECURITY.md).

## Design principles

- Plain Ruby core with optional Rails integration.
- Google's official Admin and Data API clients.
- Safe YAML with no ERB or embedded credentials.
- No database and no telemetry.
- No browser tag, consent banner, or Measurement Protocol behavior.
- No network access when requiring the gem or booting Rails.
- Deterministic plans and idempotent apply behavior.
- Experimental Google APIs isolated behind explicit opt-in.
- No destructive operation in an ordinary apply.

See [Architecture](docs/architecture.md),
[Configuration](docs/configuration.md), [Plan format](docs/plan-format.md), and
the [API support matrix](docs/api-support-matrix.md). The complete long-term
scope and release gates are in the [product plan](docs/product-plan.txt).

## Development

After checking out the repository:

```bash
bin/setup
bundle exec rake
```

The default task runs the focused RSpec suite and RuboCop. Build and inspect
the package before every release:

```bash
gem build analytics_ops.gemspec
gem contents --show-install-dir analytics_ops
```

See [Contributing](CONTRIBUTING.md) for compatibility and pull-request rules.

## Security

Please do not open public issues for suspected vulnerabilities or accidentally
exposed credentials. Follow [SECURITY.md](SECURITY.md).

## License

Analytics Ops is available under the [MIT License](LICENSE.txt).

## Trademark notice

Analytics Ops is an independent project and is not affiliated with, sponsored
by, or endorsed by Google LLC. Google Analytics is a trademark of Google LLC.
The name is used only to describe compatibility with the Google Analytics 4
APIs.

## Code of conduct

Everyone participating in the project must follow the
[code of conduct](CODE_OF_CONDUCT.md).
