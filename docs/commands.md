# Commands

The executable is `analytics-ops`. Commands that operate on one property use
`config/analytics_ops.yml` and the `production` profile unless overridden.
`setup`, `properties`, and `discover` work before that file exists.

```text
analytics-ops COMMAND [options]
```

## Fast examples

```bash
analytics-ops setup --service-account /absolute/path/to/service-account.json
analytics-ops overview
analytics-ops overview --last 7 --compare
analytics-ops portfolio
analytics-ops properties
analytics-ops doctor
analytics-ops audit --json
analytics-ops plan --output tmp/ga4-plan.json
analytics-ops apply tmp/ga4-plan.json
analytics-ops report landing-pages --csv
analytics-ops realtime --json
analytics-ops profiles
analytics-ops mcp --config /absolute/path/to/config/analytics_ops.yml
```

Only `apply` can write to Google.

## Setup

```bash
analytics-ops setup --service-account /absolute/path/to/service-account.json
```

Analytics Ops supports only service-account authentication. On the first run,
pass the downloaded JSON key explicitly. Setup then:

1. Validates that the file is a Google service-account key.
2. Lists accessible accounts and properties without loading YAML.
3. Prompts with numbered choices showing account, property name, and ID.
4. Proves Admin and Data API read access.
5. Creates the smallest valid `config/analytics_ops.yml` using the
   `production` profile.
6. Stores a named connection containing only the key's absolute path in
   `~/.config/analytics_ops/connection.json` with mode `0600`.
7. Prints `analytics-ops overview` as the next command.

Setup never overwrites an existing profile that targets another property. A
matching file is a successful no-op. A missing profile is appended safely
without removing existing settings or comments. The untouched Rails generator
placeholder is filled automatically. The key is never copied into a project
or printed.

Later setup runs use the remembered path:

```bash
analytics-ops setup
```

Automation uses the same single route with an explicit property:

```bash
analytics-ops setup \
  --service-account /secure/path/service-account.json \
  --property 123456789 \
  --non-interactive \
  --json
```

The CLI never consults `gcloud`, browser login, Application Default
Credentials, `GOOGLE_APPLICATION_CREDENTIALS`, or API keys.

## Profiles and connections

Use a profile for each GA4 property and a named connection for each Google
service account:

```bash
analytics-ops setup \
  --profile client_b \
  --connection client_b \
  --service-account /secure/client-b/service-account.json

analytics-ops profiles
analytics-ops connections
analytics-ops use client_b
```

`use` remembers the selected profile and its connection for this configuration
file. Later commands use it automatically. Add `--profile NAME` or
`--connection NAME` for a one-command override.

## Commands that do not change GA4

| Command | Result |
| --- | --- |
| `setup` | Loads the service account, selects a property, verifies both APIs, and writes local configuration; never changes Google Analytics |
| `properties` | Lists accessible account and property summaries without configuration or per-property stream calls |
| `doctor` | Checks the local file, credentials, Admin API, Data API, property access, client versions, edit visibility, and clock |
| `discover` | Lists accessible account IDs, property IDs, and stream IDs without configuration |
| `overview` | Returns five bounded reports for the previous 28 complete days in one batch request |
| `portfolio` | Returns users, sessions, and key events across every configured property |
| `snapshot` | Prints normalized managed remote state and its fingerprint |
| `audit` | Compares desired state with a fresh snapshot; exits 2 for drift |
| `plan` | Generates the same comparison; `--output FILE` saves its exact JSON |
| `verify` | Replans and exits 0 only when managed state converges |
| `report NAME` | Runs one built-in standard Data API report |
| `realtime [NAME]` | Runs `realtime_events` by default |
| `profiles` | Lists local profiles, property IDs, and connection names without contacting Google |
| `connections` | Lists connection names and key availability without printing paths |
| `use NAME` | Selects one local profile/connection without contacting Google |
| `mcp` | Starts the strictly read-only local AI tool server |
| `schema` | Prints the version-1 configuration schema |

`doctor` uses the read-only Analytics scope and proves effective access with
small real calls to both APIs.

## Apply

```bash
analytics-ops apply PLAN_FILE
```

Interactive apply:

1. Loads and strictly validates the saved plan.
2. Prints every saved before value, after value, and rollback instruction.
3. Requires the exact response `yes`.
4. Refreshes the remote snapshot.
5. Rejects the plan if its fingerprint is stale.
6. Executes only its saved create/update operations, stopping on first failure.

Automation must be explicit:

```bash
analytics-ops apply tmp/ga4-plan.json --non-interactive --yes --format json
```

`--non-interactive` without `--yes` is an error. There is no command that
plans and applies in one step.

JSON apply is deliberately non-interactive. It requires both flags so a prompt
can never corrupt the JSON stream:

```bash
analytics-ops apply tmp/ga4-plan.json --json --non-interactive --yes
```

## Report dates and comparisons

The default remains the previous 28 complete days. Override it with one easy
form:

```bash
analytics-ops report traffic --last 7
analytics-ops report traffic --from 2026-07-01 --to 2026-07-07
analytics-ops overview --last 30 --compare
analytics-ops portfolio --last 30 --compare
```

`--compare` adds an equally long preceding period. Google returns a
`dateRange` column labeled `current` or `previous`. Date options work only
with `report`, `overview`, and `portfolio`; realtime reports have no date
range. `--last` accepts 1 through 1,825 complete days.

## Options

| Option | Meaning |
| --- | --- |
| `-c, --config PATH` | Configuration file |
| `-p, --profile NAME` | Profile inside the file |
| `--connection NAME` | Named saved Google connection |
| `-f, --format FORMAT` | `human`, `json`, or report-only `csv` |
| `--json` | Shortcut for `--format json` |
| `--csv` | Shortcut for `--format csv` |
| `--last DAYS` | Previous complete days for report, overview, or portfolio |
| `--from DATE` | Inclusive `YYYY-MM-DD` start; requires `--to` |
| `--to DATE` | Inclusive `YYYY-MM-DD` end; requires `--from` |
| `--compare` | Include the equally long preceding period |
| `-o, --output PATH` | Save generated JSON; valid only with `plan` |
| `--property ID` | Select an accessible property without prompting; setup only |
| `--service-account PATH` | Connect a Google service-account JSON key; setup only |
| `--transport grpc|rest` | Official Google-client transport |
| `--timeout SECONDS` | Finite positive API call timeout |
| `--log-level LEVEL` | Structured request metadata: `debug`, `info`, `warn`, or `error`; default `warn` |
| `--yes` | Approve every operation in a saved plan; apply only |
| `--non-interactive` | Never prompt; apply requires `--yes`, setup requires `--property` |

Unknown arguments, conflicting format flags, and non-finite timeouts fail
instead of being ignored. CSV is rejected for anything except report results.
CSV cells whose first meaningful character is a spreadsheet formula marker
are prefixed safely, including cells hidden behind whitespace or controls.

## Output

- Human output removes terminal control characters from remote text.
- Long human table cells keep both their beginning and ending, with an
  ellipsis in the middle so similar URLs remain distinguishable.
- Interactive apply prints complete redacted before/after values without the
  ordinary message-length cap.
- JSON output uses stable gem-owned fields and structured errors.
- CSV contains one report's headers and rows only; it is rejected for batched
  overviews, plans, snapshots, and errors.

No command prints credentials or generated Google protobuf objects. Report
rows are emitted only because the user requested a report; they are never
logged automatically.

The MCP command writes protocol messages to standard output and rejects human,
JSON, or CSV formatting flags. Its advertised tools are all annotated
read-only and include no plan or apply operation.

## Exit statuses

| Status | Meaning |
| ---: | --- |
| 0 | Success |
| 2 | Drift found or verification not converged |
| 64 | Invalid command, option, argument, or missing confirmation |
| 65 | Invalid configuration, plan, or ambiguous identity |
| 66 | Authentication failure |
| 69 | Invalid Google request or other remote API failure |
| 74 | Timeout |
| 75 | Quota or rate limit |
| 77 | Google Analytics permission failure |
| 78 | Unsupported installed-client capability |
| 79 | Stale saved plan |
| 80 | Partial apply; inspect reconciliation output |
| 130 | Interrupted by the user; no Ruby backtrace is printed |

When `--format json` is selected, errors are JSON on standard error and are
suitable for automation.
