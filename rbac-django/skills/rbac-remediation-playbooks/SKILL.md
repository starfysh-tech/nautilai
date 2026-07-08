---
name: rbac-remediation-playbooks
description: Turn rbac-audit-django findings (and optionally rbac-threat-model abuse cases) into prioritized remediation playbooks — concrete implementation steps, test scaffolds, and ready-to-paste GitHub issues — using the project's own discovered RBAC patterns rather than generic advice. Use when the user has RBAC audit findings and asks for a remediation plan, fix playbooks, "how do I fix these authz gaps", or GitHub issues for the findings. Consumes audit output; it does not re-run the audit.
argument-hint: "[audit-report-path] [--with-diffs [FINDING-ID]]"
disable-model-invocation: true
context: fork
allowed-tools: [Read, Glob, Grep, Bash(python3:*), Bash(rg:*), Bash(ast-grep:*), Write]
---

# RBAC Remediation Playbooks

Turn audit findings into implementable work: prioritized playbooks with concrete
steps, test scaffolds, and GitHub issues. This skill consumes output from
`rbac-audit-django` (and optionally `rbac-threat-model`). It does **not** re-run
audits — it transforms findings into action.

Diagnosis and remediation are kept separate so the audit stays sharp (find and
describe) and the fixes stay opinionated and concrete (use the project's
established patterns, not generic OWASP advice). This skill is **user-invoked
only** (`disable-model-invocation: true`) — fixing security findings is a
deliberate act, not something the model should auto-fire.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/rbac-django.rbac-remediation-playbooks.md`
from the project root if it exists, and honor every entry. When the user corrects
how you cluster, prioritize, or shape playbooks, append a shoal using the format
at the end of this file. Append-only; dedup on **Trigger**; explicit behavioral
corrections only; never write outside `.claude/shoals/`. See
`docs/conventions/shoals.md`.

## Inputs

The audit and threat-model skills write to `docs/rbac-audit/`. Check there first.

- **Primary:** `docs/rbac-audit/report.md` — findings with IDs (`RBAC-H1`, `RBAC-M1`, …)
- **Structured:** `docs/rbac-audit/rbac-audit-findings.json` — machine-readable findings (severity, type, location, evidence, recommendation)
- **Threat model:** `docs/rbac-audit/threat-model.md` — abuse cases (`AC-01`, …) cross-referencing finding IDs; use BIL scores to inform prioritization
- **Optional:** `--with-diffs [FINDING-ID]` — generate concrete before/after patches (default: text-only steps)
- **Override:** findings pasted in conversation, or a different path as argument, take precedence

If none exist, stop and tell the user:
> "No audit data found in `docs/rbac-audit/` and none provided. Run `/rbac-audit-django` first."

## Workflow

### Phase 0: Discover platform context

Run the discovery script via `${CLAUDE_PLUGIN_ROOT}` (never a hardcoded path):

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/rbac-remediation-playbooks/scripts/discover_platform.py
```

Stdlib-only (Python 3.10+); pass the project root as an optional argument. It
auto-detects the backend (the tree holding `manage.py`) and emits JSON with
`permission_classes`, `groups`, `phi` (mixin class + fields + serializers using
it), `roles`, `finding_types` (the finding vocabulary, read from the sibling
audit skill's SKILL.md so the two stay in sync), and `notes`. The script
**fails open** — gaps appear as `notes`,
not a crash. If `python3` is unavailable, fall back to manual `Grep`/`Glob`
discovery of permission classes, group setup, and any sensitive-data mixin, and
say so. The discovered names — actual class names, file paths, group definitions
— are what every playbook references. Do not invent class or path names; cite
what discovery found.

### Phase 1: Ingest findings

Load from `rbac-audit-findings.json` (preferred) or parse `report.md`. Each
finding has `id`, `title`, `type`, `severity`, `location`, `description`,
`impact`, `evidence`, `recommendation`. Extract the role-permission-resource
matrix from `report.md` if present. If `threat-model.md` exists, parse abuse
cases and their BIL scores for Phase 4 boosting.

### Phase 2: Enrich

For each finding, read the actual current code at its `location` to understand
context. Cross-reference discovery: which permission classes are already on the
view, whether `get_queryset()` already filters by tenant, whether the serializer
already uses the discovered mixin, what group permissions apply. Use `ast-grep`
when available (`ast-grep --pattern 'class $NAME(viewsets.$BASE)' --lang python
<backend>`); fall back to `Grep` otherwise. Tag each finding with the abuse cases
it enables, if a threat model is present. Keep every claim grounded in `file:line`.

### Phase 3: Cluster

Group findings sharing a remediation path — the same viewset, the same
serializer, or the same pattern across multiple viewsets. Keep separate when
findings are in different apps with no shared dependency, or when fixes would
conflict or need different deployment ordering.

### Phase 4: Prioritize

| Priority | Criteria |
|----------|----------|
| **Now** | Critical/High AND (data exposure OR cross-tenant leak OR missing-authz on a write endpoint) |
| **Next** | Medium, or High that needs extra conditions (inconsistent-role, inline-check, over-privileged, role-name-coupling) |
| **Later** | Low, best-practice (logging-gap, cosmetic frontend-mismatch) |

**Threat-model boost:** if a finding enables a high-ranked abuse case, elevate
one band (Later→Next, Next→Now). Within a band, order by: affected resources,
roles impacted, then implementation simplicity (easy fixes first).

### Phase 5: Generate playbooks

For each cluster, produce a playbook using *discovered* class names, file paths,
and group definitions — never placeholder names from this doc.

#### Finding type → fix strategy

| Finding Type | Strategy |
|---|---|
| `missing-authz` | Add appropriate permission class(es) from the discovered set |
| `cross-tenant` | Add `get_queryset()` filtering using the project's tenant-scoping method, with staff bypass |
| `idor` | Use `self.get_object()` (not `get_object_or_404()`) + an object-level permission class |
| `over-privileged` | Update group permissions in the discovered group-setup command |
| `data-leak` | Add the discovered sensitive-data filter mixin to the serializer |
| `write-side-gap` | Add scope validation in `perform_create()`/`perform_update()` — verify the FK target is in the user's tenant scope |
| `phi-filter-gap` | Add the discovered filter mixin + verify field coverage against discovered fields |
| `logging-gap` | Add audit/auth-event logging |
| `inconsistent-role` | Standardize on centralized permission classes from the discovered set |
| `inline-check` | Extract scattered role checks into a permission class |
| `role-name-coupling` | Replace `groups.filter(name=...)` with `has_perm()` checks |
| `frontend-mismatch` | Update frontend route guards (low priority, UX only) |

#### Playbook template

Populate from `${CLAUDE_PLUGIN_ROOT}/skills/rbac-remediation-playbooks/templates/playbook.md`
using *discovered* class names, file paths, and group definitions — never the
placeholder names in the template.

#### When `--with-diffs` is specified

Read the actual current code, then produce before/after patches for the specified
finding or cluster: the exact `permission_classes` change, the exact
`get_queryset()` addition, the exact serializer mixin addition, and complete test
functions. **Present the diffs for the user to review and apply** — do not edit
files yourself (see Finding dispositions). Without `--with-diffs`, provide only
text steps and test outlines.

### Phase 6: Generate GitHub issues

For each cluster, produce a ready-to-paste issue body. Match the project's issue
template if one exists (auto-detect `.github/ISSUE_TEMPLATE/*`); otherwise populate
from `${CLAUDE_PLUGIN_ROOT}/skills/rbac-remediation-playbooks/templates/github-issue.md`.

### Phase 7: Summary table

```markdown
## Remediation Summary

| # | Cluster | Priority | Complexity | Findings | Key Fix |
|---|---------|----------|------------|----------|---------|
| 1 | …       | Now      | S          | RBAC-H1  | …       |

**Now:** N clusters / N findings · **Next:** … · **Later:** …
```

## Output

Write one file per priority band to `docs/rbac-audit/`:
`remediation-now.md`, `remediation-next.md`, `remediation-later.md`. Each is a
self-contained input (playbooks + issue bodies) for a downstream ticket-creation
workflow.

In the conversation, show **findings-first**: the summary table (Phase 7), 2-3
key observations (product decisions needed, threat-model elevations), and next
steps. Point the user to the files for full detail — don't dump every playbook
inline.

## Finding dispositions

This skill proposes remediation; it does not silently apply it.

- **auto-fix** — *none.* Even with `--with-diffs`, it produces patches for the user to review and apply. Editing authorization logic is a judgment call, never a mechanical one; an auto-applied auth "fix" can open a worse hole than it closes.
- **report** — the playbooks, clustering, prioritization, test scaffolds, GitHub issue bodies, and the summary table. Surface them (in conversation + the band files) and stop.
- **ask-user** — applying any change to the codebase. Present the plan/diffs and wait for the user to act. Never decide a finding doesn't need fixing, and never self-resolve an item the audit flagged.

If the user explicitly asks you to apply a specific diff after reviewing it, that
is a separate, consented edit — follow the back-up-before-mutating convention
(make the change VCS-visible and report exactly what changed).

## Error handling

- **No findings:** check `docs/rbac-audit/` first, then direct the user to `/rbac-audit-django`.
- **Unparseable finding:** skip with a warning, continue with the rest.
- **Discovery script fails:** it fails open with `notes`; if `python3` is absent, fall back to manual discovery and say coverage is reduced.
- **Referenced file not found:** note it in the playbook (the file may have moved); suggest a `Glob` search.

## Shoal entry format

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only; retire with `- **Obsolete:** <date> — <reason>`; dedup on
**Trigger**; never store a sensitive value.
