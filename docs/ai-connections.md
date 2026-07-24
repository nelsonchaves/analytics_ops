# ChatGPT, Codex, and Claude

Analytics Ops can let an AI read your Google Analytics data through the Model
Context Protocol (MCP). The connection is deliberately read-only.

The simple idea is:

```text
ChatGPT, Codex, or Claude
  → local Analytics Ops MCP process
  → Google Analytics read-only APIs
```

The AI can inspect and explain data. It cannot change GA4 through this
connection.

## Before connecting

Finish normal Analytics Ops setup first:

```bash
analytics-ops doctor
analytics-ops overview
```

Both should work. Then identify:

- the absolute Analytics Ops config path
- the command that starts Analytics Ops

For a Rails or Bundler application, the generated binstub is easiest:

```text
/Users/example/sites/my_app/bin/analytics-ops
```

All paths below are fake. Replace them with your own absolute paths.

## ChatGPT desktop and Codex

The ChatGPT desktop app, Codex CLI, and Codex IDE extension share local MCP
configuration on the same Codex host.

The fastest setup is:

```bash
codex mcp add analytics-ops -- \
  /Users/example/sites/my_app/bin/analytics-ops \
  mcp \
  --config /Users/example/sites/my_app/config/analytics_ops.yml
```

Then restart ChatGPT desktop or Codex. In ChatGPT desktop, you can also open
**Settings → MCP servers → Add server**, choose **STDIO**, and enter the same
command and arguments.

Check the saved server with:

```bash
codex mcp list
```

## Claude Code

Add the same local stdio server:

```bash
claude mcp add --transport stdio --scope user analytics-ops -- \
  /Users/example/sites/my_app/bin/analytics-ops \
  mcp \
  --config /Users/example/sites/my_app/config/analytics_ops.yml
```

Restart Claude Code, then use `/mcp` to check the connection.

## What you can ask

Examples:

- “Show my Analytics overview for the last 7 complete days.”
- “Compare traffic with the preceding 30 days.”
- “Which landing pages have the most sessions?”
- “Show totals across all configured properties.”
- “Audit my GA4 configuration and explain any drift.”
- “Are events arriving in realtime?”

The AI can call these tools:

- list local profiles and connection names
- list accessible GA4 properties
- run doctor
- read a normalized configuration snapshot
- audit configuration drift
- run overview, portfolio, and built-in reports
- read realtime event counts

## What the AI cannot do

The MCP server has no tools for:

- `plan`
- `apply`
- create or update
- delete or archive
- reading a credential file or key path

Every tool is marked read-only and non-destructive in MCP metadata. Starting
the server does not load a credential or contact Google. Google access begins
only after the AI calls a read tool.

If a recommended change looks useful, leave the AI connection and use the
normal human-reviewed CLI workflow:

```bash
analytics-ops plan --output tmp/ga4-plan.json
less tmp/ga4-plan.json
analytics-ops apply tmp/ga4-plan.json
```

The AI cannot perform that final command through MCP.

## Privacy boundary

The service-account JSON key, access token, authorization header, and saved
key path stay local and are never returned by an MCP tool.

Requested tool results do go to the connected AI product. Those results can
include:

- GA4 property and account names
- property IDs
- configuration values
- traffic, event, and landing-page report rows

Connect only an AI account or workspace whose data policy is appropriate for
your analytics information. Do not ask the model to repeat or store sensitive
report data unnecessarily.

## ChatGPT on the web

Local stdio is the easiest route for ChatGPT desktop, Codex, and Claude Code.
ChatGPT on the web does not read your local MCP configuration directly.

If web access is required, OpenAI's official
[Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
can forward an OpenAI-hosted tunnel to the same local stdio command over an
outbound-only connection. It requires a Platform tunnel ID, a runtime API key,
the `tunnel-client`, and the appropriate ChatGPT workspace permissions. This
is an optional advanced deployment; Analytics Ops does not need a public
server or inbound firewall port.

## Troubleshooting

- **Server starts and appears to hang:** Correct. Stdio MCP waits silently for
  protocol messages. The AI client starts and controls it.
- **Config not found:** Use an absolute `--config` path.
- **Gem not found:** Use the application's absolute `bin/analytics-ops`
  binstub, or install the gem globally.
- **No properties:** Add the exact service-account email to the correct GA4
  account or property.
- **More than one connection:** Run `analytics-ops profiles` and
  `analytics-ops use PROFILE --connection NAME`.
- **Changed MCP settings:** Restart the AI client.
- **Need to inspect protocol tools:** `codex mcp list` or Claude Code `/mcp`
  shows the configured local server.

Official client references:

- [OpenAI MCP documentation](https://learn.chatgpt.com/docs/extend/mcp)
- [OpenAI Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
- [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp)
- [Model Context Protocol transports](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
