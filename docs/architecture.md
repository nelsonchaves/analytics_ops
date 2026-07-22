# Architecture

Analytics Ops is a plain-Ruby library and CLI with optional Rails integration.
It translates Google-generated API objects at a narrow boundary and keeps its
planning domain independent from Google client implementation details.

```text
safe configuration
  -> desired state
  -> provider discovery
  -> normalized remote snapshot
  -> deterministic diff
  -> saved plan
  -> explicit apply
  -> convergence verification
```

## Boundaries

The intended library structure is:

```text
AnalyticsOps
├── Configuration
├── Authentication
├── Clients
│   ├── Admin
│   └── Data
├── Discovery
├── Snapshot
├── DesiredState
├── Capabilities
├── Diff
├── Plan
├── Apply
├── Verify
├── Resources
├── Reports
├── CLI
└── Rails
```

Google client objects are converted into immutable gem-owned resource values.
Diffing, planning, output, and policy code must not accept generated protobuf
or REST response objects directly.

Clients are injected. Unit and CLI integration tests use fake clients. Loading
the gem or Rails integration must never create a client or contact Google.

## API maturity

Stable and Beta operations are preferred. Alpha operations are isolated by
capability and require explicit opt-in. Missing Alpha methods return a typed
unsupported-capability result instead of raising an implementation error.

The public YAML and JSON formats use gem-owned vocabulary. Google enum and
class names remain private adapter details.

## State and convergence

Google Analytics is the remote source of truth; no local state database is
required. Configuration declares desired state and a snapshot captures the
relevant remote state. Plans include a snapshot fingerprint and cannot be
applied after relevant remote state changes.

A successful apply must converge: immediately generating a second plan with
the same inputs produces no changes.

## Rails integration

Rails support will use a Railtie for generators and Rake tasks. It will not be
an Engine because the gem has no routes, controllers, views, models, assets,
or migrations. Application request handling and browser analytics remain
outside the gem.
