# Push Workflow (Phases 1-8)

## Phases 1-3: Environment Check, Auto-Stage, and Branch Check

Execute Phases 1-3 from commit workflow (Environment Check, Auto-Stage, Branch Check).

After running `git status --porcelain`:

- **If working tree is clean** (no output from git status):
  - Count commits not yet on any remote: `git rev-list HEAD --not --remotes --count`
    (this is correct even on a brand-new branch with no upstream, where
    `@{upstream}..HEAD` would wrongly resolve to 0).
  - If count > 0 → skip directly to Phase 6 (Push only, no commit needed). Phase 6
    already pushes with `-u` when there's no upstream, so a new branch is handled.
  - If count = 0 → HARD STOP (everything is already pushed / up to date).

- **If working tree has changes** (git status produced output):
  - Continue to auto-stage and commit (Phases 2-5), then push (Phase 6)
  - This applies even if there are also unpushed commits — stage, commit, then push all

Then follow commit workflow Phases 2-3 for auto-staging and branch check.

> No pre-flight tooling scan on the push path — the pre-commit hooks enforce
> format and secrets at commit time regardless of what a scan would report.
> Run `/commitcraft check` on demand for a full tooling report.

## Phase 3: Issue Context

Extract the issue reference only — no validation, no network call. Full validation
(blocking labels, acceptance criteria) happens at PR time, not on every push.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-issues.sh --ref-only
```

Parse output:

| STATUS | Action |
|---|---|
| `REFERENCE` | Capture the `REF:` line for the commit footer |
| `NO_ISSUE` | No footer ref; auto-continue |

## Phase 4: AI Commit Message Generation

1. Read staged diff:

```bash
git diff --cached
```

2. Generate conventional commit message:

**Format:**
```
<type>(<scope>): <subject>

<body>

<REF line from Phase 3>
```

**Rules:** Follow commit workflow Phase 4 for format and type rules — the
commit-msg hook (commitlint, per `.commitlintrc.yml`) is the enforcer, so generate
a compliant draft and let the hook reject anything off. Push-specific additions:
- Footer: use the `REF:` line captured in Phase 3 verbatim (e.g. `Refs #12` for GitHub, `Refs ENG-12` for Linear/Jira). Omit if Phase 3 produced no `REF:` line.

## Phase 5: Commit

1. Commit with HEREDOC (preserves formatting):

```bash
git commit -m "$(cat <<'EOF'
<generated message here>
EOF
)"
```

2. Pre-commit hooks run automatically (gitleaks, commitlint, linters).

3. Handle hook failures:

| Failure Type | Action |
|---|---|
| gitleaks detects secrets | HARD STOP — show findings, never suggest `--no-verify`, exit |
| commitlint format error | HARD STOP — show error, suggest fix, never suggest `--no-verify`, exit |
| Auto-fixable (prettier, eslint --fix) | SOFT BLOCK — show fixed files, re-stage, retry commit |
| Test failures | HARD STOP — show failures, exit |

**Never use `--no-verify` or any hook-skipping flags.**

4. On success, capture commit hash for later use.

## Phase 6: Push to Remote

1. Check sync with remote:

```bash
git rev-list HEAD...@{upstream} --count --left-right
```

Parse output:
- `0       0` — in sync, continue
- `N       0` — ahead by N, continue
- `0       M` — behind by M, HARD STOP
- `N       M` — diverged, HARD STOP

If behind or diverged:
```
✗ Branch is behind remote
Run: git pull --rebase
```

2. Check for upstream tracking:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{upstream}
```

If no upstream, push with `-u`:

```bash
git push -u origin $(git branch --show-current)
```

Otherwise, push normally:

```bash
git push origin $(git branch --show-current)
```

3. Display push result.

## Phase 7: Issue Comment

Only if Phase 3 returned `STATUS: REFERENCE` with a **numeric** `ISSUE` (GitHub).
Skip for Linear/Jira keys (`gh issue comment` doesn't apply) and when there's no ref.

1. Capture commit hash and subject:

```bash
HASH=$(git log -1 --format=%h)
SUBJECT=$(git log -1 --format=%s)
BRANCH=$(git branch --show-current)
```

2. Post comment (best-effort — the ref-only path didn't verify the issue exists, so
   treat a failure as non-fatal and just note it):

```bash
gh issue comment <NUM> --body "Commit $HASH pushed on \`$BRANCH\`: $SUBJECT" || echo "Issue comment skipped (issue #<NUM> not found or gh unavailable)"
```

3. Display confirmation.

## Phase 8: Final Report

Display summary:

```
✓ Commit: <hash> <subject>
✓ Pushed to: origin/<branch>
✓ Issue updated: #<num>

Full message:
<full commit message>
```
