# PHI Scan

Scan a repo for Protected Health Information (PHI under HIPAA Safe Harbor) — SSNs, emails, phones, IPs, dates, restricted ZIP codes — then AI-triage the findings to filter false positives and catch what regex misses (names, MRNs). An optional, stack-gated OWASP grep pass covers common Django/React web vulnerabilities.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install phi-scan@nautilai
```

Requires `python3` on your PATH (the bundled scanner is stdlib-only, Python 3.10+).

## Use

```text
/phi-scan                 # scan staged files (git)
/phi-scan src/ --verbose  # scan a path
/phi-scan --all           # scan the whole working tree
```

## What it does

1. **Deterministic PHI scan** — a bundled `phi_check.py` matches HIPAA Safe Harbor identifiers (SSN, email, phone, IPv4, US/ISO dates, 5-digit ZIP with the 17 restricted prefixes prioritized). It filters obvious test data and honors inline `# phi-safe` suppressions, and exits non-zero on real findings — so it doubles as a git pre-commit hook.
2. **AI triage** — separates real exposure from noise: dismisses config/test/comment matches, judges date and ZIP context, and reads flagged files for names, MRNs, and rare conditions that regex can't see.
3. **Optional OWASP pass** — *off by default, stack-gated.* On Django and/or React codebases it runs shallow `grep` heuristics for hardcoded secrets, raw-SQL injection, `mark_safe`/`innerHTML` XSS, missing `permission_classes`, and PHI/secrets in logs. It is **not** a real SAST — pair it with gitleaks/semgrep/bandit for serious work.

The PHI layer is the core and is stack-agnostic. The OWASP layer is a Django/React convenience add-on and is skipped on other stacks.

## Install as a git pre-commit hook

The bundled scanner doubles as a git pre-commit hook that blocks commits containing non-test PHI. The easiest path is to ask the skill — "install the phi-scan pre-commit hook" — and it copies the files for you (it knows the plugin's install path and checks for an existing hook first).

To do it by hand, copy both bundled files from the installed plugin into your repo's `.git/hooks/`:

```bash
# PLUGIN_DIR is where the marketplace installed phi-scan, e.g.
#   ~/.claude/plugins/cache/nautilai/phi-scan/<version>
cp "$PLUGIN_DIR/scripts/phi_check.py" .git/hooks/phi_check.py
cp "$PLUGIN_DIR/scripts/pre-commit"   .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

The wrapper locates `phi_check.py` next to itself (falling back to `~/.local/bin` or `/usr/local/bin`), resolves `python3`/`python`, and **fails open** (warns, never blocks) if neither is available.

**Opt-in branch protection** — the hook can also reject direct commits to `main`/`master`. It's off by default; enable it with:

```bash
export PHI_SCAN_BLOCK_DEFAULT_BRANCH=1   # add to your shell profile to persist
```

`.git/hooks/` isn't committed, so each clone re-installs. For a shared team hook, point `core.hooksPath` at a tracked directory and copy the two files there.

## Real-time write guard (opt-in)

The plugin also ships a `PreToolUse` hook (`hooks/hooks.json` → `scripts/phi_guard.py`) that scans the content of every `Write`/`Edit`/`MultiEdit` **before it lands on disk**. On a real (non-test) PHI match it cancels the tool call and tells Claude why — catching PHI at authoring time, not just at commit.

It is **off by default** so installing the plugin never silently blocks edits. Turn it on per shell:

```bash
export PHI_SCAN_GUARD=1   # add to your shell profile to persist
```

The variable is read when Claude Code launches, so set it in your profile (or before starting `claude`) — toggling it mid-session has no effect until restart.

- Uses the same scanner, test-data filtering, and inline `# phi-safe` suppressions as the commit hook.
- Only scans scannable extensions; skips test/fixture paths.
- Covers `Write`, `Edit`, and `MultiEdit`. Notebook edits (`NotebookEdit`) are **not** scanned — the commit hook still catches PHI in saved `.ipynb` files.
- **Fails open** — if the payload is malformed or the scanner can't load, the write proceeds rather than wedging the session.

The git pre-commit hook and this guard are independent: the guard is the early net (per write), the commit hook is the backstop (per commit). Use either or both.

## Migrating from an earlier install

Earlier versions shipped as a loose `phi_check.py`, a hand-copied git hook, or a personal `phi-security` skill. Replace those so a stale copy doesn't shadow this plugin.

**1. Find existing copies (read-only):**

```bash
find "$HOME/.local/bin" "$HOME/.claude" . -name 'phi_check.py' 2>/dev/null
ls -d "$HOME/.claude/skills/phi-security" /usr/local/bin/phi_check.py 2>/dev/null
```

**2. Replace project/global git hooks** — re-run the install step above; the copy overwrites the old `phi_check.py` + `pre-commit` in place.

**3. Remove the superseded copies** (review each before deleting):

```bash
rm -rf ~/.claude/skills/phi-security      # old personal skill
rm ~/.local/bin/phi_check.py              # old global script (and /usr/local/bin if present)
```

Keep any `scripts/phi_check.py` that a project has **intentionally checked in** (it may be wired into that repo's CI) — update its contents from this plugin's copy instead of deleting it.

## Shoals (project corrections)

When you correct how this skill triages or scopes findings, it records the lesson
in `.claude/shoals/phi-scan.phi-scan.md` in your project and reads it back on the
next run. It records *judgment only* — never a matched PHI value. The file is
append-only and committed by default (teammates inherit it) — `.gitignore` it if
you'd rather keep it per-developer.

## License

MIT
