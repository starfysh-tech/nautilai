# Dependency Review

Evaluate Dependabot dependency-update PRs with **AUTO-MERGE / MERGE / SKIP / INVESTIGATE**
verdicts, each grounded in the PR diff, the dependency's changelog, and how the
package is actually used in *your* codebase. Batch every open Dependabot PR, or
evaluate one by number.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install dep-review@nautilai
```

Requires an authenticated GitHub client: the `mcp__github__*` MCP server **or** the
`gh` CLI (`gh auth login`). The skill prefers MCP and falls back to `gh`; if neither
is available it stops and tells you to install/auth `gh`. Registry metadata uses
`npm` / `pip-audit` when present and falls back to the npm/PyPI HTTP APIs otherwise.

## Use

User-invoked only (`disable-model-invocation`) — merging and closing PRs is
consequential, so the model won't auto-fire it.

```text
/dep-review                      # batch: evaluate all open Dependabot PRs
/dep-review 596                  # evaluate a single PR by number
```

Low-risk patch and minor-dev-dep bumps with passing CI **auto-merge** (no prompt);
every other merge or close is gated behind approval — see *Safety* below.

## What it does

1. **Discovery** — lists open Dependabot PRs (MCP -> `gh`), parses package,
   versions, ecosystem (from the branch prefix), and grouped status.
2. **Per-PR analysis** — for each PR, classifies the bump (patch/minor/major),
   checks CI, extracts the specific changes from the changelog, and **verifies each
   change against your code** (cited `file:line`), plus security (CVE + whether the
   vulnerable path is used) and EOL status.
3. **Verdict + report** — applies the decision matrix to land AUTO-MERGE / MERGE /
   SKIP / INVESTIGATE, handles cross-PR concerns (react/react-dom parity), and
   produces a findings-first report or batch table.
4. **Action (auto-merge + gated)** — see below.

## Safety: bounded auto-merge

Most mutating actions are gated; one narrow class auto-merges. This follows the
nautilai [finding-dispositions](../docs/conventions/finding-dispositions.md)
convention, with **one deliberate, documented exception** to the opt-in-mutation
rule (#6):

- **AUTO-MERGE** is `auto-fix` — a **patch** bump *or* a **minor dev-dependency**
  bump, with **passing CI** and **no detected breaking changes**, is squash-merged
  **without a prompt**. This restores the original skill's behavior and is the
  exception to #6 ("anything that can mutate is opt-in"). It stays safe because the
  class is narrow and CI-gated, the merge is reversible (a revert PR) and
  VCS-visible, and the skill reports exactly what it merged (PR #, package,
  from->to, commit) per the auto-fix reporting contract (#7). **CI passing is the
  consent** — a PR with failing or absent CI never auto-merges.
- **MERGE** is `ask-user` — every other merge (minor runtime deps, security fixes)
  is gated behind an `AskUserQuestion` approval.
- **SKIP** is `ask-user` — a close (and any "superseded by" comment) is recommended
  but **never performed without approval**.
- **INVESTIGATE** is `report` — surfaced with evidence, no action.

## Evidence, not reputation

Verdicts cite the specific change from the diff/changelog and back every usage claim
with a `file:line` (or "not found in <path>"). "Unverifiable" is an allowed answer;
a confident guess is not. If a changelog can't be resolved, the PR is INVESTIGATE —
not a guessed MERGE. The skill **degrades loudly**: when a metadata source is
unreachable it lowers confidence and says what it couldn't check.

## Shoals (project corrections)

When you correct a verdict — a package to always skip, a CI check that's advisory in
this repo, a pin you don't want bumped — the skill records the lesson in
`.claude/shoals/dep-review.dep-review.md` in your project and reads it back on the
next run. The file is append-only and committed by default (teammates inherit it);
`.gitignore` it if you'd rather keep it per-developer. The skill never writes outside
`.claude/shoals/`.

## Runtimes: Claude Code and Hermes Agent

### Shared behavior

Identical verdicts and identical safety rails in both: AUTO-MERGE only for low-risk patch and
minor-dev-dep bumps that pass CI; every other merge or close is gated behind approval; verdicts
are grounded in the diff and real codebase usage, not package reputation.

### Claude Code

```text
/plugin install dep-review@nautilai
/dep-review
```

### Hermes Agent

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/dep-review
```

No tap and no configuration — `hermes skills tap add` does not index this repo; install by the
identifier above.

### Runtime-specific limitations

| Capability | Claude Code | Hermes |
| --- | --- | --- |
| GitHub reads/merges | `mcp__github__*`, else `gh` | **`gh` only** — no MCP tools |
| Parallel per-PR evaluation | subagents, concurrent | **sequential** — no subagent primitive |

**`gh` is required** in Hermes and must be authenticated; the skill already falls back to it as
the baseline. Hermes' tool sandbox uses a truncated `PATH` with no Homebrew, so a
Homebrew-installed `gh` may not be found there. A large batch of Dependabot PRs is noticeably
slower without parallel evaluation.

### Update behavior

- **Claude Code** — `/plugin update dep-review@nautilai`
- **Hermes** — `hermes skills check` then `hermes skills update`. Drift is content-detected; no
  version bump needed.

## License

MIT
