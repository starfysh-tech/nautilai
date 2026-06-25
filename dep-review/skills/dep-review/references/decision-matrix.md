# Decision matrix

Verdicts are **MERGE / SKIP / INVESTIGATE**. Dispositions (what the skill may *do*
about a verdict — gate, report) live in SKILL.md "Finding dispositions". This file
is the rules + ecosystem detail for *landing* a verdict from the Phase 2 evidence.

## Decision rules

| Verdict | Conditions | Disposition (see SKILL.md) |
|---------|-----------|----------------------------|
| **MERGE** | Patch bump + CI passing + no breaking changes | `ask-user` — gate; eligible for the opt-in `--auto-merge-patch` flag |
| **MERGE** | Minor dev-dep + CI passing + no breaking changes | `ask-user` — gate (not flag-eligible: flag covers patches only) |
| **MERGE** | Minor runtime dep + CI passing + no breaking + used | `ask-user` — gate |
| **MERGE** | Security fix for a *used* feature + CI passing/fixable | `ask-user` — gate (urgent) |
| **INVESTIGATE** | Major version bump | `report` |
| **INVESTIGATE** | Breaking changes detected | `report` |
| **INVESTIGATE** | CI failing | `report` |
| **INVESTIGATE** | Pre-release (alpha/beta/rc/canary/next) | `report` |
| **INVESTIGATE** | Unable to determine impact / changelog unresolvable | `report` |
| **SKIP** | Security fix for an *unused* feature | `ask-user` — gate the close |
| **SKIP** | Dead dependency (no usage found) | `ask-user` — gate the close (+ offer a removal issue) |
| **SKIP** | Requires refactoring, not urgent | `ask-user` — gate the close |

**Overrides** (severity flips the verdict, but the action is still gated):

- **EOL / deprecated library** -> supersedes SKIP. Recommend migrating; surface as
  urgent. Decision is the user's.
- **Critical CVE in a used feature** -> supersedes INVESTIGATE. Must be reviewed
  urgently; recommend an expedited gated merge or a tracking issue.

> There is no silent action. Even a low-risk patch is gated unless the user passed
> the explicit opt-in flag *in this invocation* (then: patch + passing CI + no
> breaking changes only; report exactly what merged).

## Ecosystem detection (no hardcoded paths)

Detect the source layout from the repo, don't assume one:

- **npm** — find `package.json` (and a lockfile); search siblings of it for source
  (`*.{ts,tsx,js,jsx,mjs,cjs}`). Branch prefix: `dependabot/npm_and_yarn/...`.
- **pip** — find `pyproject.toml` / `requirements*.txt` / `setup.cfg`; search the
  package dir for `*.py`. Branch prefix: `dependabot/pip/...`.
- **GitHub Actions** — `.github/workflows/*.yml`. Branch prefix:
  `dependabot/github_actions/...`. (Usually low-risk; still verify the pinned
  action version in the workflow files.)
- **Other ecosystems** (cargo, bundler, gomod, docker, etc.) follow the same
  pattern: locate the manifest, search the relevant source globs, verify usage.

## Ecosystem commands

Use the `Grep`/`Glob` tools for codebase search (not raw shell `grep`). Use CLIs
for registry metadata when present; **fall back to the HTTP API** when they aren't,
and **degrade loudly** (lower confidence) if a source is unreachable.

### npm (JavaScript/TypeScript)

```bash
npm view <package> deprecated        # deprecation notice
npm view <package> time              # publish times (EOL signal)
npm audit --json | jq '.vulnerabilities'   # run in the dir with the lockfile
# HTTP fallback if npm CLI absent:
curl -s https://registry.npmjs.org/<package> | jq '.time, .["dist-tags"]'
```

Usage search (Grep tool, scoped to the detected source dir):

```
Grep "from ['\"]<package>"          glob="*.{ts,tsx,js,jsx}"
Grep "import type.*from ['\"]<package>"  glob="*.{ts,tsx}"
Grep "import\\(['\"]<package>"      glob="*.{ts,tsx,js,jsx}"   # dynamic import
Grep "require\\(['\"]<package>"     glob="*.{js,cjs}"
```

Caveats:

- `@types/*` -> check the **runtime** package (e.g. `@types/react` -> search `react`).
- Scoped packages -> include the full scope (`@tanstack/react-query`).
- Aliased imports -> check `package.json` `imports`/`paths` (tsconfig).

### pip (Python)

```bash
# deprecation (Development Status classifier):
curl -s https://pypi.org/pypi/<package>/json | jq '.info.classifiers[] | select(startswith("Development Status"))'
# yanked check for a specific version:
curl -s https://pypi.org/pypi/<package>/json | jq '.releases."<version>"[].yanked'
# latest upload time (EOL signal):
curl -s https://pypi.org/pypi/<package>/json | jq -r '[.releases[][] | .upload_time] | max'
pip-audit --format json              # if installed
```

Usage search:

```
Grep "import <module>"   glob="*.py"
Grep "from <module>"     glob="*.py"
```

**The PyPI package name is often not the import name.** Map it before searching.
Two reliable ways to find the real import name (don't hardcode a per-project
table — derive it):

1. `python -c "import importlib.metadata as m; print(m.metadata('<package>').get('Name')); print([f for f in (m.files('<package>') or []) if str(f).endswith('__init__.py')][:5])"`
   — lists the installed top-level modules.
2. Inspect the project's lockfile / installed `*.dist-info/top_level.txt`.

Common cases (illustrative, verify per repo): `django-cors-headers` ->
`corsheaders`; `djangorestframework` -> `rest_framework`; `psycopg2-binary` ->
`psycopg2`; `python-decouple` -> `decouple`. Django packages: also search
`settings.py` for `INSTALLED_APPS` / `MIDDLEWARE`.

**CLI-only tools** (e.g. `gunicorn`, `uvicorn`, `ruff`, `pre-commit`, `pytest`
runners) are rarely imported — check `Dockerfile`, CI workflows, `pyproject.toml`
`[tool.*]` sections, and `scripts` instead of import sites. Bias these toward
MERGE (lower breaking-change risk), but still verify.

## Edge cases

### Grouped dependency PRs
Dependabot can bundle several same-ecosystem packages in one PR (a dependency table
in the body; title like "Bump the <group> group ... with N updates"). Classify each
package individually, then apply the **highest** severity as the single PR verdict
(any major or any detected breaking change -> INVESTIGATE; all patch/minor dev deps
+ CI passing -> MERGE). Report all packages, one verdict.

### @types/* packages
Type-only, dev deps, never affect runtime. Check the **runtime** package's usage;
if that's unused -> SKIP (dead dependency). A major `@types/*` bump can imply a
runtime version requirement (e.g. `@types/react@18` wants `react@18.x`) — note it.

### React + React-DOM parity
`react` and `react-dom` must move together. Both in one PR -> evaluate as a unit
(react drives). Only one bumped -> INVESTIGATE (mismatch risk). Two separate PRs ->
coordinate them in the batch and gate them together.

### Pre-release versions
alpha / beta / rc / canary / next -> **INVESTIGATE**, never flag-eligible. May carry
breaking changes without a major bump. Recommend waiting for stable.

### Transitive dependencies
A dep bumped as a side effect of a parent (e.g. `postcss` via `tailwindcss`).
Identify the parent (`npm ls <pkg>` / `pip show <pkg>`); if the parent pins an
explicit version -> INVESTIGATE (conflict risk); if it uses a range -> apply normal
rules to the transitive dep.

### Security fix for an unused feature
CVE present, but the vulnerable path isn't used here (verified in 2d) -> SKIP (gate
the close), document the reasoning. **Exception:** CRITICAL severity -> MERGE anyway
as defense-in-depth.

### Multiple PRs for the same package
A follow-up PR superseding an older one (e.g. `4.2.8` then `4.2.9`) -> evaluate the
latest; recommend closing the older with a "Superseded by #<n>" comment (gated).

### Changelog not found
PR body lacks notes. Walk the fallback chain (GitHub releases -> repo CHANGELOG ->
registry version list). If still unresolved -> INVESTIGATE (can't verify breaking
changes) — never guess a MERGE.

### CVE listed but CI passing
Tests may not cover the vulnerable path. -> MERGE (gated): present the CVE + the
usage analysis, ask the user to confirm the security impact; suggest a security test.

### Yanked releases (pip)
`curl -s https://pypi.org/pypi/<pkg>/json | jq '.releases."<v>"[].yanked'`. Updating
**to** a yanked version -> SKIP (broken release). Updating **from** a yanked version
-> MERGE (escaping a broken state).

## Confidence levels

- **High** — all six dimensions returned clear data; no edge cases.
- **Medium** — some ambiguity (changelog 404'd, mixed signals). Say what's unsure.
- **Low** — missing data or conflicting signals. Name what would raise it.

Always pair a Low/Medium with the specific gap, e.g. "MERGE (Medium): CI passing,
no breaking keywords, but the changelog URL 404'd — recommend a manual changelog
read at <url>."
