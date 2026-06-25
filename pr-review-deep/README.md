# pr-review-deep

A rigorous, evidence-based **code quality** review for a branch or PR — focused on
implementation quality, maintainability, abstraction design, type/boundary
contracts, and behavior-preserving structural simplification.

The reviewer is **ambitious in identifying** high-leverage restructurings (not just
local cleanups) and **proposes** them with cited evidence. It does **not** perform
them or expand the PR's scope — every optimization is surfaced for the author's
decision.

## Install

```
/plugin install pr-review-deep@nautilai
```

## Use

```
/pr-review-deep
```

User-invoked only (it won't auto-fire). Reviews the current branch's changes, or a
PR when given a number/URL.

## How it behaves

- **Evidence-first** — every finding cites `file:line`, verified against the code
  before it's raised; behavior-preservation is treated as a hypothesis until proven.
- **Propose, don't perform** — describes restructurings concretely and leaves the
  decision to the author; never edits code.
- **Reads the diff with a fallback chain** — GitHub MCP → `gh` CLI → `git diff`,
  degrading loudly.
- **Severity** — `Blocking` / `Should-fix` / `Suggestion (follow-up)`.

## nautilai conventions

- **Finding dispositions** ([`docs/conventions/finding-dispositions.md`](../docs/conventions/finding-dispositions.md)):
  every finding is `report`; any proposal the user might act on is `ask-user` (never
  self-resolved); `auto-fix` is **none** by design.
- **Shoals** ([`docs/conventions/shoals.md`](../docs/conventions/shoals.md)): reads and
  appends user corrections to `<project>/.claude/shoals/pr-review-deep.pr-review-deep.md`.

## License

MIT
