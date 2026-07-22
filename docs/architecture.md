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
```

## Core objects

| Object | Responsibility |
| --- | --- |
| `Configuration` | Bounded safe YAML, environment interpolation, schema validation |
| `DesiredState` | Immutable configuration for one profile |
| `Resources` | Gem-owned account/property/stream/settings values |
| `Snapshot` | Canonical managed remote state and SHA-256 fingerprint |
| `Planner` | Pure desired-versus-snapshot comparison; no client access |
| `Plan` | Strict deterministic JSON mutation contract |
| `Applier` | Confirmation, fresh-snapshot check, sequential saved operations |
| `Clients::Admin` | Official Admin request translation and response normalization |
| `Reports::Definition` | Strict immutable Data API query |
| `Clients::Data` | Standard/realtime request translation and result normalization |
| `Workspace` | Public orchestration API with independently injectable clients |
| `CLI` | Option validation, formats, stable statuses, and explicit confirmation |
| `Railtie` | Optional generator and operator Rake tasks |

## Dependency direction

Domain and planning code know nothing about protobufs, gRPC, Rails, Active
Support, OAuth flows, or HTTP transports. Admin and Data adapters translate
official generated values immediately into immutable Analytics Ops values.
The adapters can be injected independently, so tests use deterministic fakes.

The core requires Google's wrapper gems lazily. Requiring `analytics_ops`
defines classes only; it does not instantiate a client or discover ADC.

## State model

Google Analytics is the remote source of truth. There is no local state
database. The configuration declares desired state and a snapshot captures the
relevant remote state. Canonical key ordering and normalized arrays make
snapshot fingerprints and plan bytes deterministic.

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

Messages are redacted before user-visible output. Callers do not need to parse
Google exception text.

An injected logger receives small JSON request events containing only the
service method and target resource. Request bodies, authorization data, and
report results are never logged automatically. CLI logging defaults to
`warn`.

## Rails boundary

`require "analytics_ops/rails"` adds a Railtie only. It does not add an
Engine, model, migration, route, controller, view, asset, or boot-time network
call. Browser analytics and consent remain application concerns.

## Experimental boundary

Google identifies certain Admin capabilities as Alpha. Version 0.1.0 accepts
explicit Enhanced Measurement and Google Signals declarations only so they can
appear as experimental findings. It does not apply them. Stable/beta
operations do not depend on an experimental public Analytics Ops contract.
