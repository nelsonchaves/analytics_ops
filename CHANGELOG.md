# Changelog

Analytics Ops follows Semantic Versioning for its public Ruby, CLI,
configuration, and plan contracts.

## [0.2.0] - 2026-07-22

### Added

- Configuration-free `properties` and `discover` commands, removing the
  property-ID onboarding deadlock.
- Service-account-only `setup` with strict JSON-key validation, numbered
  property selection, effective API access checks, and non-interactive
  automation support.
- Atomic mode-`0600` user-level connection storage that remembers only the
  service-account key path and never copies the key.
- Non-destructive atomic creation of the smallest valid `production`
  configuration. Matching configuration is reused; conflicting profiles are
  never overwritten.
- A five-section, row-bounded `overview` powered by one official
  `batchRunReports` request, with immutable normalized results and property
  quota metadata.
- Friendly `traffic` and `landing-pages` report aliases plus `--json` and
  `--csv` format shortcuts.
- Optional Rails `analytics:overview` Rake task.
- A public real-app read-only smoke-test and release-gate guide using the
  single service-account authentication path.

### Changed

- Account/property-only discovery no longer fetches every property's streams;
  detailed `discover` retains the original stream output.
- The setup, connection, overview, CLI, Google-client, RBS, and operator
  documentation now describe the simpler three-command start.
- Currency custom metrics now carry Google's required cost/revenue restricted-
  data classification through configuration, snapshots, plans, and requests.
- Rails installation now generates a minimal property-only configuration, so
  sample stream or retention values cannot become accidental changes.
- The Rails generator preserves configuration already created by setup and
  adds the binstub without an overwrite prompt.
- Every CLI and Ruby orchestration path now loads an explicit service account;
  ambient credentials, API keys, browser login, and external CLI
  authentication are not fallback paths.
- `googleauth` is now a direct reviewed dependency because Analytics Ops calls
  its service-account loader explicitly.
- Read-only operations request only `analytics.readonly`; guarded apply
  creates a separate client with `analytics.edit`.

### Fixed

- Reject duplicate or excessively nested YAML, impossible user-retention
  periods, Google-invalid custom-definition display names, oversized stream
  URIs, reversed report dates, malformed numeric filters, and non-finite
  client options before calling Google.
- Preserve Google's automatic `dateRange` column, distinguish absent report
  metadata, validate quota/row/header shapes, and reject invalid UTF-8 output.
- Translate pagination and raw socket failures into typed errors and reject
  malformed or cross-property Admin responses.
- Require the literal boolean `true` for Ruby apply confirmation and reject
  non-web, cross-property, or otherwise forged saved-plan payloads.
- Handle Ctrl-C as clean human or JSON output with exit status 130 instead of
  dumping a Ruby backtrace.

### Security

- Setup validates a bounded service-account key and stores only its canonical
  path outside the project; keys never enter configuration, plans, logs, or
  output.
- Setup verifies access before writing configuration or remembering the key
  path, and non-interactive mode never prompts.
- Credential-shaped values are rejected from configuration and plans; JSON
  secret assignments, invalid bytes, and terminal controls are sanitized.
- Human output is terminal-safe, and CSV formula protection covers headers and
  values hidden behind whitespace or controls.
- Existing guarded apply, stale-plan, no-delete, redaction, and no-network-on-
  load guarantees remain unchanged.

## [0.1.0] - 2026-07-22

### Added

- Strict version-1 YAML configuration with safe Psych parsing, no ERB or
  aliases, a 1 MiB limit, allowlisted environment interpolation, fail-closed
  keys, quoted numeric identifiers, and committed JSON Schema.
- Immutable desired state, normalized Admin resources, canonical JSON,
  snapshot fingerprints, and deterministic planning.
- Version-1 saved plans with strict scalar/payload/identity validation,
  duplicate-key and secret-field rejection, cross-property protection,
  atomic mode-0600 writes, and committed JSON Schema.
- Create/update-only planning for web stream default URI, retention, key
  events, custom dimensions, and custom metrics. Unmanaged resources are never
  deleted or archived.
- Explicit guarded apply with saved-plan-only execution, fresh snapshot
  validation, stale-plan rejection, stop-on-first-failure behavior, and
  structured partial reconciliation.
- Lazy official Google Admin and Data adapters, typed/redacted errors,
  deterministic protobuf contract tests, and no generated types in public
  results.
- `doctor`, `discover`, `snapshot`, `audit`, `plan`, `apply`,
  `verify`, `report`, `realtime`, and `schema` CLI commands.
- Human, automation-safe JSON, and report-only CSV output with stable exit
  statuses.
- Immutable standard/realtime report definitions, normalized result metadata
  and quota information, and seven built-in commercial recipes.
- Optional Rails 7.2–8.1 Railtie, install generator, binstub, and read-only
  operator Rake tasks.
- Public RBS signatures, security/redaction checks, Ruby 3.2–4.0 CI, Rails
  compatibility jobs, package inspection, dependency audit, and OIDC Trusted
  Publishing workflow.
- Complete operator, safety, report, Rails, architecture, compatibility, and
  troubleshooting documentation.

### Security

- Requiring the gem, loading configuration, and booting Rails perform no
  network I/O.
- Credentials and report rows are excluded from configuration and plan
  contracts; common credential patterns are redacted from errors.
- Ordinary plans cannot delete or archive resources.
