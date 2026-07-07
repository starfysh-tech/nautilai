---
name: phi-scan
description: Scan a repo for Protected Health Information (PHI under HIPAA Safe Harbor) — SSNs, emails, phones, IPs, dates, restricted ZIP codes — using a deterministic scanner, then AI-triage the findings to filter false positives and catch what regex misses (names, MRNs). Optionally runs Django/React OWASP grep checks when that stack is detected. Use when the user mentions a PHI scan, HIPAA scan, de-identification check, 'find leaked patient data', wants compliance evidence before a PR or release, or (for the OWASP add-on) a quick secrets/SQLi/XSS sweep of a Django or React repo.
argument-hint: "[path] [--all] [--verbose]"
context: fork
allowed-tools: [Read, Glob, Grep, Task, Bash(python3:*), Bash(grep:*)]
---

# PHI Scan

Scan a codebase for Protected Health Information under the HIPAA Safe Harbor
standard, then apply AI judgment to separate real exposure from noise. An
optional, stack-gated OWASP grep pass covers common Django/React web
vulnerabilities.

The deterministic PHI layer is the core of this skill. The OWASP layer is a
convenience add-on — shallow `grep` heuristics, not a real SAST. It is **off by
default** and only worth running on Django and/or React codebases. For serious
security scanning, pair this with dedicated tools (gitleaks, semgrep, bandit).

## Workflow

Run these in order. Stop after any step if the user wants to review before continuing.

### 1. Run the PHI scanner

The scanner is bundled with this plugin. Invoke it directly:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/phi_check.py $ARGUMENTS --verbose
```

- No path argument → scans **staged files** (git). Pass a path/files to scan those, or `--all` for the whole tree.
- Requires `python3` (stdlib only; Python 3.10+). It exits non-zero when non-test PHI is found, so it also works as a git pre-commit hook.
- The scanner already filters obvious test data (markers like `test`, `mock`, `@example.com`, `123-45-6789`, files under `/tests/` or `/fixtures/`) and honors inline `# phi-safe` / `// phi-safe` / `<!-- phi-safe -->` suppressions.

### 2. AI-triage the PHI findings

The scanner is deterministic regex; your job is the judgment it can't do. When findings span more than ~5 files, fan the per-file triage out to parallel subagents (Task, `general-purpose`, model: haiku) — one per file or small batch, each returning confirm/dismiss/needs-manual-review plus a one-line rationale — and synthesize the results. Below that, triage inline. For each finding (and by reading the flagged files):

1. **Confirm or dismiss context** — is it test/mock/seed data, a config value, or a comment *about* PHI handling rather than actual PHI?
2. **Catch what regex missed** — scan free text in the flagged files for names (`Patient: …`, `Dr. …`), medical record numbers (org-specific formats), rare conditions, or uniquely identifying circumstances.
3. **Judge dates** — a `MM/DD/YYYY` or ISO date is only PHI if it's patient-related; copyright years, build timestamps, and changelog dates are not.
4. **Judge ZIPs** — the scanner flags the 17 HIPAA-restricted prefixes (population < 20,000) at higher priority; other 5-digit numbers may not be ZIPs at all.

### 3. (Optional) OWASP pass — only if the stack matches

Detect the stack first; only run the checks that apply:

- **Django present** (`manage.py`, `settings.py`, or `*.py` with Django imports) → run the Django checks.
- **React/TS present** (`.tsx`/`.jsx` files, `react` in `package.json`) → run the React checks.
- **Neither** → skip this step and say so; the OWASP grep recipes are Django/React-specific and produce noise or nothing elsewhere.

When the stack matches, read `references/owasp-checks.md` and run the applicable recipes (hardcoded secrets, SQL injection, XSS, authz gaps, sensitive logs).

### 4. Generate the report

Produce a structured, findings-first report. See `references/report-template.md`
for the exact format. Lead with high-confidence PHI; group likely false
positives and manual-review items separately; append OWASP findings only if step
3 ran.

> This plugin also ships a git pre-commit hook (`scripts/pre-commit`) that runs
> this same scanner. Installing it and migrating from older loose copies of
> `phi_check.py` / the previous `phi-security` skill are one-time setup steps —
> see the phi-scan plugin README. They're deliberately not part of this skill's
> recurring workflow.

## Finding dispositions

This skill never auto-remediates (nautilai convention). Disposition of every
finding: **auto-fix** — *none*; **report** — scanner candidates, triage results,
and OWASP grep hits, surfaced in the report; **ask-user** — confirmed PHI exposure,
where the remediation (redact, move to a fixture, suppress) is the user's call.
Don't edit code to "fix" PHI on your own — report it and let the user decide.

## What gets detected

### PHI (deterministic, via `phi_check.py`)

| Type | Pattern | Notes |
|------|---------|-------|
| SSN | `XXX-XX-XXXX` | Excludes 000 / 666 / 9XX area prefixes |
| Email | RFC-lite | Standard email format |
| Phone | US format | `+1`, parentheses, separators |
| IPv4 | dotted quad | Valid octet ranges only |
| Date (US) | `MM/DD/YYYY` | Context-judged in triage |
| Date (ISO) | `YYYY-MM-DD` | Context-judged in triage |
| ZIP | 5-digit | 17 HIPAA-restricted prefixes prioritized |

### OWASP (optional, Django/React grep heuristics)

See `references/owasp-checks.md`: hardcoded secrets, raw-SQL injection, `mark_safe`/`innerHTML` XSS, missing `permission_classes`, PHI/secrets in logs.

## HIPAA reference

- **17 restricted ZIP prefixes** (population < 20,000 — replace with `000`): `036, 059, 063, 102, 203, 556, 692, 790, 821, 823, 830, 831, 878, 879, 884, 890, 893`.
- **Safe Harbor dates**: keep year only (drop month/day); ages > 89 aggregate to "90+".
- Source: [HHS De-identification Guidance](https://www.hhs.gov/hipaa/for-professionals/special-topics/de-identification/index.html).

## Gotchas

- **The scanner finds candidates, not confirmed PHI.** A `[PHI]` marker means "matched a pattern" — step 2 (AI triage) is what turns candidates into a real finding. Don't report raw scanner output as confirmed exposure.
- **It detects formats, not names.** Free-text names, MRNs, and rare conditions are invisible to regex; only the triage step catches them. Read the flagged files.
- **ZIP false positives are common.** Any 5-digit number matches; most aren't ZIPs. Lean on context.
- **The OWASP pass is Django/React-only and shallow.** Don't present it as a complete security audit. If the repo isn't Django/React, skip it.
- **Test data is filtered by default.** Pass `--include-test-data` to the scanner to see suppressed test findings (useful when a fixture accidentally contains real data).

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/phi-scan.phi-scan.md` from the project
root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — what you treat as a false positive, what
you flag, or how you scope the scan — append a shoal to that file (creating
`.claude/shoals/` if needed):

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
narrate it. (This records triage *judgment*, never PHI itself — never write a
matched value into a shoal.)
