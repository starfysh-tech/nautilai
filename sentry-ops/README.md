# Sentry Ops

Audit a repo’s Sentry setup against official SDK docs, triage and investigate production
issues through the Sentry MCP server, and add instrumentation behind a hard PII boundary —
including what the SDK attaches on its own. One skill, four workflows.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install sentry-ops@nautilai
```

## Use

```text
/sentry-ops                                # routes to the right workflow
/sentry-ops audit                          # validate the repo's Sentry setup
/sentry-ops triage                         # find and prioritize production issues
/sentry-ops investigate <issue-id-or-url>  # one issue → root cause at file:line
/sentry-ops instrument                     # add or fix capture sites
```

## Workflows

1. **audit** — checks the repo's Sentry configuration (init, DSN handling, integrations,
   sampling, release/environment tagging, source maps) against the official SDK docs for
   the detected platform.
2. **triage** — pulls current production issues and ranks them by what's worth acting on
   rather than by raw event count.
3. **investigate** — takes one issue and traces it to a root cause in the repo, citing
   `file:line`.
4. **instrument** — adds or repairs capture sites (`captureException`, messages,
   breadcrumbs, context) behind a PII boundary that covers both what you attach *and*
   what the SDK attaches on its own — the page URL, referrer and headers in the browser,
   and request data including cookies, query strings and bodies on the server.

## Requirements

- **Sentry MCP server — required for `triage` and `investigate`.** These workflows read
  live issue data; there is no repo-only fallback. You configure the MCP server yourself;
  this plugin does not bundle or provision it. Without it, run `audit` and `instrument`.
- **`audit` and `instrument` work without any MCP server** — they read the repo only.
- **Context7 MCP server — optional.** It grounds `audit` in official SDK docs. Without it,
  `audit` falls back to `WebFetch` against `docs.sentry.io`; if that also fails, it degrades
  to structural-only checks (config present, obvious misconfigurations) and says so
  explicitly in the report rather than implying the setup was validated against docs.

## Findings

`audit` follows the repo's [finding-dispositions](../docs/conventions/finding-dispositions.md)
convention — every finding is classified `auto-fix`, `report`, or `ask-user`, and anything
touching PII handling or sampling behavior is `ask-user`, never self-resolved.

## Runtime

**Claude Code only — not ported to Hermes Agent.** The plugin is MCP-centric and Hermes has
no equivalent Sentry MCP wiring, so a port would have nothing to call for `triage` and
`investigate`. Per [`docs/conventions/dual-runtime.md`](../docs/conventions/dual-runtime.md)
a Hermes port must be additive; there is no additive path here.

## License

MIT
