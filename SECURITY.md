# Security policy

## Supported versions

Analytics Ops is pre-release. Security fixes currently target the latest
commit on `master`. A published support table will replace this section before
1.0.

## Report privately

Do not open a public issue for a vulnerability or exposed credential. Use
GitHub's private vulnerability reporting for this repository.

Include:

- affected version or commit
- smallest safe reproduction
- expected and observed behavior
- potential impact
- whether a disposable or production property was involved

Do not include credentials, access or refresh tokens, authorization headers,
private keys, visitor data, report exports, or production plan files.

If credentials may be exposed, revoke or rotate them with Google immediately;
do not wait for a project response.

## Security guarantees

Analytics Ops:

- uses Application Default Credentials or an explicitly injected Google
  credential object
- refuses credential-shaped configuration and plan fields
- redacts common authorization material from translated errors
- performs no network I/O while requiring the gem, loading YAML, or booting
  Rails
- defaults to read-only commands
- requires a strictly validated saved plan and explicit confirmation to mutate
- rejects stale and cross-property plans
- excludes delete/archive operations from ordinary plans
- never logs report results automatically
- has no telemetry, credential store, database, or browser injection
- publishes through RubyGems Trusted Publishing without a stored API key

Plan files still describe operational configuration and are created with mode
0600. Report output may contain sensitive aggregate data and should be handled
under the operator's data policy.

## Operator responsibilities

Analytics Ops cannot secure an overprivileged Cloud project, service account,
GitHub organization, CI runner, GA property, or exported report. Use
least-privilege read credentials for routine work, isolate mutation
credentials, protect release environments, and keep production mutation
credentials out of Rails web containers.
