# Contributing

Thank you for helping make Analytics Ops safer and easier to operate.

## Setup

```bash
git clone https://github.com/nelsonchaves/analytics_ops.git
cd analytics_ops
bin/setup
bin/check
```

Useful focused commands:

```bash
bundle exec rspec spec/analytics_ops/clients/data_spec.rb
bundle exec rubocop
bundle exec rbs -I sig validate
bundle exec rake build
```

Use `RSPEC_STATUS_FILE=/tmp/analytics_ops-rspec-status` when the repository is
mounted read-only except for source edits.

## Design rules

- Keep the core plain Ruby and independent of Rails and Active Support.
- Use Google's official Ruby clients and the service-account-only contract; do
  not add another HTTP or authentication stack.
- Keep generated Google objects behind adapters.
- Do not introduce telemetry, a database, browser analytics, or boot-time
  network access.
- Preserve the read-only default and saved-plan confirmation boundary.
- Do not add ordinary delete/archive operations.
- Use immutable gem-owned public values and typed errors.

## Tests

Use RSpec. Run focused specs while changing a subsystem, then run the complete
suite before the milestone commit. Ordinary tests must use injected fakes and
must never contact a real property.

An opt-in live check may use only a dedicated disposable GA4 property. It must
use uniquely prefixed resources and clean up only resources it created. Never
run a live test against production.

Changes to a Google adapter need request/response coercion tests against the
supported official generated classes. Changes to planning need deterministic
output, stale-state, cross-property, and idempotency coverage.

## Pull requests

Keep commits focused and explain:

- the user-visible problem and public contract
- read/write behavior and rollback implications
- tests and compatibility checks performed
- documentation or schema changes

Update `CHANGELOG.md` and the relevant support matrix when behavior changes.
Configuration and plan incompatibilities require an explicit schema version;
they never migrate silently.

Never commit credentials, real property exports, visitor data, production
plans, or production identifiers. Follow [SECURITY.md](SECURITY.md) for private
vulnerability reports and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for project
conduct.
