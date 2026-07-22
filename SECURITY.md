# Security policy

## Supported versions

Analytics Ops is pre-release. Security fixes currently target the latest
commit on `main`. A version support table will be published before 1.0.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability, exposed credential,
or reproducible credential leak.

Use GitHub's private vulnerability reporting for the repository. Include:

- The affected version or commit.
- The smallest safe reproduction.
- The expected and observed behavior.
- The potential impact.
- Whether credentials or a production property were involved.

If credentials may have been exposed, revoke or rotate them with Google before
waiting for a project response. Never include live credentials, access tokens,
visitor data, or production report exports in a report.

## Security boundaries

Analytics Ops will:

- Use Google Application Default Credentials or an explicitly injected
  credentials object.
- Redact authorization material from logs and errors.
- Keep credentials out of configuration and plan files.
- Default to read-only operations.
- Require an explicit saved plan before mutations.
- Avoid network access during library load or Rails boot.
- Publish through RubyGems Trusted Publishing without a stored API key.

Analytics Ops cannot secure a Google Cloud project, service account, GitHub
organization, CI runner, or GA property that has been granted excessive
permissions. Operators remain responsible for least-privilege access and
credential rotation.
