# GitHub Issue Auditor

Audit a GitHub repository's open issues for cleanup opportunities — fuzzy-matched
duplicate titles, orphaned sub-issues whose parent is closed, unlabeled or stale
items, and labels inconsistent with the repo's own convention. Inspection is
read-only; any change to the tracker (close, relabel, comment) is opt-in behind an
approval gate.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install github-issue-auditor@nautilai
```

Requires the GitHub CLI (`gh`) authenticated (`gh auth status`), or the GitHub MCP
server configured. It reads via whichever is available.

## Use

This skill is **user-invoked** (`disable-model-invocation: true`) — it won't
auto-fire, because it can mutate your tracker.

```text
/github-issue-auditor                       # audit the current repo
/github-issue-auditor owner/repo            # audit a specific repo
/github-issue-auditor --stale-days 60       # custom stale threshold
/github-issue-auditor --similarity 0.85     # stricter duplicate matching
```

## What it does

1. **Detects the repo's label taxonomy** — it does not assume label names. It
   lists the repo's labels and groups them (status / type / priority / area), so
   "duplicate", "backlog", and "needs-triage" mean whatever *this* repo calls them.
2. **Audits (read-only)** into categories: marked duplicates, unlabeled, stale,
   orphaned sub-issues (native links preferred, body references as fallback), and
   label inconsistencies. Fuzzy duplicate detection uses normalized Levenshtein
   title similarity (default threshold 0.75).
3. **Reports findings-first** — leads with prioritized findings citing issue
   numbers, omits clean categories, then stops at a review checkpoint.
4. **Applies changes only when asked, behind a gate** — closing duplicates,
   relabeling, or commenting happens only after you approve a task list via
   `AskUserQuestion`. GitHub records every change under your account and
   close/label are reversible.

## Conventions

Follows the nautilai [house conventions](../docs/conventions/README.md):

- **Finding dispositions (#1):** every tracker mutation is `ask-user` behind the
  Phase 4 gate; the audit itself is `report`; there is no default `auto-fix`.
- **Graceful degradation (#3):** GitHub MCP → `gh` CLI → stop. Degrades loudly.
- **Opt-in mutation (#6, #9):** read-only by default; stops at the report and
  waits for an explicit request before changing anything.
- **Cite evidence (#5):** findings reference issue numbers, parent #, age, and
  similarity %.
- **Shoals (#11):** corrections (e.g. "issues labeled `keep-open` are never
  stale") are captured to `.claude/shoals/github-issue-auditor.github-issue-auditor.md`
  in your project and read back on the next run. Append-only and committed by
  default — `.gitignore` it for per-developer shoals.

## License

MIT
