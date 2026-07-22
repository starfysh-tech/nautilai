# Audit

Validate this repo's Sentry setup against what the official docs actually say. Repo-only
— no Sentry MCP server needed.

**This is a discover → ground → compare loop, not a checklist.** The checks below are
written as *questions to put to the docs*, deliberately not as answers. Sentry SDK
defaults change between major versions; a frozen answer list would be wrong within a
year and confidently so. Resolve every expectation against the docs for the SDK and
major version this repo actually resolved.

## 1. Discover

Run Phase 0 from `SKILL.md` in full. Everything below compares against its output.

Additionally collect, per SDK present:

- Every option passed to init, with its literal value — and note which options are
  *absent*, since absence means the documented default applies and the default is the
  thing you must look up.
- Integrations explicitly added, and any explicitly removed or filtered out.
- Sourcemap/debug-symbol upload: bundler plugin, CLI step, CI job, auth token source.
- Sampling: error sample rate and trace sample rate (or sampler function), plus profiling
  and session-replay rates if present.
- Scrubbing hooks: `beforeSend`, `beforeSendTransaction`, `beforeBreadcrumb`,
  `ignoreErrors`, `denyUrls`, and any equivalent.
- Where the DSN and any auth token come from, per runtime, and what happens when unset.

## 2. Ground

Follow the grounding rule in `SKILL.md` — Context7 first, WebFetch of `docs.sentry.io`
second, structural-only third, and **name the tier you used in the report**.

Query per SDK and major version. Do not answer a browser-SDK question from a
server-SDK page, and do not answer a v9 question from v7 docs.

Ask the docs, at minimum:

1. **What are the documented defaults** for every option the repo did *not* set? The
   unset options are where the surprises live.
2. **What does this SDK attach by default** that the developer never passes — which
   integrations are on by default, and what does each collect?
3. **What is required for readable stack traces** in a minified build for this bundler
   and SDK version — and what is the documented symptom when it is missing?
4. **What is required for release attribution**, and how must `release`/`dist` relate to
   what was uploaded?
5. **What does the PII flag actually gate** in this version, and what remains collected
   regardless? What is only controllable server-side / at org level?
6. **What does this SDK document about capturing a non-`Error` value** — the effect on
   grouping and stack traces?
7. **What does the SDK warn against explicitly** — repeated init, init ordering, sampling
   values, deprecated options in this version?

If a claim cannot be grounded, **do not make it.** Report it as unverified.

## 3. Compare — check areas

Each area is a question against the grounded answer, not a fixed rule.

**Initialization**
- Is init present for every runtime that can throw (browser, server, edge/serverless,
  worker)? A runtime with no init is silently unmonitored.
- Is init called exactly once per runtime, early enough to catch startup errors?
- Is the DSN present at runtime in each environment? An unset DSN makes capture a
  no-op that looks identical to working instrumentation.
- Is capture gated off in development? If so, note that capture paths cannot be
  exercised locally — this is a constraint on how `instrument` verifies, not a defect.

**Stack-trace readability**
- Is the production build minified? If so, is sourcemap/debug-symbol upload configured
  and actually running in CI — not merely a plugin present but unconfigured?
- Do the identifiers the upload keys on match what the runtime reports?
- Symptom to look for: production frames showing hashed chunk names and single-letter
  functions. **High severity** — it degrades every future investigation, not one issue.

**Release attribution**
- Is `release` set, from a real build-time source rather than a hardcoded string?
- Without it, no event can be attributed to a deploy from Sentry alone. Say that
  plainly rather than implying attribution the setup cannot support.

**Sampling and cost**
- Are trace/profile/replay rates set deliberately, or left at whatever the version
  defaults to? Compare against the documented default and the repo's traffic.
- A rate of `1.0` in production is a finding worth surfacing on cost grounds unless
  volume is genuinely low.
- Is error sampling being confused with trace sampling? They are different options with
  different consequences; conflating them silently drops errors.

**PII — the highest-value area**
- What do the default-on integrations collect here, per the grounded answer? Check the
  console/breadcrumb integration and, on servers, request data (cookies, headers, query
  strings, bodies).
- Do any routes carry secrets in the URL — auth callbacks, password resets, invite or
  share links? Those URLs become event data. Cross-reference the routes against what
  the SDK attaches.
- Is there a `beforeSend` (or equivalent) scrubbing gate, and does it cover what the
  integrations attach — not just what application code passes?
- **Read the scrubber against its own stated intent.** A scrubbing hook is the one place
  a repo writes down its PII policy, usually in a header comment. Enumerate the event
  fields it actually mutates, then compare that list to what the default-on integrations
  populate. The gap between "fail closed" in the comment and the fields the code reaches
  is a finding — a scrubber that covers URLs but not breadcrumb messages, `extra`, or
  `contexts` reads as complete and is not. Check the event shape the hook is typed
  against, too: a hook typed for error events does not run on transactions.
- **Check the scrubbing gates against each other across runtimes.** Where a repo runs
  more than one SDK, a mitigation applied on one side and not the other is a strong
  signal — the team already recognized the risk, so the unprotected runtime is an
  oversight rather than an accepted trade-off. Name the protected site as evidence.
- Are user identities attached, and deliberately?
- Any ID logged that is really a **bearer capability** (Phase 0 step: possessing it
  grants access without auth)? Treat as `ask-user`, never `auto-fix`.

**Capture-site hygiene**
- Sites passing a non-`Error` value to capture — plain objects from `{ data, error }`
  clients, strings, response bodies.
- `catch` blocks that log to console and never capture, or swallow entirely.
- Failure states that return silently instead of throwing or capturing.
- Inconsistent or absent tagging versus the repo's majority convention.
- High-cardinality values used as tags.

## 4. Report

Group findings by area, ordered by severity. Every finding carries:

- `file:line` (or the config file and key) — no finding without a location.
- What the docs say, and **which grounding tier** produced that answer.
- The concrete consequence, in this repo's terms. Not "best practice says X" — say what
  breaks and when.
- A disposition: `auto-fix` / `report` / `ask-user`.

Dispositions for this workflow:
- `auto-fix` — mechanical and unambiguous, e.g. adding a missing tag to match the
  repo's own existing convention.
- `report` — anything requiring a judgment call: sampling rates, which integrations to
  disable, scrubbing policy.
- `ask-user` — anything touching PII, secrets, DSN/token handling, or cost. Never
  auto-apply these.

Open with a short state-of-play: SDKs and versions found, grounding tier used, and what
you could **not** verify. If you ran structural-only, say so at the top — a reader must
never mistake a degraded audit for a doc-grounded one.

Do not fix anything in this workflow. Hand capture-site work to `instrument`.
