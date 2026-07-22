# API support matrix

The matrix distinguishes what Analytics Ops can safely guarantee from what
Google exposes only experimentally or through the UI.

| Capability | Initial status |
| --- | --- |
| Account and property discovery | Planned, read-only |
| Data-stream discovery | Planned, read-only |
| Data retention | Planned, managed |
| Key events | Planned, managed |
| Custom dimensions | Planned, managed |
| Custom metrics | Planned, managed |
| Standard reports | Planned, read-only |
| Realtime reports | Planned, read-only |
| Enhanced Measurement | Experimental candidate |
| Google Signals | Experimental or audited candidate |
| User-provided data setting | Audit when supported |
| Ads-personalization regions | Manual until proven |
| Stream data redaction | Manual until proven |
| Consent settings | Manual or audited |
| Event create/edit rules | Post-1.0 candidate |
| Audiences | Post-1.0 candidate |
| Advertising and BigQuery links | Unsupported initially |
| Measurement Protocol secrets/events | Unsupported initially |
| Account/property deletion | Unsupported |

Statuses become `managed`, `audited`, `experimental`, `manual`, or
`unsupported` only after executable contract tests prove the behavior against
the supported official Google client versions.

Google Admin API:
https://developers.google.com/analytics/devguides/config/admin/v1

Google Data API:
https://developers.google.com/analytics/devguides/reporting/data/v1
