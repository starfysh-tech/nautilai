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

## Phase 2.5: Detect the repo's PR template

The repo may ship its own PR template. Respect it — a description bot (CodeRabbit,
etc.) grades against *that* template, so a generic body fails the check. `gh pr
create --body` bypasses template resolution entirely, so we must detect and fill it
ourselves.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-pr-template.sh
```

| STATUS | Meaning | Phase 3 path |
|---|---|---|
| `FOUND` | one template applies (`PATH:`) | **Fill it** (Phase 3A) |
| `MULTIPLE` | a `PULL_REQUEST_TEMPLATE/` dir of choices (one `PATH:` per candidate) | **Pick, then fill** (Phase 3A) |
| `NONE` | no repo template | **Generic body** (Phase 3B) |

On `MULTIPLE`, choose the candidate whose filename obviously matches the Phase 4
conventional type (`fix:` → `bugfix.md`, `feat:` → `feature.md`). If no candidate is
an obvious match, ask with `AskUserQuestion`. Either way, name the chosen template in
the Phase 6 confirmation so `Edit` can override it.

## Phase 3A: Fill the repo template (STATUS `FOUND` / `MULTIPLE`)

Read the chosen `PATH` and fill it — **do not** substitute the generic format:

- **Preserve every heading, in order, verbatim.** Never add, drop, reorder, or rename
  a section — the grader keys on them.
- **Preserve `<!-- comments -->`** — they render invisibly and keep template fidelity.
- Fill each section from the Phase 2 commits/diff. For a section the diff can't
  honestly answer (e.g. `## Screenshots` on a backend change), write a one-line
  `N/A — <reason>`. **Never leave it blank** (a bot reads blank as skipped) and
  **never invent content.**
- **Never tick a pre-existing checkbox.** A checkbox is a human attestation
  (`- [ ] I ran the tests`); the author ticks it, not you. Leave every one unchecked.
- Issue link (Phase 5): if the template already has a close-keyword line or
  placeholder (`Closes #`, `Fixes #`, `Related:`), fill it in place. Otherwise append
  the link as a footer on its own line after the last section.

## Phase 3B: Generic body (STATUS `NONE`)

No repo template — generate this format:

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

Present the complete proposed PR — title, the body from Phase 3A/3B, and the issue
link from Phase 5 — in **one** `AskUserQuestion`. When a repo template was used, name
it (e.g. "Template: `bugfix.md` — inferred from `fix:`"):

- "Create this PR?" → **Create** / **Create draft** / **Edit** / **Skip**
  - **Edit** covers changing the template choice, issue link, title, or body — only then ask what to change. Don't pre-emptively prompt for any of them.

On Create / Create draft, write the Phase 3 body to a file and pass it with
`--body-file` — a filled repo template can contain characters that break a heredoc,
and `--body-file` preserves it exactly:

```bash
# BODY_FILE holds the Phase 3A filled template or the Phase 3B generic body.
# Write it under a temp dir (not the repo) and remove it after, so no untracked
# file is left behind.
gh pr create --title "<type>(<scope>): <summary>" --body-file "$BODY_FILE"
rm -f "$BODY_FILE"
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
