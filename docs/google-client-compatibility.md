# Google client compatibility

Analytics Ops uses only Google's official modern Ruby clients. It adds no
second HTTP stack and does not expose generated Google objects publicly.

## Supported versions

| Direct dependency | Constraint | Contract-tested release |
| --- | --- | --- |
| `google-analytics-admin` | `~> 0.8.0` | 0.8.0 |
| `google-analytics-data` | `~> 0.9.0` | 0.9.0 |
| `googleauth` | `~> 1.12` | 1.17.1 |
| `mcp` | `~> 0.25.0` | 0.25.0 |

The reviewed lockfile resolves these generated transports:

| Versioned transport | Reviewed release |
| --- | --- |
| `google-analytics-admin-v1alpha` | 0.43.0 |
| `google-analytics-data-v1beta` | 0.22.0 |

The main Admin wrapper currently selects a V1alpha generated transport. That
transport name does not make every feature Alpha: Google publishes feature
maturity separately. Analytics Ops treats capabilities Google identifies as
Alpha as experimental or unsupported.

The API-wrapper bounds allow reviewed patch updates inside each minor line and
reject a new minor contract automatically. The `googleauth` bound stays within
its compatible 1.x public API. `doctor` reports the installed Admin and Data
wrapper versions, expected bounds, and selected `grpc` or `rest` transport.

## Executable contract coverage

Tests coerce deterministic fake requests and responses through official
protobuf classes for:

- `list_account_summaries`
- `get_property`
- `list_data_streams`
- `get_data_retention_settings`
- `update_data_retention_settings`
- `list_key_events` and `create_key_event`
- list/create/update custom dimensions
- list/create/update custom metrics
- custom-metric restricted cost/revenue enum translation
- update web data-stream default URI
- `run_report`, `batch_run_reports`, and `run_realtime_report`

The tests also prove enum mappings and normalization into immutable gem-owned
values without making network requests. Service-account tests exercise the
official `Google::Auth::ServiceAccountCredentials` loader with generated fake
keys and verify the exact read/edit scopes.

MCP contract tests use the official Ruby SDK to prove the exact tool allowlist,
strict input validation, structured output, redacted errors, lazy credential
loading, and read-only/non-destructive annotations.

## Updating a Google client

1. Review the official release and Admin API changelog.
2. Update one direct bound intentionally.
3. Resolve the lockfile on every supported Ruby.
4. Run focused Admin/Data contract specs.
5. Run the full Ruby and Rails CI matrix.
6. Update this file and the changelog.

Do not merge an automated client update based only on dependency resolution.
Generated method, field, enum, and transport changes require contract review.
