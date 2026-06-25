# RBAC for Django/DRF

Three skills that form a security workflow for role-based access control in any
Django/DRF + React codebase: **audit → threat-model → remediation-playbooks**.
The audit finds code-level authorization gaps; the threat model translates them
into ranked attacker abuse cases; the playbooks turn them into prioritized,
project-specific fixes and GitHub issues.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install rbac-django@nautilai
```

The bundled scanners are stdlib-only Python (3.10+). `ast-grep` and `ripgrep`
(`rg`) are **preferred** for faster structural analysis but optional — the
scanner degrades to stdlib AST/file-walks and reports reduced coverage if either
is missing.

## The workflow

```text
/rbac-audit-django                       # 1. scan + judge → docs/rbac-audit/
/rbac-threat-model                       # 2. abuse cases from the findings
/rbac-remediation-playbooks              # 3. fix playbooks + GitHub issues
```

All three share the `docs/rbac-audit/` directory so the pipeline composes from a
single location. Each skill is also useful standalone.

### 1. `rbac-audit-django`

Audits a Django/DRF backend (and optionally its React frontend) for missing
permission classes, unfiltered querysets (tenant-isolation leaks), IDOR,
write-side scope gaps, serializer data leaks, and role-name coupling. A
deterministic scanner builds the inventory and **self-discovers** role names, the
sensitive-data mixin, and through-models from *your* code — nothing is
hardcoded. You supply the judgment. Output: a severity-ranked, `file:line`-cited
findings report (`report.md` + `rbac-audit-findings.json`).

### 2. `rbac-threat-model`

Thinks like an attacker who already holds a valid account. Generates 5-10 ranked
abuse cases using the PACE framework (Principals, Assets, Channels, Escalation)
and BIL scoring (Business Impact Level). Runs from an app description, from audit
findings, or both. Output: `threat-model.md`.

### 3. `rbac-remediation-playbooks`

Turns audit findings (and optional threat-model abuse cases) into prioritized
remediation playbooks — concrete steps, test scaffolds, and ready-to-paste
GitHub issues — using the project's *discovered* patterns rather than generic
advice. It proposes; it never edits code on its own. This skill is **user-invoked
only** (`disable-model-invocation`), because fixing security findings is a
deliberate act. Output: `remediation-{now,next,later}.md`.

## Conventions

This plugin follows the nautilai house [conventions](../docs/conventions/README.md):

- **Finding dispositions** — these are security audits, so **no finding is ever
  auto-fixed.** The audit and threat-model skills `report` informational findings
  and treat every Critical/High gap as `ask-user`; the remediation skill proposes
  diffs for the user to apply but never edits authorization logic itself. An
  `ask-user` finding is never self-resolved.
- **Evidence-cited** — every claim about your code carries a `file:line` (or is
  marked unverifiable); guesses are not allowed.
- **Findings-first** — reports lead with what's wrong and omit clean categories.
- **Bundled scripts** — invoked via `${CLAUDE_PLUGIN_ROOT}`, stdlib-only, and
  fail-open (a missing optional tool degrades the scan rather than crashing it).
- **Shoals** — each skill reads and appends project corrections to
  `.claude/shoals/rbac-django.<skill>.md` (append-only, committed by default,
  never written outside `.claude/shoals/`). Installing the plugin is consent to
  this behavior. Shoals record *judgment only* — never a sensitive value
  (PHI/PII/secret).

## License

MIT
