# PR Creation Workflow

## Phase 0: Branch & Commit Gate

Check working state before PR creation:

```bash
BRANCH=$(git branch --show-current)
git status --porcelain
```

**If on `main` or `master`:**

1. If uncommitted changes exist:
   - Follow `workflows/commit.md` Phases 1-5 (stage, generate message, create branch, commit)
   - After commit completes on the new branch, continue to Phase 1
2. If no uncommitted changes:
   - Stop: "No changes to create a PR from. Make changes first, then run `/commitcraft pr`."

**If on a feature branch:**

Continue to Phase 1.

## Phase 1: Check for Existing PR

Check if a PR already exists for the current branch:

```bash
gh pr view --json state,url 2>/dev/null
```

**Handling:**
- If no PR found → Continue to Phase 2
- If PR exists with `state: OPEN` → Display URL, ask if user wants to update description or exit
- If PR exists with `state: CLOSED` or `state: MERGED` → It's not blocking; continue to Phase 2 to create a fresh PR

## Phase 2: Gather Context

Collect branch and commit information:

```bash
BRANCH=$(git branch --show-current)
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -z "$BASE" ]; then
    BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
fi
BASE="${BASE:-main}"
git log "$BASE"..HEAD --oneline
git diff "$BASE"...HEAD --stat
```

Parse commits to understand:
- What changed (files, functions, features)
- Why it changed (commit messages)
- Scope of changes (additions/deletions)

## Phase 3: Generate PR Description

Create PR description following this format:

```markdown
## Summary
[One paragraph overview of what this PR does and why]

## Changes
- **Component/Area:** Description of change
- **Component/Area:** Description of change

## Test plan
- [ ] Verification step 1
- [ ] Verification step 2
- [ ] Verification step 3
```

**Style Guidelines:**
- Summary: 1-2 paragraphs, explain the "why" not just the "what"
- Changes: Bold prefix for component/area, group related changes
- Test plan: Checkbox format `- [ ]`, actionable verification steps
- Keep concise and scannable

## Phase 4: Determine PR Title

Generate conventional commit-style title from commits:

```
<type>(<scope>): <summary>
```

**Rules:**
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`
- Summary: imperative mood, ≤70 chars, lowercase
- Scope: optional, single word from commits

## Phase 5: Determine Issue Link (no prompt — pick a sensible default)

Run full issue validation (PR time is where it belongs):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-issues.sh
```

Pick the default link **without prompting** — it's confirmed once in Phase 6:

| STATUS | Default link in PR Summary |
|---|---|
| `OK` | `Closes #<num>`. Multiple issues → `Closes #A, closes #B` (keyword before EACH number). |
| `REFERENCE` | The `REF:` line verbatim (e.g. `Refs ENG-123`). Never `Closes #` — close keywords don't apply to external trackers. |
| `INCOMPLETE` | `Closes #<num>` — note "N unchecked acceptance criteria" inline in the summary. |
| `BLOCKED` | No close keyword; note "issue #X has blocking labels" inline. |
| `NOT_FOUND` / `NO_ISSUE` / `ERROR` | No issue link. |

## Phase 6: Confirm & Create (single prompt)

Present the complete proposed PR — title, body, and the issue link from Phase 5 —
in **one** `AskUserQuestion`:

- "Create this PR?" → **Create** / **Create draft** / **Edit** / **Skip**
  - **Edit** covers changing the issue link, title, or body — only then ask what to change. Don't pre-emptively prompt for any of them.

On Create / Create draft:

```bash
gh pr create --title "<type>(<scope>): <summary>" --body "$(cat <<'EOF'
## Summary
[Generated summary with the Phase 5 issue link if any]

## Changes
- **Component:** Description

## Test plan
- [ ] Step 1
EOF
)"
```

Add `--draft` if draft was selected. Capture the PR URL from output.

## Phase 7: Final Report

Display result:

```
✓ PR created: <url>
✓ Branch: <branch>
✓ Commits: N commits since <base branch>
```

Or if skipped:

```
PR creation skipped
```
