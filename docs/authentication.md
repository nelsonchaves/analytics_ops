# Authentication

Analytics Ops uses Google Application Default Credentials through Google's
official Ruby clients. It does not implement or store an OAuth session.

## Local administration

For interactive local use, authenticate through the Google Cloud CLI with the
smallest required OAuth scope:

- `analytics.readonly` for doctor, discovery, audit, plan, verify, and reports.
- `analytics.edit` only when applying administrative changes.

The Google Cloud project must have the applicable Analytics API enabled, and
the authenticated identity must also have access to the target GA property.
Cloud IAM access alone does not grant GA property access.

## Automation

Prefer a dedicated service account or Workload Identity Federation. Scheduled
drift audits need only read access. Mutation credentials belong in a separately
protected release workflow, not an application web container.

## Rules

- Never commit service-account JSON.
- Never place credentials in `config/analytics_ops.yml`.
- Never place credentials in a plan file.
- Never print authorization headers, tokens, private keys, or refresh tokens.
- Rotate credentials immediately when exposure is suspected.
- Do not share one public OAuth client from the gem.

The future `analytics-ops doctor` command will verify credential discovery,
OAuth scopes, enabled APIs, property access, client compatibility, and local
clock sanity without changing remote state.

Official quickstart:
https://developers.google.com/analytics/devguides/config/admin/v1/quickstart
