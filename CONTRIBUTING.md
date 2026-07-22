# Contributing

Thank you for helping make Analytics Ops safer and easier to use.

## Before opening a pull request

1. Open an issue for a new public capability or configuration change.
2. Keep the plain-Ruby core independent of Rails and Active Support.
3. Do not add a second HTTP or authentication implementation around Google's
   official clients.
4. Do not introduce boot-time network access, telemetry, or credential
   persistence.
5. Add focused RSpec coverage for changed behavior.
6. Update the changelog and applicable compatibility documentation.

## Setup

```bash
bin/setup
bundle exec rake
```

## Tests

Unit and CLI integration tests use injected fake clients. They must not call a
real Google property. Live API checks are opt-in, use a dedicated test
property, and are never required for ordinary contributors.

## Compatibility

Changes must work on supported Ruby versions and preserve the gem-owned public
contracts. Generated Google API classes must remain behind adapter boundaries.
Alpha API capabilities require an explicit experimental opt-in and graceful
handling when a method is unavailable.

## Pull requests

Keep commits focused and explain:

- The user-visible problem.
- The public contract, if any, that changes.
- The safety and rollback behavior.
- The verification performed.

Never include credentials, real property exports, visitor data, or production
plan files.

## Conduct and security

Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Report vulnerabilities using
[SECURITY.md](SECURITY.md), not a public issue.
