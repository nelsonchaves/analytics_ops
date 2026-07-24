# Rails integration

Rails support is optional and lives behind:

```ruby
# Gemfile
gem "analytics_ops", require: "analytics_ops/rails", group: :development
```

It supports Rails 7.2, 8.0, and 8.1. The core gem does not depend on Rails or
Active Support.

## Install

```bash
bundle install
bin/rails generate analytics_ops:install
bundle exec analytics-ops setup \
  --service-account /absolute/path/to/service-account.json
```

The generator creates only:

- `config/analytics_ops.yml`
- `bin/analytics-ops` with executable mode

The order is flexible:

- Generator first: setup safely replaces the untouched placeholder.
- Setup first: the generator preserves the valid configuration and adds only
  the binstub.

The generated file has the same minimal `production` profile used by the CLI.
It contains no active stream, retention, key-event, dimension, or metric
policy, so installation alone cannot produce a mutation plan. Add managed
settings only after reviewing the configuration guide.

## Rake tasks

```bash
bin/rake analytics:doctor
bin/rake analytics:overview
bin/rake analytics:portfolio
bin/rake analytics:audit
bin/rake analytics:plan
bin/rake analytics:verify
bin/rake 'analytics:report[traffic_acquisition]'
```

`analytics:plan` writes `tmp/analytics_ops-plan.json`. Override task inputs
without changing application code:

```bash
ANALYTICS_OPS_PROFILE=production \
ANALYTICS_OPS_CONFIG=config/analytics_ops.yml \
ANALYTICS_OPS_PLAN=tmp/production-ga4-plan.json \
bin/rake analytics:plan
```

Rails tasks use the profile selected by `analytics-ops use`. Set
`ANALYTICS_OPS_PROFILE` only for an explicit one-run override; Rails
environment names no longer silently select a different profile.

There is intentionally no `analytics:apply` Rake task. Apply a reviewed file
with the explicit CLI:

```bash
bin/analytics-ops apply tmp/production-ga4-plan.json
```

## Runtime boundary

The integration is a Railtie, not an Engine. It has no:

- models or database
- migrations
- routes or controllers
- views or helpers
- assets or JavaScript
- browser tag injection

Requiring `analytics_ops/rails`, booting Rails, and registering Rake tasks do
not construct Google clients or make network requests. A network call begins
only when an operator invokes a task or CLI operation.

Do not place production mutation credentials in a Rails web container.
Scheduled audits may use a dedicated read-only identity. Interactive apply
belongs on an administrator workstation or in a protected release workflow.
