# Commands

The executable is `analytics-ops`. Commands that operate on one property use
`config/analytics_ops.yml` and the `production` profile unless overridden.
`setup`, `properties`, and `discover` work before that file exists.

```text
analytics-ops COMMAND [options]
```

## Fast examples

```bash
analytics-ops setup
analytics-ops overview
analytics-ops properties
analytics-ops doctor
analytics-ops audit --json
analytics-ops plan --output tmp/ga4-plan.json
analytics-ops apply tmp/ga4-plan.json
analytics-ops report landing-pages --csv
analytics-ops realtime --json
```

Only `apply` can write to Google.

## Setup

```bash
analytics-ops setup
```

Setup first tries the existing Application Default Credentials. If they are
missing or have insufficient effective Analytics scopes, it invokes Google's
official `gcloud auth application-default login` command. That command may
replace local ADC used by other development tools, so setup prints a notice
before starting it. Setup then:

1. Lists accessible accounts and properties without loading YAML.
2. Prompts with numbered choices showing account, property name, and ID.
3. Proves Admin and Data API read access.
4. Creates the smallest valid `config/analytics_ops.yml` using the
   `production` profile.
5. Prints `analytics-ops overview` as the next command.

Setup never overwrites an existing profile that targets another property. A
matching file is a successful no-op. Use an owned Desktop OAuth client when
needed:

```bash
analytics-ops setup --client-id-file path/to/desktop-oauth.json
```

For a machine that cannot open a browser:

```bash
analytics-ops setup --no-launch-browser
```

Automation never opens a browser or prompts. It requires existing ADC and an
explicit accessible property:

```bash
analytics-ops setup --property 123456789 --non-interactive --json
```

OAuth client files are credential material. They are passed only to `gcloud`;
Analytics Ops never copies them into configuration, plans, or output.

## Commands that do not change GA4

| Command | Result |
| --- | --- |
| `setup` | Authenticates if needed, selects a property, verifies both APIs, and writes local configuration; never changes Google Analytics |
| `properties` | Lists accessible account and property summaries without configuration or per-property stream calls |
| `doctor` | Checks the local file, credentials, Admin API, Data API, property access, client versions, edit visibility, and clock |
| `discover` | Lists accessible account IDs, property IDs, and stream IDs without configuration |
| `overview` | Returns five bounded reports for the previous 28 complete days in one batch request |
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
| `--json` | Shortcut for `--format json` |
| `--csv` | Shortcut for `--format csv` |
| `-o, --output PATH` | Save generated JSON; valid only with `plan` |
| `--property ID` | Select an accessible property without prompting; setup only |
| `--client-id-file PATH` | Pass an owned Desktop OAuth client to `gcloud`; setup only |
| `--no-launch-browser` | Print Google's login URL instead of opening a browser; setup only |
| `--transport grpc|rest` | Official Google-client transport |
| `--timeout SECONDS` | Finite positive API call timeout |
| `--log-level LEVEL` | Structured request metadata: `debug`, `info`, `warn`, or `error`; default `warn` |
| `--yes` | Approve every operation in a saved plan; apply only |
| `--non-interactive` | Never prompt; apply requires `--yes`, setup requires `--property` and existing ADC |

Unknown arguments, conflicting format flags, and non-finite timeouts fail
instead of being ignored. CSV is rejected for anything except report results.
CSV cells whose first meaningful character is a spreadsheet formula marker
are prefixed safely, including cells hidden behind whitespace or controls.

## Output

- Human output removes terminal control characters from remote text.
- JSON output uses stable gem-owned fields and structured errors.
- CSV contains one report's headers and rows only; it is rejected for batched
  overviews, plans, snapshots, and errors.

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
