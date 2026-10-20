# Report template

Fill the sections below in order. Use the mode-specific columns. Omit a section only when this
template says so.

## Severity

- **Critical** — exploitable now, or a legal blocker: a live credential in the repo or its history, an injection reachable from a public route, AGPL code in a closed product that is distributed.
- **High** — a serious weakness that needs a fix before launch, acquisition close, or the next release.
- **Medium** — a real risk with limited exposure, or a process gap that makes high-severity issues likely.
- **Low** — hygiene.

Buyer mode adds **deal impact** to each Critical and High finding:

- `blocker` — the deal should not close until it is resolved.
- `price` — it affects valuation or needs an escrow or indemnity.
- `post-close` — fix it in the integration plan.

## Template

````markdown
# Tech due diligence: <repo-name>

| | |
|---|---|
| Repo | `<path>` at `<git HEAD short SHA>` (`<branch>`) |
| Checkout | <"in sync with `<upstream>`", or "<N> commits behind `<upstream>`, last fetched <date>; <M> uncommitted changes"> |
| Date | <YYYY-MM-DD> |
| Mode | owner \| buyer |
| Scope | full \| quick |
| Stack | <languages by size>; <frameworks>; <infra kinds> |

## Summary

<3–5 sentences: overall posture, the most important risks, and what was not assessed.>

| Area | Status | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| Secrets | RAN \| PARTIAL: … \| NOT RUN: … | | | | |
| Code security | | | | | |
| Dependencies | | | | | |
| Licensing and IP | | | | | |
| Infrastructure and operations | | | | | |
| Architecture | | | | | |
| Code quality and tests | | | | | |
| Team and process | | | | | |
| <Stack pack, e.g. Django> | | | | | |

## Findings

<Critical, High, and Medium only. Group by area. Order by severity, then by blast radius. One row per finding. Group repeats of one root cause in a single row and list every location. Put `tracked: <file:line>, <status>` in the Finding cell when a known-risk file records it.>

Owner mode:

| # | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|

Buyer mode:

| # | Severity | Deal impact | Finding | Evidence | Question for seller |
|---|---|---|---|---|---|

## Low findings

<One line per Low finding, numbered after the table: `L<n>. <area>: <finding> — <file:line>`. Omit this section when there are none.>

## Owner mode: fix order

<Numbered list of finding numbers in the order to fix them, with one line on each step's dependency or reason for its position.>

## Buyer mode: request list

<Each document or access to request, from areas.md, that the repo does not already contain.>

## Architecture

<The answers to the architecture questions, with evidence. A short paragraph per question.>

## Open questions

<The questions the code cannot answer, each addressed to its owner.>

## Method

- Inventory: `<file_source>`, <file_count> files.
- Tools run: <tool and version, per area>.
- Not run: <tool or area: reason>.
- Triage: <N> candidates reviewed, <K> kept; dropped by reason: <reason: count, …>.
- History: <commits scanned>; shallow clone: yes \| no.
- Known-risk sources read: <paths>.
- Lanes: <lane names>; Critical and High findings re-checked: <N>, changed: <N, with what changed>.
````

Omit **Owner mode: fix order** in buyer mode and **Buyer mode: request list** in owner mode.
Omit a summary-table row whose area is `N/A`.
