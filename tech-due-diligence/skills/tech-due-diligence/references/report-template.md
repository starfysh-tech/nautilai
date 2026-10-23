# Report template

Fill the sections below in order. Owner and buyer mode share the findings work but lay the
report out for different readers: owner mode for the engineers who fix it, buyer mode for the
people who decide on a deal. Omit a section only when this template says so.

## Terms

- **Untrusted party** — anyone other than the product's operator and a user acting on their own data: the public internet, a web page the user visits, another account on the same machine, another tenant, or the author of third-party content the product imports.
- **Reachable** — an untrusted party can trigger the issue through an interface the product exposes: a network port, a route, an IPC channel, a file the product reads, or content it imports.
- **Confirmed reach** — the code you read shows the whole path from the untrusted party to the issue. **Unconfirmed reach** — part of the path is in code you did not read (for example a dependency whose source is not on disk) or depends on runtime behaviour you did not observe.
- **By default** — in the configuration the product ships or installs with, with no setting changed.
- **User action** — a step an attacker must get the user to take: opening a crafted link or file, importing or enabling the attacker's content, or changing a non-default setting. Using a core function as intended (a save, a sync, an import from a source the product ships with) is not user action.
- **During use as intended** — while the user runs a core function as intended, in the default configuration.
- **Credentials** — passwords, API keys, access tokens, private keys, and session or signing secrets.
- **Live credential** — a credential the repo shows no evidence of being revoked or rotated. A documented placeholder or test value is not a credential.
- **User data** — data the product stores or processes for its users or their customers, including personal and regulated data.
- **Destroys user data** — deletes or overwrites user data or user files with no copy that the product keeps for restore.
- **Core function** — a feature that the README, the product's own docs, or the seller's claims present as what the product does.

## Severity

Assign the highest level whose test the finding meets.

- **Critical** — either:
  - reachable by an untrusted party by default with no user action, and it exposes credentials or user data, runs commands or code the attacker chooses, or reads or changes another tenant's data; or
  - a live credential committed to the repo or its history.
- **High** — any of:
  - an impact listed under Critical that needs user action or a non-default setting;
  - it destroys user data during use as intended, or after a user action;
  - an injection, authorization, or tenant-isolation gap reachable only by a logged-in user;
  - a core function cannot work as written;
  - release or update signing keys are exposed to code or people outside the release process;
  - user data leaves the product to a place without access control or retention limits;
  - one author above 0.5 of commits in the last 12 months, in buyer mode.
- **Medium** — any of: a weakness that causes harm only together with a second failure; a process gap (no tests in CI, no review before merge, no monitoring); an exposure limited to the operator or admins; a dependency advisory with no reachable path found.
- **Low** — hygiene: no path to harm found.

**Unconfirmed reach.** Rate the finding as if the reach were confirmed. Include `inferred` in its basis and name the unconfirmed part. When that makes it Critical, add "confirm or fix" for it to the conditions to close. Otherwise put the confirmation question in the follow-up list. Uncertainty about anything other than reach (for example how users behave) does not raise the rating and does not add a condition.

Licensing and IP items are **observations** with no severity (see the areas reference).

Every Critical, High, and Medium finding states its **basis**, the kind of evidence behind it.
Combine values when parts of a finding rest on different evidence, for example `code + inferred`:

- `tool` — a scanner reported it and you confirmed it at the cited lines.
- `code` — you read it in the code, config, or git history at the cited lines.
- `inferred` — you reasoned it from indirect evidence, such as code that was not built or run. Name that evidence.

Buyer mode adds three fields to each Critical and High finding:

- **Business impact** — one category: `breach and regulatory`, `customer and revenue`, `key person`, `scalability and cost`, or `operational continuity`.
- **Deal impact** — assign the first that applies:
  - `blocker` — the finding is Critical; or it is High and it destroys user data during use as intended. Do not close until it is resolved.
  - `price` — one author above 0.5 of commits in the last 12 months; loss of control over release or signing keys (the key is exposed to code or people outside the release process, or the repo cannot show who holds it); remediation size `L`; or a seller claim the code contradicts. It affects valuation or needs an escrow or indemnity.
  - `post-close` — every other Critical or High finding. Fix it in the integration plan.
- **Remediation size** — an estimate, labelled as one: `S` (days, contained in one area), `M` (weeks, one team), or `L` (a quarter or more, or a redesign). Base it on the code the fix touches, and cite that code.

## Owner mode

````markdown
# Tech due diligence: <repo-name>

| | |
|---|---|
| Repo | `<path>` at `<git HEAD short SHA>` (`<branch>`) |
| Checkout | <"in sync with `<upstream>`", or "<N> commits behind `<upstream>`, last fetched <date>; <M> uncommitted changes"> |
| Date | <YYYY-MM-DD> |
| Mode | owner |
| Scope | full \| quick |
| Stack | <languages by size>; <frameworks>; <infra kinds> |

## Summary

<3–5 sentences: overall posture, the most important risks, and what was not assessed.>

| Area | Status | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| <one row per area that applies> | RAN \| PARTIAL: … \| NOT RUN: … | | | | |

## Findings

<Critical, High, and Medium only. Group by area. Order by severity, then by blast radius. One row per finding. Group repeats of one root cause in a single row and list every location. Put `tracked: <file:line>, <status>` in the Finding cell when a known-risk file records it.>

| # | Severity | Basis | Finding | Evidence | Fix |
|---|---|---|---|---|---|

## Low findings

<One line per Low finding: `L<n>. <area>: <finding> — <file:line>`. Omit when there are none.>

## Observations

<Licensing and IP items, one line each, with the question for counsel. Omit when there are none.>

## Fix order

<Numbered list of finding numbers in the order to fix them, with one line on each step's dependency or reason for its position.>

## Architecture, data, AI economics, and scalability

<The answers to those areas' questions, with evidence. A short paragraph per question.>

## Open questions

<The questions the code cannot answer, each addressed to its owner.>

## Method

<See Method below.>
````

## Buyer mode

The body is for a reader who decides on the deal and does not read code. Keep `file:line`
evidence out of the body; it goes in Appendix B, keyed by finding number.

Write the investment summary in business terms. It names no tools, libraries, protocols,
file paths, or audit process labels (lanes, packs, scanners). Describe each issue by what can
happen to users, data, or the business. The technical detail goes in the findings table and
the appendices.

````markdown
# Tech due diligence: <repo-name>

| | |
|---|---|
| Target | <product or company name, if known>; repo `<path>` at `<SHA>` (`<branch>`) |
| Checkout | <one sentence: the snapshot date (last fetch, or the clone date when never fetched) and whether it is current; details go in Appendix C> |
| Date | <YYYY-MM-DD> |
| Scope | full \| quick |
| Stack | <languages by size>; <frameworks>; <infra kinds> |

## Investment summary

**Verdict:** <one of: Proceed · Proceed with conditions · Do not proceed without remediation · No opinion on the product> — <one sentence on why>.

<Choose the verdict by the first rule that applies: "No opinion on the product" by the rule below; "Do not proceed without remediation" when any finding is a `blocker`; "Proceed with conditions" when the conditions to close are not empty; otherwise "Proceed".>

<Use "No opinion on the product" only when the repo does not contain the product's own code: a deployment kit, docs, an SDK, or a fork. Then still report this repo's findings, and make "audit the product repositories" the first condition to close. A product that depends on a backend, service, or shared component kept in another repo, or one that is still planned, gets a normal verdict: report the dependency as a finding and its audit as a condition to close.>

<When the snapshot is more than 30 days older than the report date, the verdict sentence says so, and "re-run this audit on the current code" is a condition to close.>

<3–4 sentences: what the technology is and the risks that drive the verdict.>

**Strengths**

<3–5 bullets, `S<n>. <strength>`: what the technology does well that a buyer can rely on, each confirmed in the code. Plain language; the evidence goes in Appendix B.>

**Top risks**

<At most 5 lines, from Critical and High findings only, ordered by deal impact then severity: `<finding #>. <the risk in one sentence> — pre-close | post-close`. Mark a risk `pre-close` only when it appears under conditions to close. The finding's row carries its impact, deal impact, and remediation size; do not repeat them here.>

**Conditions to close**

<Numbered list, each item once: each `blocker` finding; each "confirm or fix" item from an unconfirmed reach; each of the secrets, code security, dependency vulnerabilities, and infrastructure and operations areas whose status is `NOT RUN` or `PARTIAL`; and the re-run when the snapshot is stale. Licensing and IP observations never appear here.>

**Area status**

| Area | Status | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| <one row per area that applies> | RAN \| PARTIAL: … \| NOT RUN: … | | | | |

<Use plain area names. Put all stack packs, written or built, in one row named "Stack-specific checks". State each PARTIAL or NOT RUN reason by what was not checked, not by tool name.>

**Limits of this opinion**

<What the audit could not see from the repo: production data, cloud accounts and their configuration, contracts and DPAs, real usage and cost figures, runtime behaviour. Area gaps are in the area status table; do not repeat them here.>

## Findings

<Critical, High, and Medium only, grouped by business impact category. One row per root cause. No file paths in this table. The Follow-up cell names the follow-up item numbers for this finding.>

| # | Severity | Basis | Finding | Business impact | Deal impact | Remediation size (estimate) | Follow-up |
|---|---|---|---|---|---|---|---|

<One line under the table: "<N> Low hygiene items are listed in Appendix A.">

## Technology profile

<Short paragraphs, no file paths: system shape and what limits scale (from the scalability area); data map and subprocessors; AI and vendor economics, when they apply; team and key-person exposure; seller claims verdicts, when `--claims` was given.>

## Observations

<Licensing and IP items, one line each, `O<n>. <observation>`. Their questions go in the follow-up list. Omit when there are none.>

## Follow-up list

<Open with **Ask first**: at most 5 items, the ones that decide the conditions to close and the `blocker` and `price` findings. Then the rest. Every question for the seller and every document or access to request, in one numbered list. Include each item from the areas reference's request list that the repo does not already contain, and each question the code cannot answer. Tag an item with the finding or observation it serves, for example `(finding 3)` or `(O2)`. List each item once.>

## Appendix A — Low findings

<One line per Low finding: `L<n>. <area>: <finding>`.>

## Appendix B — Evidence

<Per strength and per finding number: the `file:line` evidence and the triage notes.>

## Appendix C — Method

<See Method below.>
````

## Method

Both modes end with this block:

- Inventory: `<file_source>`, <file_count> files.
- Tools run: <tool and version, per area>.
- Not run: <tool or area: reason>.
- Triage: <N> candidates reviewed, <K> kept; dropped by reason: <reason: count, …>.
- History: <commits scanned>; shallow clone: yes \| no.
- Known-risk sources read: <paths>.
- Lanes: <lane names>; Critical and High findings re-checked: <N>, changed: <N, with what changed>.

Omit a summary-table row whose area is `N/A`.

Before writing, renumber the findings 1…N in the order they appear in the report, and update
every cross-reference and appendix key to match. Every count that appears more than once
(commits, findings, candidates) must have the same value and the same basis each time; say
the basis when two bases are needed (for example, "99 non-merge commits; 135 including
merges").
