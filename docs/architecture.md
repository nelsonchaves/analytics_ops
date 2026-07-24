# Architecture

Analytics Ops is a plain-Ruby library and CLI with optional Rails hooks. It has
no database and keeps Google's generated classes behind two narrow adapters.

```text
strict YAML
  → immutable desired state
  → Admin API snapshot
  → deterministic planner
  → versioned saved plan
  → explicit guarded apply
  → convergence verification

immutable report definition
  → Data API adapter
  → immutable normalized result

configuration-free connection
  → explicit service-account identity
  → account/property discovery
  → API access verification
  → atomic minimal configuration

named local connections + profiles
  → selected property
  → single-property workspace or read-only portfolio

local MCP stdio
  → read-only tool allowlist
  → Workspace and Portfolio
```

## Core objects

| Object | Responsibility |
| --- | --- |
| `Configuration` | Bounded safe YAML, environment interpolation, schema validation |
| `Configuration::Writer` | Non-destructive atomic creation or additive profile update |
| `DesiredState` | Immutable configuration for one profile |
| `Resources` | Gem-owned account/property/stream/settings values |
| `Snapshot` | Canonical managed remote state and SHA-256 fingerprint |
| `Planner` | Pure desired-versus-snapshot comparison; no client access |
| `Plan` | Strict deterministic JSON mutation contract |
| `Applier` | Confirmation, fresh-snapshot check, sequential saved operations |
| `Clients::Admin` | Official Admin request translation and response normalization |
| `Reports::Definition` | Strict immutable Data API query |
| `Clients::Data` | Standard/realtime request translation and result normalization |
| `ServiceAccount` | Strict JSON-key validation, scopes, and user-level path storage |
| `Connection` | Configuration-free discovery and selected-property access verification |
| `Setup` | Property selection, verification, and safe configuration creation |
| `Workspace` | Public orchestration API with independently injectable clients |
| `Portfolio` | Read-only totals across configured profiles and connections |
| `Reports::Period` | Bounded simple dates and equal preceding-period comparisons |
| `MCPServer` | Local strictly read-only AI tools over Workspace and Portfolio |
| `CLI` | Option validation, formats, stable statuses, and explicit confirmation |
| `Railtie` | Optional generator and operator Rake tasks |

## Dependency direction

Domain and planning code know nothing about protobufs, gRPC, Rails, Active
Support, authentication flows, or HTTP transports. Admin and Data adapters translate
official generated values immediately into immutable Analytics Ops values.
The adapters can be injected independently, so tests use deterministic fakes.

The core requires Google's wrapper gems lazily. Requiring `analytics_ops`,
constructing a `Connection`, loading configuration, and booting Rails define
or validate local objects only; they do not instantiate a generated client,
read a service-account key, or contact Google.

The MCP protocol implementation uses the official Ruby MCP SDK. Starting the
server lists local tools only; credentials and Google clients remain lazy
until a tool is called.

## State model

Google Analytics is the remote source of truth. There is no local state
database. The configuration declares desired state and a snapshot captures the
relevant remote state. Canonical key ordering and normalized arrays make
snapshot fingerprints and plan bytes deterministic.

`setup` discovers properties through a configuration-free `Connection`,
verifies the selected property, and creates or additively updates the existing
versioned YAML format. Existing conflicting profiles are never rewritten. A
separate user-level `connection.json` stores named absolute service-account
key paths and per-configuration profile selections. It is not desired state
and contains no key material.

Apply accepts an already validated plan, refreshes the snapshot, compares its
fingerprint, then sends only the saved operations. A partial response is
explicit reconciliation data, not a hidden retry or rollback.

## Error boundary

Expected failures become typed Analytics Ops errors:

- configuration and invalid plan
- authentication and authorization
- unsupported capability and identity conflict
- stale plan and confirmation required
- quota, timeout, invalid request, and remote failure
- partial apply with a structured result

Messages are redacted before user-visible output. Structured Google reason,
metadata, and status values are preserved in bounded Analytics Ops errors so
setup does not need to recognize English wording.

An injected logger receives small JSON request events containing only the
service method and target resource. Request bodies, authorization data, and
report results are never logged automatically. CLI logging defaults to
`warn`.

## Rails boundary

`require "analytics_ops/rails"` adds a Railtie only. It does not add an
Engine, model, migration, route, controller, view, asset, or boot-time network
call. Browser analytics and consent remain application concerns.

## AI boundary

`analytics-ops mcp` is a local stdio server. Its tool registry contains only
property discovery, health checks, snapshots, audits, overviews, portfolios,
built-in reports, and realtime reads. Every tool is marked read-only and
non-destructive. Plan creation, plan-file writing, apply, create, update, and
delete are absent rather than hidden behind model instructions.

Tool outputs can contain analytics configuration and report rows. The chosen
AI product receives those requested outputs, but never the service-account
key, token, authorization header, or saved key path.

## Experimental boundary

Google identifies certain Admin capabilities as Alpha. Version 0.3.0 accepts
explicit Enhanced Measurement and Google Signals declarations only so they can
appear as experimental findings. It does not apply them. Stable/beta
operations do not depend on an experimental public Analytics Ops contract.
