# Saved plan format

`analytics-ops plan --output FILE` writes deterministic version-1 JSON. This
file is the only mutation input accepted by `apply`.

Example with fake identifiers:

```json
{
  "changes": [
    {
      "after": {
        "description": "Published calculator identifier",
        "disallow_ads_personalization": false,
        "display_name": "Calculator slug",
        "parameter_name": "calculator_slug",
        "scope": "event"
      },
      "api_maturity": "beta",
      "before": null,
      "operation": "create",
      "resource_identity": "event:calculator_slug",
      "resource_type": "custom_dimension",
      "reversible": true,
      "rollback": "Archive the newly created custom dimension"
    }
  ],
  "findings": [],
  "format_version": 1,
  "profile": "production",
  "property_id": "123456789",
  "snapshot_fingerprint": "sha256:0000000000000000000000000000000000000000000000000000000000000000"
}
```

Plans contain no timestamp. The same desired state and normalized snapshot
produce the same bytes.

## Top-level fields

| Field | Meaning |
| --- | --- |
| `format_version` | Exact plan contract version; currently 1 |
| `profile` | Configuration profile that produced the plan |
| `property_id` | Numeric GA4 property ID encoded as a string |
| `snapshot_fingerprint` | SHA-256 of relevant normalized remote state |
| `changes` | Sorted supported create/update operations |
| `findings` | Sorted drift, manual, warning, or experimental observations |

Every change records resource type, stable identity, operation, API maturity,
before/after payloads, reversibility, and manual rollback guidance.

## Supported version-1 changes

| Resource | Create | Update | Delete/archive |
| --- | :---: | :---: | :---: |
| Existing web data-stream default URI | No | Yes | No |
| Data retention | No | Yes | No |
| Key event | Yes | No | No |
| Custom dimension | Yes | Mutable metadata only | No |
| Custom metric | Yes | Mutable metadata only | No |

Resource names in update payloads must belong to the plan's property. Immutable
identity fields cannot change between `before` and `after`.

Currency custom-metric payloads include `restricted_metric_types` with
`cost_data`, `revenue_data`, or both. The classification is never inferred or
changed automatically.

## Findings are not operations

A finding may identify inaccessible resources, immutable conflicts, manual UI
checks, or explicitly declared experimental capabilities. Apply ignores
findings; it never converts them into mutations.

## Storage and review

Plan writes are atomic and mode 0600. Treat the file as operationally
sensitive even though credentials and report rows are forbidden:

```bash
analytics-ops plan --output tmp/ga4-plan.json
less tmp/ga4-plan.json
analytics-ops apply tmp/ga4-plan.json
```

Do not hand-edit a fingerprint or payload. Generate a new plan after any remote
or desired-state change. Partial apply also requires reconciliation and a new
plan.

The complete machine-readable contract is
[plan-schema-v1.json](plan-schema-v1.json). Runtime validation additionally
enforces cross-field identity, immutable-field, and cross-property rules.
