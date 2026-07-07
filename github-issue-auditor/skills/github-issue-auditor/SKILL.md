---
name: github-issue-auditor
description: Audits a GitHub repository's issues for cleanup — finds fuzzy-matched duplicate titles, orphaned sub-issues whose parent is closed, unlabeled or stale items, and labels inconsistent with the repo's own taxonomy. Inspection is read-only; any change to the tracker is opt-in behind an approval gate. Invoked via `/github-issue-auditor`.
argument-hint: "[owner/repo] [--stale-days N] [--similarity 0.0-1.0]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, AskUserQuestion, Bash(gh:*), mcp__github__list_issues, mcp__github__issue_read, mcp__github__search_issues, mcp__github__list_issue_types, mcp__github__get_label, mcp__github__issue_write, mcp__github__sub_issue_write, mcp__github__add_issue_comment
---

# GitHub Issue Auditor

Audit a repository's open issues for cleanup opportunities, then — only with
explicit approval — apply the agreed changes. The audit (Phases 1–3) is
**read-only**. Mutations (Phase 4) are **opt-in** and gated.

This skill is user-invoked. It does not infer the repo's label conventions from a
hardcoded list — it **detects the repo's own taxonomy first** (Phase 1) and judges
everything against that.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/github-issue-auditor.github-issue-auditor.md`
from the project root if it exists, and honor every entry as a constraint (e.g.
"issues labeled `keep-open` are intentionally never stale", "don't propose closing
issues in milestone X").

When the user corrects your behavior — what you treat as a duplicate, which labels
are "missing", what counts as stale, or what you propose to mutate — append a shoal
to that file (creating `.claude/shoals/` if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger**. Capture only explicit behavioral
corrections, not passing preferences. Mention the capture in one line; don't
narrate it. Never write outside `.claude/shoals/`. See `docs/conventions/shoals.md`.

## Tooling — graceful degradation

Pick the best-available tool at each step; degrade loudly; only hard-stop when the
baseline is genuinely absent:

1. **GitHub MCP** (`mcp__github__*`) — preferred for reads and (gated) writes.
2. **`gh` CLI** — the baseline. Reads via `gh issue list --json …`,
   `gh issue view N --json …`, `gh label list --json name,description`,
   `gh sub-issue list` (if the GH version supports it). Writes via
   `gh issue close`, `gh issue edit --add-label`, `gh issue comment`.
3. **Stop** — if neither MCP nor an authenticated `gh` is available, stop and tell
   the user to install/authenticate `gh` (`gh auth status`). Don't fabricate data.

State which path you took. If MCP is unavailable, say "falling back to gh CLI" once
and proceed; don't silently fail.

## Determine the target repo

- An `owner/repo` argument wins. Otherwise use the current directory's repo
  (`gh repo view --json nameWithOwner`).
- If neither resolves, ask the user which repo to audit. Never guess.

Each phase below has a deterministic Python implementation under `scripts/` (see
[Scripts](#scripts)). Use it when you want reproducible discovery/analysis instead
of hand-running queries; drive the phases directly (MCP/`gh`) when you need the
taxonomy-aware judgment the scripts don't encode.

## Phase 1 — Discover the taxonomy + the issues (read-only)

**1a. Detect the repo's label taxonomy** — do not assume any label names.

- List the repo's labels (`gh label list --json name,description,color` or the MCP
  label tools) and group them into families by prefix/convention you observe:
  status (`status: *`, `triage`, `backlog`, `wontfix`…), type (`type: *`, `bug`,
  `enhancement`, `feature`, `documentation`…), priority, area, etc.
- A repo's "duplicate", "backlog", and "needs-triage" labels are whatever **this**
  repo calls them. If the convention is ambiguous, ask the user which label marks
  duplicates / backlog rather than guessing.

**1b. Pull open issues** (read-only). Fetch `number, title, createdAt, updatedAt,
body, labels, state` for open issues (cap the page sensibly; note if truncated).

**1c. Bucket into candidate categories** — using the *detected* taxonomy:

1. **Marked duplicates** — issues carrying the repo's duplicate label.
2. **Unlabeled** — issues with zero labels (need triage).
3. **Stale** — issues in the repo's backlog/triage state older than the threshold
   (default 30 days from `createdAt`; honor `--stale-days`). If the repo has no
   backlog-like label, fall back to last-activity age (`updatedAt`) and say so.
4. **Orphaned sub-issues** — issues whose parent is closed. Prefer GitHub's native
   sub-issue links (MCP / `gh sub-issue`) when present; otherwise parse the body
   for parent references (case-insensitive): `Part of #N`, `Epic: #N`,
   `Parent: #N`, `Subtask of #N`, `Closes #N`. Confirm the parent is actually
   CLOSED before flagging (one `gh issue view N --json state` per unique parent).
5. **Inconsistent labels** — issues whose labels violate the detected convention
   (e.g. two mutually exclusive status labels, a type label the repo retired).

## Phase 2 — Analyze (read-only)

- **Potential duplicates (fuzzy).** Compare open-issue titles pairwise; flag pairs
  whose titles are highly similar. Use normalized Levenshtein similarity
  (`1 − editDistance / max(len)` on lowercased, trimmed titles); default threshold
  **0.75**, configurable via `--similarity`. Token/word-overlap is an acceptable
  cheaper proxy on large trackers. This is heuristic, not semantic — present pairs
  as *candidates to review*, never auto-merge.
- **Age** for stale items (days from `createdAt`, or `updatedAt` in the fallback).
- **Suggested disposition** per finding (see Finding dispositions) with a one-line
  rationale citing the issue number(s) and the evidence (label, parent #, age,
  similarity %).

## Phase 3 — Report findings (read-only, findings-first)

Lead with the findings, prioritized; **omit clean categories entirely**; no
process narration. For each finding cite the issue number and the specific
evidence. Suggested layout:

- A one-line summary count per non-empty category.
- **Marked duplicates** — `#N "title"` → original `#M` (from body), or "no
  reference found".
- **Orphaned sub-issues** — `#N "title"` → parent `#M` is CLOSED.
- **Potential duplicates** — `#N` ↔ `#M` — `87%` similar titles.
- **Unlabeled** — `#N "title"` — needs triage.
- **Stale** — `#N "title"` — `58` days old.
- **Inconsistent labels** — `#N` — has both `status: open` and `status: done`.

Then **stop** and let the user decide. Do not proceed to any mutation
unprompted — this is the review checkpoint.

## Phase 4 — Apply changes (opt-in, gated)

Mutations to someone's issue tracker are **never** automatic. Reaching Phase 4
requires the user to ask for changes after seeing the report. Then:

1. Build a task list grouped by action (close as duplicate · close as orphaned ·
   add label · comment · relabel), each tagged with issue # and rationale.
2. **Gate via `AskUserQuestion`**: Approve all · Review/select items · Modify
   scope · Cancel. Never self-resolve — surface and wait (nautilai convention #1).
3. Execute the **approved** items one by one, announcing each, via MCP if
   available else `gh`:
   - Close duplicate: comment `Closing as duplicate of #M`, then close.
   - Close orphaned: comment `Closing as parent issue #M is resolved`, then close.
   - Label: `gh issue edit N --add-label "<detected label>"`.
   - Stale: comment to confirm still-needed (don't close stale items on your own —
     that's a judgment call → `ask-user`).
4. GitHub records every change with your user attribution, and close/label are
   reversible — that is the audit trail (no local `.bak` needed). Report what
   changed: issue #, action, result; list any failures (permission, not-found,
   rate-limit) and continue past them.

## Scripts

This skill ships a deterministic, stdlib-only (Python 3.8+) implementation of the
four phases under `${CLAUDE_PLUGIN_ROOT}/skills/github-issue-auditor/scripts/`. The
graceful-degradation order above still holds — the scripts shell out to `gh`.

- `discovery.py` — **Phase 1** `gh` queries for marked duplicates, unlabeled, stale
  backlog, and orphaned sub-issues (body-reference parsing + confirmed-closed parent
  check). `DiscoveryEngine(stale_threshold_days, duplicate_label, backlog_label)`:
  pass the labels you detected in **Phase 1a** instead of the defaults
  (`status: duplicate`, `status: backlog`) when this repo's taxonomy differs — don't
  assume the defaults fit. Standalone:
  `python3 ${CLAUDE_PLUGIN_ROOT}/skills/github-issue-auditor/scripts/discovery.py`.
- `analyzer.py` — **Phase 2** normalized Levenshtein title similarity (default
  threshold `0.75`, honor `--similarity`), parent-reference extraction, age, and a
  suggested disposition per finding. `IssueAnalyzer(similarity_threshold=0.75,
  label_map={...})`: pass the `bug`/`enhancement`/`documentation` labels you
  detected in **Phase 1a** instead of the defaults (`type: bug`, `type:
  enhancement`, `type: documentation`) when this repo's taxonomy differs.
- `interactive_review.py` — **Phase 3** per-item approval reference flow. In-skill,
  the `AskUserQuestion` gate is the canonical approval control; this is its CLI
  equivalent (`InteractiveReviewer.review_all`). Do not run it from within a
  session — it blocks on stdin; use `AskUserQuestion` instead.
- `executor.py` — **Phase 4** applies approved actions via `gh`
  (`ActionExecutor(dry_run=...)`: close-with-comment, add-label, comment,
  investigation comment). Supports a dry-run preview.
- `report_generator.py` — optional markdown audit report
  (`ReportGenerator.generate_report` / `save_report`).

Config schema: `${CLAUDE_PLUGIN_ROOT}/skills/github-issue-auditor/config.example.json`
(`stale_threshold_days`, `similarity_threshold`, `categories_to_audit`,
`generate_report`, `dry_run`). Invocation examples and workflows:
`references/HOW_TO_USE.md`.

## Finding dispositions

Per the nautilai convention (`docs/conventions/finding-dispositions.md`). Because
every change here mutates the **user's** issue tracker, the default posture is
conservative:

- **auto-fix** — *none by default*. The audit never edits the tracker on its own.
  Mechanical relabeling may be applied **only** inside the Phase 4 approved batch
  (the gate is the single control point); the GitHub-side change is the recoverable
  record.
- **report** — the entire audit: every candidate duplicate, orphan, unlabeled,
  stale, and inconsistency, with cited issue numbers. Surfaced in Phase 3 and stop.
- **ask-user** — every mutation (close, relabel, comment, merge suggestion) and any
  judgment call (is this *really* a duplicate? is a stale backlog item still
  wanted?). Decided **only** through the Phase 4 gate; never silently fixed or
  skipped, not even "skip as trivial".

## Parent reference formats

Case-insensitive. Native sub-issue links (when the repo uses them) take precedence
over body parsing.

| Format          | Example          |
| --------------- | ---------------- |
| `Part of #N`    | Part of #42      |
| `Epic: #N`      | Epic: #100       |
| `Parent: #N`    | Parent: #78      |
| `Subtask of #N` | Subtask of #55   |
| `Closes #N`     | Closes #12       |

## Gotchas

- **Fuzzy matching is heuristic, not semantic.** A 0.88 title similarity is a
  prompt to look, not proof of duplication. Always present as a candidate pair.
- **Don't assume label names.** "duplicate"/"backlog"/"bug" are this skill's
  *concepts*; the repo's actual labels are detected in Phase 1. Audit against the
  repo's taxonomy, not a built-in one.
- **Orphan detection needs a confirmed-closed parent.** A body reference alone
  isn't enough — verify the parent's state.
- **Stale ≠ close.** Age flags an item for a human to confirm; closing it is the
  user's call.
- **Rate limits / truncation.** Large trackers may truncate the page or hit API
  limits — say so rather than reporting a partial set as complete.
- **Read-only until asked.** Phases 1–3 mutate nothing. If the user only wanted a
  report, you're done after Phase 3.
