# Changelog

Analytics Ops follows Semantic Versioning for its public Ruby, CLI,
configuration, and plan contracts.

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
