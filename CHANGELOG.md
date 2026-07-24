# Changelog

Analytics Ops follows Semantic Versioning for its public Ruby, CLI,
configuration, and plan contracts.

## [Unreleased]

## [0.3.0] - 2026-07-23

### Added

- Named service-account connections with per-configuration profile mappings,
  `connections`, `profiles`, and `use` commands, plus automatic migration from
  the version-1 single-key pointer.
- Collision-safe automatic connection names when separate applications both
  use the default `production` profile with different credentials.
- Safe additive setup for a second property profile without hand-editing YAML.
- `--last`, `--from`, `--to`, and `--compare` for standard reports and
  overviews, with bounded equal preceding-period comparisons.
- A read-only `portfolio` summary across every configured property and its
  associated Google connection.
- A local stdio `mcp` server for ChatGPT desktop, Codex, and Claude Code. Its
  strict tool allowlist supports discovery, doctor, snapshot, audit,
  overview, portfolio, standard reports, and realtime reads only.
- Service-account file permission and Git-repository placement warnings in
  setup and doctor.
- A beginner-friendly AI connection guide with the exact local commands,
  privacy boundary, and optional OpenAI Secure MCP Tunnel explanation.

### Changed

- Verify future RubyGems releases from the published artifact instead of
  waiting for the legacy full index, which can lag behind a successful
  Trusted Publishing upload.
- Rails generator and CLI setup now share the `production` default. Setup can
  fill the untouched generated placeholder, and Rails tasks use the locally
  selected profile unless `ANALYTICS_OPS_PROFILE` explicitly overrides it.
- The mode-`0600` user connection file now stores multiple named key paths and
  profile selections while still storing no key material.
- Google transport errors preserve bounded structured reason, metadata, and
  status values so disabled-API guidance does not depend on English wording.

### Fixed

- Show complete redacted before/after values during interactive apply instead
  of truncating the exact operation being approved.
- Require `--non-interactive --yes` for JSON apply so prompts can never corrupt
  machine-readable standard output.
- Reject duplicate stream IDs during configuration loading instead of failing
  later during planning.
- Preserve both the beginning and ending of long human report cells so similar
  URLs remain visibly distinct.
- Validate saved connection mappings against existing connection names.

### Security

- Every MCP tool is explicitly annotated read-only and non-destructive; the
  server contains no plan, apply, create, update, delete, archive, credential,
  or key-path tool.
- Starting MCP, listing local profiles, and switching profiles perform no
  Google network access or credential loading.
- MCP input schemas are strict and bounded, tool errors are redacted, and
  unexpected exceptions do not expose internal details.

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

- Keep empty rows for dimensionless standard reports so overview totals retain
  their metric headers on a new or empty GA4 property.
- Use only Google's compatible `eventCount` metric in the built-in
  `realtime_events` recipe.
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
