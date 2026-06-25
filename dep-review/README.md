# Dependency Review

Evaluate Dependabot dependency-update PRs with **MERGE / SKIP / INVESTIGATE**
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
/dep-review --auto-merge-patch   # opt-in: let low-risk patches merge without the per-PR gate
```

## What it does

1. **Discovery** — lists open Dependabot PRs (MCP -> `gh`), parses package,
   versions, ecosystem (from the branch prefix), and grouped status.
2. **Per-PR analysis** — for each PR, classifies the bump (patch/minor/major),
   checks CI, extracts the specific changes from the changelog, and **verifies each
   change against your code** (cited `file:line`), plus security (CVE + whether the
   vulnerable path is used) and EOL status.
3. **Verdict + report** — applies the decision matrix to land MERGE / SKIP /
   INVESTIGATE, handles cross-PR concerns (react/react-dom parity), and produces a
   findings-first report or batch table.
4. **Action (gated)** — see below.

## Safety: no silent merges

Every mutating action is gated. This follows the nautilai
[finding-dispositions](../docs/conventions/finding-dispositions.md) convention:

- **INVESTIGATE** is `report` — surfaced with evidence, no action.
- **SKIP** is `ask-user` — a close (and any "superseded by" comment) is recommended
  but **never performed without approval**.
- **MERGE** is `ask-user` — every merge, *even a low-risk patch*, is gated behind an
  `AskUserQuestion` approval. A merge lands on your default branch and can trigger
  deploys, so it does not qualify as a silent auto-fix.

The one way merges skip the per-PR prompt is the **explicit opt-in flag**
`--auto-merge-patch`, passed in the invocation. Even then it covers **only** patch
bumps with passing CI and no detected breaking changes, and the skill reports
exactly what it merged (PR #, package, from->to, commit). This mirrors the "anything
that can mutate is opt-in" convention (#6) and the auto-fix reporting contract (#7).

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

## License

MIT
