# Plan format

`analytics-ops plan` will produce a readable summary and a versioned JSON plan.
The JSON plan is the only input accepted by `apply`.

Conceptual structure:

```json
{
  "format_version": 1,
  "profile": "production",
  "property_id": "123456789",
  "created_at": "2026-07-22T00:00:00Z",
  "snapshot_fingerprint": "sha256:...",
  "changes": [
    {
      "resource_type": "custom_dimension",
      "resource_identity": "event:calculator_slug",
      "operation": "create",
      "api_maturity": "beta",
      "before": null,
      "after": {
        "parameter_name": "calculator_slug",
        "display_name": "Calculator slug",
        "scope": "event"
      },
      "reversible": true
    }
  ]
}
```

## Safety rules

- Plan generation is read-only.
- A plan contains no credentials or report data.
- Changes are sorted deterministically.
- Apply rejects unknown format versions.
- Apply rejects a stale snapshot fingerprint.
- Apply executes only operations present in the saved plan.
- Ordinary plans exclude destructive operations.
- Partial failure produces a reconciliation result and nonzero exit status.

The concrete JSON Schema will be committed before mutation support is enabled.
Changing the plan format requires an explicit format version and migration
documentation.
