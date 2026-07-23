---
name: sentry-ops
description: "Audit a repo's Sentry setup against official SDK docs, triage and investigate production issues through the Sentry MCP server, and add instrumentation behind a hard PII boundary. Use when the user runs /sentry-ops, mentions Sentry, names a Sentry issue ID or URL, asks why something is failing in production, asks whether Sentry is set up correctly, or asks to add error tracking to a code path. Subcommands: audit | triage | investigate | instrument."
argument-hint: "[audit|triage|investigate|instrument] [issue-id-or-url]"
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob, ToolSearch, WebFetch, AskUserQuestion]
---

# Sentry Ops

Four workflows. Read exactly one per run.

## Dispatch

Take the first whitespace-delimited token of `$ARGUMENTS` as the subcommand; the
remaining words are context to pass into the workflow, not part of the dispatch.

- First token is `audit|triage|investigate|instrument` → read
  `${CLAUDE_PLUGIN_ROOT}/skills/sentry-ops/workflows/<token>.md` and follow it exactly.
- `$ARGUMENTS` is empty → run **Phase 0** below, then recommend a subcommand and stop.
  Do not pick one silently.
- `$ARGUMENTS` looks like a Sentry issue ID or a `sentry.io` URL with no subcommand →
  `investigate`, passing it as context.
- Anything else → say the subcommand wasn't recognized and list the four. Do not guess.

`${CLAUDE_PLUGIN_ROOT}` is resolved to an absolute path by the runtime. Never substitute
it yourself and never fall back to a relative path; if it did not resolve, stop and say so.

Run all commands from the repo root.

## Phase 0 — discover before you assert

**Every workflow starts here.** This plugin ships no assumptions about how *this* repo
uses Sentry. Establish the facts first; they change what the other workflows are allowed
to claim.

Find and read, in this order:

1. **SDK and version** — the Sentry package(s) and resolved versions from the lockfile,
   not the manifest range. Multiple SDKs (browser + server + edge) are common; find all.
2. **Init sites** — every `Sentry.init` / `sentry_sdk.init` call. One read of these
   sites yields items 2, 4, and 7; gather them together. Note the file, the options
   passed, and whether init is gated (`enabled:`, an env check, a build flag). More than
   one init for the same runtime is a finding, not a variant.
3. **Stack-trace readability** — is the production build minified, and does anything
   upload sourcemaps (bundler plugin, `sentry-cli`, debug IDs)? This decides whether
   `investigate` can navigate by stack frame or must navigate by tag.
4. **Release attribution** — is `release` (and `dist`) set, from what source? If not,
   events cannot be attributed to a deploy from Sentry alone.
5. **Existing capture conventions** — sample the existing `captureException` /
   `capture_exception` call sites. What tags and context does this repo already use?
   **Read them and follow them.** Do not impose a convention from elsewhere.
6. **Existing error-wrapping helper** — does the repo already normalize non-`Error`
   values before capture? If one exists, use it; do not hand-roll a second.
7. **Runtime split** — separate DSNs per runtime (frontend vs backend vs edge/serverless)
   and where each comes from. A DSN that is unset at runtime makes capture a silent no-op.

State what you found before acting on it. If a fact is unavailable, say so — an
unverified assumption about a capture path is how PII leaks get introduced.

## Sentry MCP — session facts

`triage` and `investigate` need a user-configured Sentry MCP server. `audit` and
`instrument` do not; they are repo-only.

If Sentry MCP tools are not present, say so plainly and offer `audit` or `instrument`
instead. Do not simulate issue data, and do not fetch from the Sentry web API as a
substitute unless the user explicitly sets that up.

**Detect the scope; do not assume it.** A Sentry MCP endpoint URL may bake in the org
and project (`.../mcp/<org>/<project>`) or may not. When it does, the tool schemas omit
`organizationSlug` even though the published docs and examples show it — passing it
fails. When it does not, it is required.

> **Trust the live tool schema over any documented example.** Read the schema you were
> actually given. If a call fails on an argument that the docs show, the docs are
> describing a differently-scoped endpoint.

Not every Sentry tool is directly callable. A small set is exposed directly
(typically issue search, event search, resource fetch, issue update, Seer analysis);
the rest — alert rules, DSNs, monitors, release details, full issue details — route
through a generic execute/proxy tool. When you do not know a tool's name or its
arguments, **search the tool catalog first** rather than guessing at a call.

`analyze_issue_with_seer` takes minutes. It is **not** a default follow-up to fetching
issue details. Run it only when the user asks, or when the issue details genuinely do
not reveal the cause and you say why first.

## Grounding rule — for `audit` especially

Do not assert a Sentry "best practice" from memory. The SDKs change faster than any
checklist this plugin could freeze.

Ground claims against official docs, in this order, and **name which tier you used** in
the report:

1. **Context7 MCP** (optional dependency) — `/websites/sentry_io_platforms` for
   SDK-specific configuration, `/getsentry/sentry-docs` for product concepts
   (sourcemaps, releases, data scrubbing, quotas). Query for the SDK **and major
   version** the repo actually resolved in Phase 0.
2. **WebFetch of `docs.sentry.io`** — when Context7 is unavailable.
3. **Structural checks only** — when neither is reachable. Report only what is
   observably true of the repo (init present, sourcemaps configured or not, sampling
   value present or not) and **state in the report that doc-grounded checks were
   skipped**. Never silently downgrade.

## PII boundary — applies to every workflow

Two separate problems. Most projects police the first and get bitten by the second.

**1. What you put in.** No emails, names, tokens, passwords, or raw request bodies in
tags, context, or messages. IDs, statuses, and counts are usually fine — with one
caveat worth checking per repo: **some IDs are bearer capabilities.** If possessing an
ID is sufficient to fetch the underlying record without auth (share links, unguessable
public URLs, invite tokens), it is a credential, not an identifier. Anyone with Sentry
read access can replay it. Identify these in Phase 0 before logging any ID.

**2. What the SDK attaches that you never passed.** This is the part that leaks. Default
integrations enrich events on their own, without any capture call. The specifics below
hold in current SDKs and are what to verify against docs — not a frozen list to trust:

- **Browser: the page URL.** `httpContextIntegration` is on by default and attaches the
  request URL, user-agent, referrer, and headers to every event.
- **Browser: breadcrumbs.** `breadcrumbsIntegration` is on by default and captures
  console calls, DOM events, `fetch`, History API navigations, and XHR — including their
  URLs. Build-time stripping of `console.log` does not cover `console.error`/`warn`.
- **Server: request data.** The request-data integration captures cookies, headers,
  query strings, request bodies, and URLs by default.
- **URLs are payloads.** A query string or path segment carrying an auth code, reset
  token, or share ID becomes event data on every capture from that page or route — on
  the client via HTTP context, on the server via request data.

`sendDefaultPii` defaults to `false` and gates some of this — notably the user's IP
address. **Do not assume it gates everything**, and do not assume any single option
disables server-side enrichment: what a given SDK and major version collects by default
changes between releases, and some scrubbing is an org-level setting rather than an
`init` option.

`audit` resolves the specifics against current docs for the SDK and version this repo
actually resolved. Never state the boundary from memory — verify it, then cite it.

Before adding any capture, ask what the SDK will attach alongside it — not just what
you passed.

## Findings

Report findings per the marketplace's finding-dispositions convention:
`auto-fix` (mechanical and safe), `report` (needs a human judgment call), `ask-user`
(destructive, ambiguous, or policy-bearing). Never auto-apply a `report` or `ask-user`
finding. Cite `file:line` for every finding that points at code.
