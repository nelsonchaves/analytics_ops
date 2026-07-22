# API support matrix

This matrix describes Analytics Ops 0.1.0—not every method Google exposes.

| State | Meaning |
| --- | --- |
| Managed | Read and safely create/update within the stated limit |
| Audited | Read-only |
| Experimental | Explicitly declared, but Alpha behavior is isolated and may change |
| Manual | Reported as an operator checklist |
| Unsupported | Deliberately outside the public contract |

| Capability | State | Exact 0.1.0 behavior |
| --- | --- | --- |
| Account/property discovery | Audited | Lists accessible summaries |
| Data-stream discovery | Audited | Lists web, Android, and iOS streams |
| Web stream default URI | Managed | Updates an existing web stream |
| Stream create/delete | Unsupported | Missing streams become findings |
| Data retention | Managed | Reads and updates supported periods/reset behavior |
| Key events | Managed | Reads and creates missing events; no delete |
| Custom dimensions | Managed | Reads, creates, and updates display name/description; user ads flag where supported |
| Custom metrics | Managed | Reads, creates, and updates display name/description |
| Standard Data API reports | Audited | Immutable definitions and normalized results |
| Realtime Data API reports | Audited | Immutable definitions and normalized results |
| Batch reports | Unsupported | Use individual definitions |
| Enhanced Measurement | Experimental | Validated declaration and finding only; no mutation |
| Google Signals | Experimental | Validated declaration and finding only; no mutation |
| Consent coverage | Manual | Must be verified in tagging/consent systems |
| Ads-personalization regions | Manual | Not inferred from similarly named API fields |
| Stream data redaction | Manual | UI/API policy must be verified separately |
| User-provided data setting | Unsupported | Not read or changed |
| Event create/edit rules | Unsupported | Alpha, outside 0.1.0 |
| Audiences and expanded datasets | Unsupported | Alpha, outside 0.1.0 |
| Google Ads, AdSense, DV360, SA360 links | Unsupported | Not read or changed |
| BigQuery links | Unsupported | Not read or changed |
| Access bindings | Unsupported | Not read or changed |
| Measurement Protocol secrets/events | Unsupported | Never managed |
| Account/property/stream deletion | Unsupported | No destructive path |

Google marks some Admin API capabilities as Alpha and warns that Alpha
contracts may break. Analytics Ops never labels a capability managed merely
because a generated class exists. The supported operations above have
executable protobuf-coercion contract specs against the pinned official Ruby
clients.

References:

- [Google Analytics Admin API overview](https://developers.google.com/analytics/devguides/config/admin/v1)
- [Google Analytics Data API](https://developers.google.com/analytics/devguides/reporting/data/v1)
- [Google Analytics Admin API changelog](https://developers.google.com/analytics/devguides/config/admin/v1/changelog)
