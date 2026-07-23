# Live read-only smoke test

Use this guide before releasing Analytics Ops or when checking it in a real
application. The test reads Google Analytics and writes local setup files. It
never changes GA4.

## What you need

| Item | Purpose | Fake example |
| --- | --- | --- |
| Google account | Your human login for Cloud and GA4 administration | `operator@example.test` |
| GA4 account | Owns one or more GA4 properties | Account ID `100000001` |
| GA4 property | Holds the configuration and reports being tested | Property ID `123456789` |
| Google Cloud project | Owns API enablement, quota, and the service account | `example-analytics-project` |
| Service account | The non-human identity Analytics Ops uses | `analytics-ops@example-project.iam.gserviceaccount.com` |

Cloud IAM access and GA4 access are separate. The service account does not
need a broad Cloud role, but its email must be added inside GA4 Access
Management.

A normal API key cannot read private GA4 data or change GA4 settings.

## Prepare Google once

1. In the Cloud project, enable:
   - Google Analytics Admin API
   - Google Analytics Data API
2. Open [Google Cloud service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts).
3. Create **Analytics Ops Local** without broad Cloud IAM roles.
4. Create a JSON key and save it outside all repositories.
5. In GA4, open **Admin → Account access management → Add users**.
6. Add the service-account email as Viewer for read-only use or Editor for
   future reviewed applies.

No Google Cloud CLI, browser authorization, consent screen, OAuth client, or
test-user setup is used.

## Test the checkout through a real app

Temporarily point the host application's Gemfile at the local gem:

```ruby
gem "analytics_ops",
    path: "/absolute/path/to/analytics_ops",
    group: :development
```

Run `bundle install`. `bundle info analytics_ops` must show the local checkout
and version `0.2.0`.

### Preserve an existing configuration

Setup never overwrites a conflicting profile. If
`config/analytics_ops.yml` already exists, hold it safely outside the
application while testing:

```bash
analytics_smoke_backup="$(mktemp -d)"
cp config/analytics_ops.yml "$analytics_smoke_backup/original.yml"
mv config/analytics_ops.yml "$analytics_smoke_backup/held.yml"
```

Do not print the file. Production identifiers and environment conventions do
not belong in public test output.

### Connect once

Use the downloaded key without printing its contents:

```bash
bundle exec analytics-ops setup \
  --service-account /absolute/path/outside/repositories/service-account.json
```

Analytics Ops validates the key, verifies both APIs, and remembers only its
absolute path in `~/.config/analytics_ops/connection.json` with mode `0600`.
The key is not copied.

Run plain setup once more to verify the remembered connection:

```bash
bundle exec analytics-ops setup
```

### Run every read-only check

```bash
bundle exec analytics-ops version
bundle info analytics_ops
bundle exec analytics-ops doctor
bundle exec analytics-ops overview
bundle exec analytics-ops report traffic --json
bundle exec analytics-ops realtime
bundle exec analytics-ops audit
```

Empty reports are acceptable for a property with little traffic.
Authentication errors, authorization errors, malformed output, crashes, and
Google-client errors are failures.

`audit` exit status `0` means the declared state converges. Exit status `2`
means drift was found. Both are successful read-only smoke-test outcomes.

During the test:

- Never run `analytics-ops apply`.
- Do not create a plan for application.
- Never commit the service-account JSON, the connection pointer, real report
  rows, screenshots containing credentials, or temporary production IDs.
- Never paste key contents into a terminal transcript, issue, or chat.

## Restore the host app

Restore the original configuration:

```bash
mv config/analytics_ops.yml "$analytics_smoke_backup/generated.yml"
cp "$analytics_smoke_backup/original.yml" config/analytics_ops.yml
cmp "$analytics_smoke_backup/original.yml" config/analytics_ops.yml
```

After confirming the restoration, remove the temporary backup with the
operating system's normal secure cleanup process.

Keep `~/.config/analytics_ops/connection.json`, the Cloud project, and the
service account if Analytics Ops will remain in use. For a temporary-only
test, remove the connection file and revoke the downloaded key in Google
Cloud.

Keep the local path dependency until `0.2.0` is published. After publication,
replace it with:

```ruby
gem "analytics_ops", "~> 0.2", group: :development
```

Run `bundle install`, then confirm `bundle info analytics_ops` resolves
version `0.2.0` from RubyGems.

## Release gate

Do not tag while any live read-only command or local release check is failing.
Require all of the following:

- The complete live smoke test passed.
- `bin/check`, package inspection, and `git diff --check` passed.
- Documentation and changelog describe the released behavior.
- The gem worktree is clean and the release commit is on `origin/master`.
- Version and changelog both say `0.2.0`.

Then create and push the annotated tag:

```bash
git tag -a v0.2.0 -m "Release Analytics Ops 0.2.0"
git push origin v0.2.0
```

The tag workflow verifies and publishes through RubyGems Trusted Publishing.
Never run a manual `gem push` or store a RubyGems API key.
