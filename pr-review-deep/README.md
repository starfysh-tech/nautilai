# pr-review-deep

A rigorous, evidence-based **structural code-quality** review for a branch or PR —
it hunts for whole branches, layers, or modes that can be **deleted** rather than
merely rearranged, and holds abstraction design, type/boundary contracts, and
decomposition to a high standard.

The reviewer is **ambitious in identifying** high-leverage restructurings (not just
local cleanups) and **proposes** them with cited evidence. It does **not** perform
them or expand the PR's scope — every optimization is surfaced for the author's
decision. It is a depth pass, **not a breadth audit**: it does not run tests,
security tooling, or coverage checks — reach for a multi-dimension review tool for
those.

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

## Runtimes: Claude Code and Hermes Agent

### Shared behavior

The review method is identical — implementation quality, abstraction design, type/boundary
contracts, behavior-preserving simplification, every claim cited to `file:line`. It proposes
restructurings; it never performs them.

### Claude Code

```text
/plugin install pr-review-deep@nautilai
/pr-review-deep
```

### Hermes Agent

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/pr-review-deep
```

No tap and no configuration — `hermes skills tap add` does not index this repo; install by the
identifier above.

### Runtime-specific limitations

| Capability | Claude Code | Hermes |
| --- | --- | --- |
| PR data | `mcp__github__pull_request_read`, else `gh` | **`gh` only** — no MCP tools |
| `context: fork` isolation | yes | not applicable |

**`gh` must be installed and authenticated** for the PR-fetching path in Hermes. Note that Hermes'
tool sandbox uses a truncated `PATH` (`/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin`) with no
Homebrew — so a Homebrew-installed `gh` may not be found. Reviewing a local branch diff works
without `gh`.

### Update behavior

- **Claude Code** — `/plugin update pr-review-deep@nautilai`
- **Hermes** — `hermes skills check` then `hermes skills update`. Drift is content-detected; no
  version bump needed.

## License

MIT
