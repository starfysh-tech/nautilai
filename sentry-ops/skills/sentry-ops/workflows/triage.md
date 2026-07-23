# Triage

Find what is actually broken and rank it. Ends with a shortlist, not a fix.

**Requires the Sentry MCP server.** If it is absent, say so and stop — offer `audit`
instead. Do not fabricate issue data.

Complete Phase 0 in `SKILL.md` first if you have not. You need the release-attribution
and runtime-split facts to rank anything honestly.

## 1. Scope the query

Default to unresolved issues in the production environment. Narrow with the dimensions
the user gave you; if they gave none, ask before running a broad query only when the
project is large enough that an unscoped list would be useless — otherwise just run it.

Useful narrowing: severity level, first-seen window, environment, priority, assignment,
and whether the issue is regressed. Prefer the grouped-issue search tool for "what is
broken"; use the event/aggregation tool for counts, trends, and per-event detail.

Do not run Seer here. Triage is about ranking, not root cause.

## 2. Rank

Order by impact, not by raw event count. A high-count issue hitting one bot is not the
top item. Weigh:

- **Users affected** over event volume.
- **New or regressed** over long-standing and stable — a spike that started recently is
  more actionable than steady background noise.
- **Blast radius** — does it sit on a payment, auth, or data-write path? Phase 0's map of
  the codebase tells you; the tags tell you where it lives.
- **Severity level** as recorded, but sanity-check it — a repo that captures everything
  at `error` has no signal in that field, which is itself a finding for `audit`.

## 3. Attribute honestly

If Phase 0 found no `release` configured, **you cannot attribute an issue to a deploy
from Sentry alone.** You may correlate a first-seen timestamp with `git log` — and if you
do, say that is what you did. Never present a correlation as release attribution.

If `release` *is* configured, use it, and say which release.

## 4. Report

For each shortlisted issue:

- Issue short ID and title. A short meaningless token as the title is the mis-captured
  non-`Error` signature (`investigate.md` step 3) — flag it as an instrumentation defect
  for `instrument`, and don't rank it on the token.
- First seen / last seen, event count, users affected.
- The tags that locate it in the codebase.
- One line on why it is ranked where it is.

**Completion criterion** — for each shortlisted issue you can name it, its first/last
seen, and the tags that locate it. If you cannot, do not advance it to `investigate`.

End by offering `investigate <issue-id>` on the top item. Do not start investigating.
