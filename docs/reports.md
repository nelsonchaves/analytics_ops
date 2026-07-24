# Reports

Reports are read-only Data API calls. Analytics Ops validates an immutable
definition, sends an official-client request, and returns a gem-owned
`AnalyticsOps::Reports::Result`.

## Built-in recipes

All standard recipes cover the previous 28 complete days
(`28daysAgo` through `yesterday`).

| Name | What it answers | Required custom definitions |
| --- | --- | --- |
| `traffic_acquisition` | Sessions, users, and key events by channel/source/medium | None |
| `landing_pages` | Sessions, users, and key events by landing page | None |
| `calculator_completions` | Completed calculations by calculator | `customEvent:calculator_slug` |
| `shares_and_prints` | Share and print events by calculator | `customEvent:calculator_slug` |
| `related_calculator_navigation` | Related-calculator clicks by source and destination | `customEvent:calculator_slug`, `customEvent:related_calculator_slug` |
| `commercial_outbound_clicks` | Commercial outbound clicks by calculator and destination | `customEvent:calculator_slug`, `customEvent:outbound_destination` |
| `realtime_events` | Event count by event name | None |

The CLI also accepts `traffic` as an alias for `traffic_acquisition` and
`landing-pages` as an alias for `landing_pages`. Canonical names remain in
JSON and Ruby results.

The event names used by the calculator recipes are
`calculation_completed`, `result_shared`, `result_printed`,
`related_calculator_clicked`, and `commercial_outbound_clicked`.
If your site uses different names, create a custom Ruby definition.

## CLI

```bash
analytics-ops overview
analytics-ops report traffic
analytics-ops report landing-pages --json
analytics-ops report calculator_completions --csv
analytics-ops realtime
```

Change dates without writing Ruby:

```bash
analytics-ops report traffic --last 7
analytics-ops report traffic --from 2026-07-01 --to 2026-07-07
analytics-ops report traffic --last 30 --compare
```

`--last` ends at yesterday so it uses complete days. `--from` and `--to` are
inclusive and must be used together. `--compare` adds the equally long period
immediately before the requested range. Comparison rows contain Google's
automatic `dateRange` dimension with `current` or `previous`.

CSV is accepted only for `report` and `realtime`. The CSV renderer protects
headers and cells whose first meaningful character is `=`, `+`, `-`, or `@`,
including formula text hidden behind whitespace or control characters.

## Overview

`analytics-ops overview` uses one `batchRunReports` call containing five
small reports for the previous 28 complete days:

- totals for active users, sessions, and key events
- a daily trend
- traffic acquisition
- landing pages
- device categories

Each subreport has a small row limit, and Google property-quota information is
preserved when returned. Batching reduces network round trips; it does not
make the underlying report work quota-free. CSV is intentionally unavailable
for this multi-report result. Use `--json` for structured overview output.

The dimensionless totals request keeps empty rows so a brand-new property
still returns the expected metric headers.

The realtime recipe intentionally requests only `eventCount` with
`eventName`. Google does not allow `activeUsers` with that dimension. Realtime
is a short-lived event check rather than a complete user report.

## Multiple-property portfolio

```bash
analytics-ops portfolio
analytics-ops portfolio --last 7 --compare
```

Portfolio runs one small dimensionless totals report for each configured
profile and shows active users, sessions, and key events together. Each
profile uses its own saved named connection. This is read-only, but each
property still consumes normal Google Data API quota.

## Ruby

```ruby
workspace = AnalyticsOps::Workspace.load(
  "config/analytics_ops.yml",
  profile: "production"
)

result = workspace.report("traffic_acquisition")
puts result.headers
puts result.rows
puts result.metadata

overview = workspace.overview
puts overview.report("overview_totals").rows
puts overview.property_quota

ranges = AnalyticsOps::Reports::Period.resolve(last_days: 7, compare: true)
comparison = workspace.report("traffic", date_ranges: ranges)
puts comparison.rows
```

Custom immutable definition:

```ruby
definition = AnalyticsOps::Reports::Definition.new(
  name: "recent_events",
  kind: "standard",
  dimensions: ["eventName"],
  metrics: ["eventCount"],
  date_ranges: [
    { "start_date" => "7daysAgo", "end_date" => "yesterday" }
  ],
  dimension_filter: {
    "field" => "eventName",
    "match_type" => "begins_with",
    "value" => "calculator_",
    "case_sensitive" => false
  },
  order_bys: [
    { "metric" => "eventCount", "desc" => true }
  ],
  limit: 100
)

result = workspace.report(definition)
```

Definitions reject unknown fields, malformed names, duplicate dimensions or
metrics, invalid date order, filters that reference unselected fields,
non-finite numeric filters, invalid ordering, and unbounded limits. Realtime
definitions cannot use date ranges or offsets.

Dates use only `YYYY-MM-DD`, `NdaysAgo`, `yesterday`, or `today`. Absolute and
relative ranges are checked for reversed endpoints. A request may contain up
to four uniquely named ranges; comparison responses include Google's
automatic `dateRange` dimension. Numeric filters accept only finite doubles or
signed 64-bit integers.

## Result shape

`result.to_h` contains:

- `name` and `kind`
- separate dimension and metric headers
- rows keyed by header name
- Google's total `row_count`
- response metadata when present, including thresholding, sampling, time zone,
  currency, empty reason, and property quota

Metric values remain strings, matching the Data API wire contract. Generated
Google types never escape the adapter.

## GA reporting limits

A GA4 report is not an exact count of all site activity:

- It covers only traffic collected under your site's consent and tagging
  behavior. This gem does not inject tags or manage consent.
- Google may apply data thresholds, sampling, cardinality limits, modeled data,
  attribution rules, or an `(other)` row.
- Standard reports can lag behind collection; realtime is short-lived and is
  useful for verification, not accounting.
- Data API results can differ from the Analytics UI because the selected
  dimensions, metrics, filters, identity, and attribution semantics differ.
- Quotas belong to Google and can change. Analytics Ops returns quota metadata
  when Google supplies it.
- Custom dimensions must already be registered and populated. Their Data API
  names use `customEvent:parameter_name`.

Do not treat report output as billing, audit, or consent evidence. Avoid
personally identifiable or user-level dimensions, and review exported CSV/JSON
as potentially sensitive operational data.

Official references:

- [Data API reporting](https://developers.google.com/analytics/devguides/reporting/data/v1)
- [Reporting data expectations](https://developers.google.com/analytics/devguides/reporting/data/v1/data-expectations)
- [API dimensions and metrics](https://developers.google.com/analytics/devguides/reporting/data/v1/api-schema)
