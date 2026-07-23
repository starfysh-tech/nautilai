# Sentry Hygiene

Audit a repo’s Sentry setup against official SDK docs and instrument capture behind a hard
PII boundary — including what the SDK attaches on its own. Complements the official Sentry
plugin, which owns SDK setup and issue-fixing. One skill, two workflows.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Relationship to the official Sentry plugin

This plugin is intentionally narrow. Sentry ships an official
[`sentry`](https://github.com/getsentry/sentry-for-ai) plugin that already does — first
party, and better — the two biggest jobs:

- **SDK setup** in ~20 languages/frameworks (`sentry-sdk-setup`), plus feature setup,
  alerts, and SDK upgrades.
- **Finding and fixing production issues** through a bundled Sentry MCP server
  (`sentry-fix-issues`, `sentry-code-review`).

`sentry-hygiene` does **not** compete with either. It covers the two gaps that plugin leaves:

- **`audit`** — validate an *existing* setup against current docs. The official plugin
  installs Sentry; it has no equivalent for confirming an install is correct (sourcemaps
  actually uploading, sampling sane, scrubbing complete).
- **`instrument`** — the **inbound-PII gate**: what the SDK attaches to events on its own.
  The official plugin's PII model is about data coming *out* of Sentry (treat event data
  as untrusted, don't leak it into code); this is the complementary *inbound* half.

Both workflows are **repo-only** — they read code and docs, never the Sentry MCP. For
anything about live issues, use the official plugin.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install sentry-hygiene@nautilai
```

## Use

```text
/sentry-hygiene             # runs discovery, then recommends audit or instrument
/sentry-hygiene audit       # validate this repo's Sentry setup against official SDK docs
/sentry-hygiene instrument  # add or fix capture sites behind the PII boundary
```

## Workflows

1. **audit** — checks the repo's Sentry configuration (init, DSN handling, integrations,
   sampling, release/environment tagging, sourcemaps, scrubbing coverage) against the
   official SDK docs for the detected platform and version, grounded at runtime rather
   than from a frozen checklist. Reports findings with dispositions; fixes nothing itself.
2. **instrument** — adds or repairs capture sites (`captureException`, messages,
   breadcrumbs, context) behind a PII boundary that covers both what you attach *and*
   what the SDK attaches on its own — the page URL, referrer and headers in the browser,
   and request data including cookies, query strings and bodies on the server.

## Requirements

- **No Sentry MCP server needed.** Both workflows are repo-only — they read your code and
  the official docs. (The official Sentry plugin is what bundles and uses the MCP.)
- **Context7 MCP server — optional.** It grounds `audit` in official SDK docs. Without it,
  `audit` falls back to `WebFetch` against `docs.sentry.io`; if that also fails, it degrades
  to structural-only checks (config present, obvious misconfigurations) and says so
  explicitly in the report rather than implying the setup was validated against docs.

## Findings

`audit` follows the repo's [finding-dispositions](../docs/conventions/finding-dispositions.md)
convention — every finding is classified `auto-fix`, `report`, or `ask-user`, and anything
touching PII handling or sampling behavior is `ask-user`, never self-resolved.

## Runtime

**Claude Code only — not currently ported to Hermes Agent.** Porting to Hermes must be
additive per [`docs/conventions/dual-runtime.md`](../docs/conventions/dual-runtime.md), and
the port hasn't been done. Nothing in the two repo-only workflows is Claude-specific, so a
future Hermes port is possible; it simply isn't wired yet.

## License

MIT
