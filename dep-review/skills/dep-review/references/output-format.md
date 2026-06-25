# Output format

Findings-first: lead with the verdict, omit clean dimensions, cite evidence with
`file:line`. Use generic, repo-detected paths in your own output — the paths below
are illustrative.

## Single-PR report

```markdown
### PR #596: @testing-library/react 14.3.1 -> 15.0.7

**Verdict: INVESTIGATE** (High confidence)

**Summary:**
- Change type: major (14 -> 15)
- CI: passing
- Overall impact: HIGH (13 files affected)
- Security: no CVEs
- EOL: actively maintained

**Changes verified (cited):**

1. **renderHook 2nd param now an options object** (was a callback)
   - Search: `Grep "renderHook" glob="*.test.{ts,tsx}"`
   - Found: 8 files — e.g. src/hooks/useAuth.test.tsx:15, src/hooks/usePagination.test.tsx:22
   - Impact: HIGH — all 8 hook tests need the signature update

2. **waitFor default timeout reduced 1000ms -> 500ms**
   - Search: `Grep "waitFor" glob="*.test.{ts,tsx}"`
   - Found: 5 files with explicit timeout expectations
   - Impact: MEDIUM — may need timeout adjustments

3. **act() required for async updates**
   - Search: `Grep "act\\(" glob="*.test.{ts,tsx}"`
   - Found: already wrapped consistently — NO IMPACT

**Recommendation:** review the v14->v15 migration guide before merging; 13 files
across hooks/components need updates. Report-only — no action taken.
```

## Batch summary table

```markdown
## Dependabot PR batch review

| PR | Package(s) | Change | Verdict | Disposition |
|----|------------|--------|---------|-------------|
| #592 | 8 dev deps (grouped) | patch/minor | MERGE | gated — awaiting approval |
| #593 | axios 1.6.2 -> 1.7.0 | minor (runtime) | MERGE | gated — awaiting approval |
| #596 | @testing-library/react | 14->15 major | INVESTIGATE | report only |
| #597 | django-stubs 4.2.7 -> 5.0.0 | major | INVESTIGATE | report only |

**Summary:**
- MERGE (gated): 2 PRs — present for approval
- INVESTIGATE: 2 PRs — review required, no action
- SKIP: 0

**Next:** approve which of the gated MERGEs to land (AskUserQuestion). Nothing is
merged or closed without your approval.
```

After a gated action runs, report exactly what happened: PR #, package, from->to,
and the merge/close result (commit SHA or close confirmation).
