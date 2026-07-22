# Analytics Ops

**Manage Google Analytics 4 configuration and reports from Ruby—safely and
repeatably.**

Analytics Ops is an open-source Ruby gem and command-line tool. It is being
built to help teams review GA4 settings, find configuration drift, plan safe
changes, and run reports without repeating work in the Google Analytics UI.

> [!IMPORTANT]
> This project is in early development and is not yet available on RubyGems.
> The command line currently supports `help` and `version`; the GA4 commands
> described in the roadmap are not implemented yet.

## Quick start

You need [Ruby](https://www.ruby-lang.org/) 3.2 or newer, Bundler, and Git.

```bash
git clone https://github.com/nelsonchaves/analytics_ops.git
cd analytics_ops
bin/setup
bin/analytics-ops help
```

That is all you need to install the dependencies and open the CLI help.

## Useful commands

Run these commands from the project folder:

| Command | What it does |
| --- | --- |
| `bin/setup` | Install project dependencies |
| `bin/analytics-ops help` | Show the available CLI commands |
| `bin/analytics-ops version` | Show the current version |
| `bin/check` | Run all tests and style checks |
| `bundle exec rake spec` | Run only the tests |
| `bundle exec rake rubocop` | Run only the style checks |
| `bin/console` | Open a Ruby console with Analytics Ops loaded |
| `bundle exec rake build` | Build the gem locally |

For most development work, you only need:

```bash
bin/setup
bin/check
```

## How it is designed to work

Analytics Ops follows a review-first workflow:

```text
desired configuration → audit → plan → review → apply → verify
```

- Audits, plans, verification, and reports are read-only.
- Changes require a saved plan and explicit confirmation.
- Credentials never belong in configuration or plan files.
- Requiring the gem or starting Rails never makes a network request.

The planned CLI will include commands for checking access, discovering GA4
properties, auditing settings, reviewing plans, applying approved changes,
verifying results, and running reports. See the [product plan](docs/product-plan.txt)
for the full roadmap.

## Use it in another Ruby project

Until the first RubyGems release, pin the gem to a commit you have reviewed:

```ruby
# Gemfile
gem "analytics_ops",
  github: "nelsonchaves/analytics_ops",
  ref: "REPLACE_WITH_A_COMMIT_SHA",
  group: :development
```

Then install it:

```bash
bundle install
```

Do not use an unpinned branch in production or release automation.

## Authentication

The current `help` and `version` commands do not need Google credentials.
Future GA4 commands will use Google Application Default Credentials, including
local user OAuth, service accounts, and Workload Identity Federation.

Analytics Ops does not store credentials. Never commit service-account JSON,
OAuth secrets, access tokens, or refresh tokens. See the
[authentication guide](docs/authentication.md) for details.

## Documentation

| Guide | Use it to learn about |
| --- | --- |
| [Configuration](docs/configuration.md) | The planned YAML configuration format |
| [Authentication](docs/authentication.md) | Google credentials and access |
| [Architecture](docs/architecture.md) | Project structure and safety boundaries |
| [Plan format](docs/plan-format.md) | How changes will be reviewed and protected |
| [API support matrix](docs/api-support-matrix.md) | Stable and experimental Google APIs |
| [Product plan](docs/product-plan.txt) | Roadmap, scope, and release gates |
| [Contributing](CONTRIBUTING.md) | Development and pull-request guidelines |

## Security

Do not open a public issue for a vulnerability or an exposed credential.
Follow the private reporting steps in [SECURITY.md](SECURITY.md).

## License and trademark

Analytics Ops is available under the [MIT License](LICENSE.txt).

This independent project is not affiliated with, sponsored by, or endorsed by
Google LLC. Google Analytics is a trademark of Google LLC and is named only to
describe API compatibility.

Everyone participating in the project must follow the
[code of conduct](CODE_OF_CONDUCT.md).
