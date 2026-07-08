# How to Use GitHub Issue Auditor

Reference doc for invoking this skill directly (it has `disable-model-invocation:
true`, so it never triggers from conversational phrasing — always run
`/github-issue-auditor`).

## Prerequisites

- [ ] GitHub CLI (`gh`) installed and authenticated (`gh auth status`), or GitHub
      MCP tools available
- [ ] Working directory is inside the target repo, or pass `owner/repo` explicitly
- [ ] Write access to the repository if you intend to reach Phase 4

## Invocation

```
/github-issue-auditor [owner/repo] [--stale-days N] [--similarity 0.0-1.0]
```

- No argument → audits the current directory's repo.
- `--stale-days` overrides the default 30-day stale-backlog threshold.
- `--similarity` overrides the default 0.75 fuzzy-duplicate threshold.

## Workflow (see SKILL.md for full detail)

1. **Phase 1 — Discover**: detects the repo's own label taxonomy first (no
   hardcoded "duplicate"/"backlog"/"bug" label names), then pulls open issues and
   buckets them into marked duplicates, unlabeled, stale, orphaned sub-issues, and
   inconsistent labels.
2. **Phase 2 — Analyze**: fuzzy title-similarity for potential duplicates,
   age for stale items, a suggested disposition per finding.
3. **Phase 3 — Report**: findings-first summary, cited by issue number. **Stops
   here.** No mutation happens without you asking for it next.
4. **Phase 4 — Apply** (only if you ask): builds a task list from the report,
   gates it through `AskUserQuestion` (approve all / review-select / modify scope
   / cancel), then executes only what you approved.

## Config schema

Optional `config.json` (see `config.example.json`):

```json
{
  "stale_threshold_days": 30,
  "similarity_threshold": 0.75,
  "categories_to_audit": ["duplicates", "unlabeled", "stale_backlog", "orphaned", "potential_duplicates"],
  "generate_report": false,
  "dry_run": false
}
```

Natural-language overrides also work, e.g. "use a 60-day stale threshold" or
"0.85 similarity for duplicates."

## Scripts

The deterministic implementations under `scripts/` can be run standalone for
testing or debugging (see SKILL.md's Scripts section for full parameter docs):

```bash
python3 scripts/discovery.py      # Phase 1
python3 scripts/analyzer.py       # Phase 2 (reads discovery output)
python3 scripts/executor.py       # Phase 4 (reads approved actions)
```

`interactive_review.py` is a CLI reference implementation of the Phase 3
approval flow — do not run it from within a session (it blocks on stdin); the
skill uses `AskUserQuestion` instead.

## Error table

| Symptom | Cause | Fix |
|---|---|---|
| `GitHub CLI (gh) is not installed` | `gh` missing | Install from https://cli.github.com/ |
| `Not authenticated with GitHub` | No `gh` session | `gh auth login` |
| `Not in a GitHub repository` | cwd isn't a repo, no `owner/repo` given | `cd` into the repo or pass `owner/repo` |
| `Permission denied` on a Phase 4 action | No write access | Verify repo permissions |
| Rate limit / truncated results | Large tracker, API cap hit | Check `gh api rate_limit`; note the truncation in the report rather than treating it as complete |
