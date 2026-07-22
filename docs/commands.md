# Commands

The executable is `analytics-ops`. All commands use
`config/analytics_ops.yml` and the `production` profile unless overridden.

```text
analytics-ops COMMAND [options]
```

## Fast examples

```bash
analytics-ops doctor
analytics-ops audit --format json
analytics-ops plan --output tmp/ga4-plan.json
analytics-ops apply tmp/ga4-plan.json
analytics-ops report landing_pages --format csv
analytics-ops realtime --format json
```

Only `apply` can write to Google.

## Read-only commands

| Command | Result |
| --- | --- |
| `doctor` | Checks the local file, credentials, Admin API, Data API, property access, client versions, edit visibility, and clock |
| `discover` | Lists accessible account IDs, property IDs, and stream IDs |
| `snapshot` | Prints normalized managed remote state and its fingerprint |
| `audit` | Compares desired state with a fresh snapshot; exits 2 for drift |
| `plan` | Generates the same comparison; `--output FILE` saves its exact JSON |
| `verify` | Replans and exits 0 only when managed state converges |
| `report NAME` | Runs one built-in standard Data API report |
| `realtime [NAME]` | Runs `realtime_events` by default |
| `schema` | Prints the version-1 configuration schema |

`doctor` cannot reliably inspect scopes inside an issued Google token. It
reports that check as unknown and proves effective access with real read-only
calls instead.

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

## Options

| Option | Meaning |
| --- | --- |
| `-c, --config PATH` | Configuration file |
| `-p, --profile NAME` | Profile inside the file |
| `-f, --format FORMAT` | `human`, `json`, or report-only `csv` |
| `-o, --output PATH` | Save generated JSON; valid only with `plan` |
| `--transport grpc|rest` | Official Google-client transport |
| `--timeout SECONDS` | Positive API call timeout |
| `--log-level LEVEL` | Structured request metadata: `debug`, `info`, `warn`, or `error`; default `warn` |
| `--yes` | Approve every operation in a saved plan; apply only |
| `--non-interactive` | Never prompt; apply only and requires `--yes` |

Unknown arguments and options fail instead of being ignored. CSV is rejected
for anything except report results. CSV cells beginning with spreadsheet
formula characters are prefixed safely.

## Output

- Human output is readable in a terminal.
- JSON output uses stable gem-owned fields and structured errors.
- CSV contains report headers and rows only; it never applies to plans,
  snapshots, or errors.

No command prints credentials or generated Google protobuf objects. Report
rows are emitted only because the user requested a report; they are never
logged automatically.

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

When `--format json` is selected, errors are JSON on standard error and are
suitable for automation.
