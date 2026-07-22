# Safety

Analytics Ops is read-only unless you explicitly apply a saved plan.

## What cannot mutate

`properties`, `doctor`, `discover`, `snapshot`, `audit`, `plan`, `verify`,
`overview`, `report`, and `realtime` only read Google Analytics APIs. Setup
may run Google's login command and create the local configuration file after
access is verified; it never changes Analytics. The login command can replace
existing local ADC. Loading the gem, constructing a connection, parsing YAML,
and booting Rails make no network request.

## What apply requires

An apply needs all of these:

1. A saved version-1 JSON plan.
2. A configuration profile matching the plan's profile and property ID.
3. Explicit confirmation—typed `yes`, or both `--non-interactive --yes`.
4. A fresh remote snapshot with the exact saved fingerprint.

The applier executes only the operations stored in the file. It never replans
during apply and never turns findings into changes.

The Ruby API also requires the literal boolean `true`; truthy strings or
objects do not count as confirmation.

## Stale plans

Every plan fingerprints normalized managed remote state with SHA-256. If that
state changed after planning, apply exits 79 without performing any saved
operation:

```text
StalePlanError: Remote state changed after this plan was generated; create a new plan
```

Generate and review a new plan. Do not edit the fingerprint to force a stale
plan through.

## Destructive operations

Ordinary plans contain only supported creates and updates. They never:

- delete an account, property, stream, key event, dimension, or metric
- archive a custom definition
- delete an unmanaged resource
- recreate an immutable conflict
- create a missing stream automatically

Configuration removal does not mean remote deletion. It simply stops managing
that declaration.

## Partial apply and rollback

Apply stops on the first failed operation. Exit 80 includes:

- successfully applied changes
- the failed change and redacted error
- unattempted remaining changes

Analytics Ops does not attempt an automatic rollback because rollback itself
can fail or overwrite concurrent operator work. Each change includes a
human-readable rollback instruction. Reconcile the remote state, then generate
a fresh plan. Never reuse the old fingerprint.

Some create rollbacks require a deliberate manual delete or archive in Google
Analytics. Those destructive actions are outside the ordinary CLI.

## Plan-file defenses

Saved plans are deterministic JSON, limited to 1 MiB, and written atomically
with mode 0600. Loading rejects:

- unknown or missing fields
- duplicate JSON keys
- incorrect scalar types
- invalid resource identities
- unknown resource payload fields
- unsupported operations
- no-op updates and immutable-field changes
- secret-shaped fields, credential-shaped text, and control characters
- resource names for another property

Workspace and adapter checks provide additional cross-property protection.
The public schema is [plan-schema-v1.json](plan-schema-v1.json).

## Credential and data boundaries

- Credentials never belong in YAML, plans, fixtures, logs, or command output.
- Report rows are never logged automatically.
- The gem has no telemetry and stores no report results.
- The gem does not inject browser analytics or manage consent.
- Production mutation credentials should not exist in a Rails web container.
- Real production IDs and exports do not belong in repository fixtures.

Use a read-only identity for routine audits and reports. Use a separately
protected edit identity only for a reviewed apply.
