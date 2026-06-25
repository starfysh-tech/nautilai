---
name: dep-review
description: Evaluate Dependabot dependency-update PRs with AUTO-MERGE / MERGE / SKIP / INVESTIGATE verdicts, each grounded in the PR diff, changelog, and actual codebase usage. Batch all open Dependabot PRs or evaluate one by number. Low-risk patch and minor-dev-dep bumps that pass CI auto-merge; other merges and closes gate behind approval. Use when the user runs /dep-review, asks to triage Dependabot PRs, review dependency bumps, or decide which dependency updates are safe to merge.
allowed-tools: Read, Grep, Glob, Bash(gh:*), Bash(git:*), Bash(npm:*), Bash(pip:*), Bash(pip-audit:*), Bash(curl:*), Bash(jq:*), WebFetch, AskUserQuestion, mcp__github__pull_request_read, mcp__github__list_pull_requests, mcp__github__merge_pull_request, mcp__github__add_issue_comment, mcp__github__update_pull_request, mcp__github__get_file_contents
disable-model-invocation: true
---

# Dependency Review

Evaluate Dependabot dependency-update PRs and produce a structured verdict per PR —
**AUTO-MERGE / MERGE / SKIP / INVESTIGATE** — grounded in the PR diff, the
dependency's changelog, and how the package is actually used in *this* codebase.
Batch every open Dependabot PR, or evaluate a single PR by number.

This skill is **user-invoked only** (`disable-model-invocation`): merging and
closing PRs is consequential, so the model should not auto-fire this workflow.

## Usage

```text
/dep-review          # batch: evaluate all open Dependabot PRs
/dep-review 596      # evaluate a single PR by number
```

## Tooling — graceful degradation (fail-open)

Pick the best-available tool at each step; never hard-fail because a *preferred*
one is missing. State which fallback you took.

- **GitHub reads / merges / comments:** prefer the `mcp__github__*` tools if
  available; otherwise fall back to the **`gh` CLI** (the baseline requirement) —
  `gh pr list`, `gh pr view`, `gh pr checks`, `gh pr merge`, `gh pr close`,
  `gh api`. If neither MCP nor an authenticated `gh` is available, **stop** and
  tell the user to install/auth `gh` — this is the one genuinely required input.
- **Ecosystem metadata** (deprecation, publish time, audit): use the registry CLI
  if present (`npm`, `pip-audit`); if it's absent, fall back to the registry HTTP
  API (`curl https://pypi.org/pypi/<pkg>/json`, `https://registry.npmjs.org/<pkg>`).
  If a metadata source is unreachable, **degrade loudly** — lower the confidence
  and say what you couldn't check, don't silently assume.
- **Changelog:** PR body → GitHub release notes (`gh api .../releases/tags/...` or
  WebFetch the repo CHANGELOG) → registry version list. If none resolve, the
  change is **INVESTIGATE** (can't verify breaking changes), not a guessed MERGE.

## Grounding rule — cite evidence, never assume

Every verdict must rest on observed evidence, not on the package's reputation or
a guess about its API:

- Quote the **specific change** from the diff/changelog (what API/behavior moved),
  not just "it's a minor bump."
- Back every usage claim with a **`file:line`** (or "not found in <searched path>").
  "Unverifiable" is an allowed answer; a confident guess is not.
- If live registry/changelog data contradicts the PR body, trust the live source
  and say so.
- When confidence is **Low**, say so explicitly and name what would raise it.

## Workflow

Run in order. After Phase 1 and Phase 2, **pause** if the user may want to review
before any gated action. The skill auto-merges only the narrow AUTO-MERGE class
(patch / minor-dev-dep + passing CI); every other merge waits for approval.

### Phase 1 — Discovery

**Parse input:** no args → batch mode (all open Dependabot PRs); a single number
→ single-PR mode.

**List open Dependabot PRs** (prefer MCP `list_pull_requests`, else `gh`):

```bash
gh pr list --author "app/dependabot" --state open \
  --json number,title,headRefName,labels
```

**Extract per PR:** number, package name(s), from/to versions, ecosystem (detect
from the branch prefix — `dependabot/npm_and_yarn/...`, `dependabot/pip/...`,
`dependabot/github_actions/...`, etc.), and grouped status (a dependency table in
the PR body means multiple packages in one PR).

> **No hardcoded paths or repo names.** Detect the ecosystem source directory from
> the repo (`package.json` location for npm; `pyproject.toml`/`requirements*.txt`
> for pip) rather than assuming a fixed layout.

### Phase 2 — Per-PR analysis

For each PR, gather evidence across these dimensions and record the supporting
`file:line` / changelog quote for each. See
[`references/analysis-steps.md`](references/analysis-steps.md) for the full
per-PR procedure (steps 2a–2g) and the structured return format.

1. **Classify** the change: patch / minor / major (grouped PR → highest severity
   across all packages).
2. **CI status** — `gh pr checks <n>`: passing / failing / pending.
3. **Extract specific changes** from the changelog (what moved, how, migration
   needed).
4. **Verify each change against the codebase** — search for the changed
   API/import/symbol; classify impact NONE / LOW / MEDIUM / HIGH with evidence.
5. **Security** — CVEs in labels/body; cross-reference whether the vulnerable
   path is actually used.
6. **EOL status** — deprecated, yanked, or no releases in a long time.

See [`references/decision-matrix.md`](references/decision-matrix.md) for the
ecosystem-specific commands, the package→import name caveats, and the edge cases
(grouped PRs, `@types/*`, React/React-DOM parity, pre-release, transitive deps,
yanked releases, superseding PRs).
[`references/edge-cases.md`](references/edge-cases.md) is the at-a-glance summary of
the recurring ones if you just need the verdict mapping.

### Phase 3 — Verdict application

Apply the [`references/decision-matrix.md`](references/decision-matrix.md) rules to
each PR's evidence to land a final verdict, then handle cross-PR concerns (e.g.
React/React-DOM must move together). Build the report — see
[`references/output-format.md`](references/output-format.md).

### Phase 4 — Action execution (auto-merge + gated)

See **Finding dispositions** below for which verdicts may act and how. In short:
INVESTIGATE/SKIP are report-only here; an **AUTO-MERGE** verdict (narrow, CI-gated)
merges without a prompt; every other MERGE and every PR close goes through an
`AskUserQuestion` approval gate. Batch the gated actions into a single approval
prompt rather than asking per-PR where you can.

## Finding dispositions

Per the nautilai [finding-dispositions](https://github.com/starfysh-tech/nautilai/blob/main/docs/conventions/finding-dispositions.md)
convention, each PR verdict maps to a disposition by what this skill is *allowed to
do about it*:

| Verdict | Disposition | What the skill does |
|---|---|---|
| **AUTO-MERGE** | `auto-fix` | Merge **without a prompt** — *only* a **patch** bump or a **minor dev-dependency** bump, each with **passing CI** and **no detected breaking changes**. Squash-merge, then report exactly what landed. |
| **MERGE** | `ask-user` | Recommend merging; **gate behind an `AskUserQuestion` approval** — minor runtime deps, security fixes, anything not in the AUTO-MERGE class. |
| **INVESTIGATE** | `report` | Surface findings + cited evidence; take no action. |
| **SKIP** | `ask-user` | Recommend closing; **never close on its own** — gate the close (and any "superseded by" comment) behind approval. |

**AUTO-MERGE is a deliberate, narrow exception to the opt-in-mutation convention
(#6)** — see the plugin README. It restores the original skill's behavior: a
low-risk dependency bump that *passes CI* is merged automatically. The exception is
bounded and safe:

- It covers **only** patch / minor-dev-dep bumps with **passing CI** and **no
  detected breaking changes**. Anything else — runtime minor, major, security fix,
  pre-release, grouped-with-breaking — falls to **MERGE** (gated) or INVESTIGATE.
- It satisfies the `auto-fix` safety contract: the merge is **reversible** (a revert
  PR) and **VCS-visible** (`gh pr merge --squash` lands a commit), and you **report
  exactly what was merged** (PR #, package, from→to, merge commit).
- CI passing is the consent: never AUTO-MERGE a PR with failing/absent CI.

Never self-resolve an **`ask-user`** verdict (MERGE-gated / SKIP) — not even to "skip
a trivial PR." When in doubt between AUTO-MERGE and gating, **gate**. Under-acting is
recoverable; a wrong silent merge or close is not.

## Engagement style

- **Findings-first.** Lead with the verdict; don't bury it in analysis. Omit clean
  dimensions — no "I checked X and it was fine" padding.
- For **MERGE**: keep it brief — the cited "why it's safe" evidence and the version
  delta, nothing more.
- For **INVESTIGATE**: list the specific changes needing human judgment (with
  `file:line`), not the whole changelog.
- For **SKIP**: one clear reason, not an exhaustive list.
- Don't editorialize on a dependency's quality or maintenance unless it's
  load-bearing for the verdict.
- State confidence; when **Low**, say what would raise it.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/dep-review.dep-review.md` from the
project root if it exists, and honor every entry as a constraint (e.g. "always SKIP
bumps to package X — it's pinned for a reason", "this repo's CI 'lint' check is
advisory, don't treat it as failing").

When the user corrects your behavior — a verdict you got wrong, a package you
should always skip/merge, how you read this repo's CI — append a shoal to that file
(creating `.claude/shoals/` if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger**. Capture only explicit behavioral
corrections, not passing preferences. Never write outside `.claude/shoals/`.
Mention the capture in one line; don't narrate it.
See [shoals convention](https://github.com/starfysh-tech/nautilai/blob/main/docs/conventions/shoals.md).

## Files

- [`references/analysis-steps.md`](references/analysis-steps.md) — per-PR analysis steps 2a–2g + the structured return format.
- [`references/decision-matrix.md`](references/decision-matrix.md) — decision rules, ecosystem commands, package→import caveats, edge cases, confidence levels.
- [`references/edge-cases.md`](references/edge-cases.md) — quick-reference summary of the recurring edge cases (grouped PRs, `@types/*`, React/React-DOM parity, pre-release, transitive deps). Full detail lives in `decision-matrix.md`.
- [`references/output-format.md`](references/output-format.md) — single-PR report format + batch summary table.
- [`references/example-report.md`](references/example-report.md) — worked single-PR and batch examples.
