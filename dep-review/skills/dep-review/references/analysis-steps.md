# Per-PR analysis steps

For each PR, gather evidence across six dimensions, then recommend a verdict. In
batch mode you may analyze PRs concurrently. **Every claim about the codebase
carries a `file:line`** (or "not found in <path searched>"); every claim about the
dependency quotes the changelog/diff.

## Return shape

Produce each PR's analysis in this shape so Phase 3 can apply the decision rules:

```markdown
## PR #<number>: <title>

### Classification
- Change type: patch | minor | major
- Ecosystem: npm | pip | github_actions | <other>
- Grouped: yes | no (if yes, list packages + per-package change type)
- Dev dependency: yes | no

### CI status
- Status: passing | failing | pending
- Failed checks: <list or "none">

### Changes extracted (cited)
<numbered list of specific changes per package — what changed / how / migration
needed — each with the changelog source quoted or linked>

### Codebase verification (cited)
<per change: search performed -> file:line found (or "not found in <path>") ->
impact NONE | LOW | MEDIUM | HIGH>

### Aggregated impact
- Overall: NONE | LOW | MEDIUM | HIGH
- Affected files: <count> — <key paths>

### Security
- CVEs: none | <list with severity + whether the vulnerable path is used>

### EOL status
- active | deprecated | unmaintained | yanked-target

### Recommended verdict
- Verdict: MERGE | SKIP | INVESTIGATE
- Confidence: High | Medium | Low
- Reasoning: <1-2 sentences, grounded in the evidence above>
```

> Verdicts are `MERGE` / `SKIP` / `INVESTIGATE`. "Auto-MERGE" is **not** a verdict —
> it is a *disposition* on a MERGE (see SKILL.md "Finding dispositions"): every
> merge is gated behind approval unless the user passed the explicit opt-in flag
> for low-risk patches.

## 2a. Classify change type

Parse semver from the PR title:

- **patch**: `1.2.3 -> 1.2.4`
- **minor**: `1.2.3 -> 1.3.0`
- **major**: `1.2.3 -> 2.0.0`

Grouped PRs -> use the **highest** severity across all packages (any major -> treat
the PR as major).

## 2b. CI status

```bash
gh pr checks <PR_NUMBER> --json name,state
```

- `passing` — all checks completed successfully
- `failing` — any check failed
- `pending` — checks still running

If this repo has an advisory-only check the user has flagged before, honor the
shoal rather than treating it as failing.

## 2c. Extract specific changes (cite the source)

**Goal:** a structured list of concrete changes per package — not just keyword
presence.

1. **Read the PR body** for embedded release notes: `gh pr view <n> --json body -q '.body'`.
2. **For each package, identify:** what changed (API/method/config/behavior), how
   (renamed / removed / signature change / behavior change / new requirement),
   migration needed (yes/no + detail).
3. **Fallback for sparse/missing notes** (see the changelog fallback chain in
   SKILL.md): GitHub releases (`gh api repos/<org>/<repo>/releases/tags/v<version>`)
   -> repo CHANGELOG (WebFetch) -> registry version list. If nothing resolves,
   the change is INVESTIGATE.
4. **Keyword scan as a supplement** (not a substitute for reading): `BREAKING
   CHANGE`, `migration`, `deprecated`/`removed`, `renamed`, `requires changes`,
   `peer dependency`.

## 2d. Verify each change against the codebase (cite `file:line`)

For **each** change from 2c, determine whether it touches *this* codebase.

1. **Identify the search target** — the changed API/method/class, the old import
   path, or the changed feature/option name.
2. **Search** with the `Grep`/`Glob` tools (not raw shell `grep`), scoped to the
   ecosystem's source dir (detected, not hardcoded):
   - npm: `Grep "from ['\"]<package>" glob="*.{ts,tsx,js,jsx}"`
   - pip: `Grep "import <module>"` / `Grep "from <module>"` glob="*.py"
   (See `decision-matrix.md` for import-name caveats and `@types/*` handling.)
3. **Read the matched files** to confirm real usage — don't trust a string match
   alone.
4. **Classify impact per change**, with the `file:line` evidence:
   - **NONE** — not found in the searched paths
   - **LOW** — found but unaffected (e.g. an optional param we don't pass)
   - **MEDIUM** — found, minor change needed (e.g. rename an import)
   - **HIGH** — found, significant refactor (e.g. signature change across many files)

## 2e. Aggregate per-package impact

Combine per-change impacts (highest severity wins): any HIGH -> package HIGH; else
any MEDIUM -> MEDIUM; else any LOW -> LOW; none -> NONE (candidate unused
dependency). For grouped PRs, repeat per package and use the highest package impact
as the PR's input.

## 2f. Security analysis

- Check labels/body for CVEs: `gh pr view <n> --json labels,body`.
- If a CVE is present, determine the affected feature and **cross-reference 2d** —
  is the vulnerable path actually used here? Priority: CRITICAL (RCE, auth bypass)
  > HIGH (XSS, injection) > MEDIUM (DoS) > LOW (info disclosure).
- Optional audit when the tool is present (degrade if not): `npm audit --json`,
  `pip-audit --format json`.

## 2g. EOL status

- npm: `npm view <package> deprecated time` (or `https://registry.npmjs.org/<package>`).
- pip: latest upload time — `curl -s https://pypi.org/pypi/<package>/json | jq -r '[.releases[][] | .upload_time] | max'`.
- EOL indicators: marked deprecated, all versions yanked, no releases in a long
  time, README says "no longer maintained"/"archived". A deprecated/EOL package
  can turn a SKIP into a recommendation to migrate — surface it; the decision is
  still the user's.
