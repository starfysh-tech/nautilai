---
name: rbac-audit-django
description: Audit a Django/DRF + React codebase for role-based access control gaps — missing permission classes, unfiltered querysets (tenant isolation), IDOR, write-side scope gaps, serializer data leaks, and role-name coupling. Runs a deterministic scanner, then applies judgment to produce severity-ranked, evidence-cited findings plus a role-permission-resource matrix. Use when the user mentions an RBAC audit, authorization review, tenant-isolation check, "find missing permission_classes", IDOR review, or wants a security audit of a Django/DRF API before a PR or release.
argument-hint: "[path-or-app] [--scope backend|frontend|full] [--role-docs path]"
context: fork
allowed-tools: [Read, Glob, Grep, Bash(python3:*), Bash(rg:*), Bash(ast-grep:*), Bash(mkdir:*)]
---

# RBAC Audit for Django/DRF

Audit a Django REST Framework backend (and optionally its React frontend) for
role-based access control gaps, tenant isolation leaks, and authorization
enforcement issues. A deterministic scanner builds the inventory; you supply the
judgment. Output is a severity-ranked, evidence-cited findings report.

RBAC bugs are silent — a missing `permission_classes` or an unfiltered queryset
doesn't crash, it quietly serves data to the wrong user. In regulated contexts
(PHI/PII) that is a reportable breach. This audit catches the *absence* of
enforcement, which tests rarely cover.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/rbac-django.rbac-audit-django.md`
from the project root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — what you treat as an intentional pattern,
what you flag, or how you scope the audit — append a shoal to that file
(creating `.claude/shoals/` if needed) using the format at the end of this file.
Append-only; dedup on **Trigger**; capture explicit behavioral corrections only.
Never write outside `.claude/shoals/`.

## Inputs

- **Path or app name** (optional): scope the audit to a directory or Django app. Defaults to the auto-detected backend root.
- **`--scope`**: `backend` (default), `frontend`, or `full` (both).
- **`--role-docs path`**: path to existing RBAC docs. If provided, audit against documented intent — not just code patterns.

If no path is given, auto-detect the backend: find the directory containing
`manage.py` (e.g. via `Glob` for `**/manage.py`). Don't assume a fixed layout.

## Workflow

Run in order. Stop after any phase if the user wants to review before continuing.

### Phase 0: Run the scanner

The scanner is bundled with this plugin. Invoke it via `${CLAUDE_PLUGIN_ROOT}`,
never a hardcoded path:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/rbac-audit-django/scripts/rbac_scanner.py <backend-path>
```

- Requires `python3` (stdlib only; Python 3.10+). `ast-grep` and `rg` are preferred but **optional** — the scanner degrades to stdlib AST/file-walks if they're absent and reports reduced coverage in `tool_warnings`. If `python3` itself is missing, fall back to manual `Grep`/`Glob` inspection and say so.
- Read `tool_availability` / `tool_warnings` in the output first — if a tool is missing, the structural inventory is thinner, so lean harder on manual reading.

The scanner self-discovers role names, the PHI mixin, and through-models from the
codebase — it does **not** hardcode any app or role names. It outputs JSON with
`viewsets`, `permission_classes`, `queryset_managers`, `role_name_strings`,
`group_permissions`, `serializer_phi_coverage`, and a `summary`.

**Read `summary` first.** Non-zero counts are your starting points. The scanner
does the inventory; your job is judgment — which flagged items are real issues
vs. intentional design. Save the output and reference it throughout.

### Phase 1: Discover the RBAC model

Understand *intent* so you don't flag intentional patterns as bugs.

1. **Roles**: read the User model to see how roles are assigned (groups, membership models, role fields). The scanner's `permission_classes` section is the mechanical inventory.
2. **Permission classes**: read each one the scanner listed — the scanner says which methods exist (`has_permission` / `has_object_permission`); you read the logic inside.
3. **Tenant boundaries**: identify the multi-tenancy model (organization, clinic, team, workspace — whatever this codebase calls it). Look for FK relationships to the tenant entity, custom QuerySet managers (`for_user()`, `for_tenant()`), and tenant-scoping filter backends.
4. **Role docs**: if `--role-docs` was passed or a docs file exists, compare documented roles against enforced code.
5. **Role-identity coupling**: determine whether authorization checks against *role-name strings* (e.g. `groups.filter(name="…")`) or *model permissions* (`user.has_perm("app.action")`). Name-string checks break silently when a group is renamed. The scanner's `role_name_strings` section locates hardcoded names; flag cross-cutting backend/frontend coupling as `role-name-coupling` (Medium). Cite `file:line` for each.

### Phase 2: Audit authorization touchpoints

Read the flagged items from the scanner and make judgment calls. **Every claim
about the code carries a `file:line`** (or quoted evidence); if you can't verify,
say "unverifiable" — never guess.

- **Permission classes**: viewsets where `permission_classes` is `DEFAULT` rely on `DEFAULT_PERMISSION_CLASSES`. Read settings to learn the baseline, then judge sufficiency. Same for `@api_view` functions without `@permission_classes`.
- **Queryset filtering (tenant isolation)**: for viewsets the scanner flags with `has_get_queryset: false`, and for those with a `get_queryset()` override, verify non-staff users are filtered by *their* memberships (not a forgeable request param). Red flags: `Model.objects.all()` unfiltered; filtering by `?tenant_id=` without validating access.
- **Object-level checks**: when a view uses `self.get_object()`, at least one permission class must implement `has_object_permission()`. Red flag: `get_object_or_404(Model, pk=pk)` directly, bypassing the DRF permission pipeline.
- **Custom actions**: `@action` methods handling sensitive ops (delete, export, state change) need appropriate `permission_classes`.
- **Write-side validation**: read-side filtering doesn't protect creates. For membership/through-model viewsets, check `perform_create()`/`perform_update()`/`perform_destroy()` validate the target FK is within the user's scope. The scanner lists membership viewsets lacking `perform_create()` — absence here is a privilege-escalation vector (`write-side-gap`, High).
- **Serializer data exposure**: nested serializers that don't filter by tenant, `SerializerMethodField` querying without user context, writable FK fields accepting other tenants' IDs. If the codebase has a PHI/sensitive-data filter mixin, verify coverage across every serializer that touches that data (`phi-filter-gap`).
- **Inline role checks**: `user.role ==`, `is_staff`, `groups.filter`, `has_perm(` scattered through view logic instead of centralized permission classes (`inline-check`). Cite each.

### Phase 3: Frontend authorization (only if `--scope` includes frontend)

Frontend checks are UX guardrails, not security. Auto-detect the frontend root
(e.g. `Glob` for `**/package.json` with a `react` dependency) — don't assume
`client/`. Check route guards, role-based conditional rendering, 403 handling,
and whether the frontend role enum matches what the backend serializer returns.
Mismatches are `frontend-mismatch` (Low). Cite `file:line`.

### Phase 4: Build the role-permission-resource matrix

From Phases 1-3, construct a matrix: rows are resources × actions, columns are
roles (use the *discovered* role names, not example names). If role docs were
provided, flag discrepancies between the matrix and documented intent.

### Phase 5: Classify and report

Group findings by severity and type. Write two outputs to `docs/rbac-audit/`
(create it; recommend the user gitignore it — outputs may quote sensitive code):

1. **`docs/rbac-audit/rbac-audit-findings.json`** — structured findings for downstream skills. Populate from `${CLAUDE_PLUGIN_ROOT}/skills/rbac-audit-django/templates/findings.json`.
2. **`docs/rbac-audit/report.md`** — human-readable. Populate from `${CLAUDE_PLUGIN_ROOT}/skills/rbac-audit-django/templates/report.md`.

Read the templates first, then populate. Include the scanner's `summary` as
`scanner_summary` in the JSON so downstream tools don't re-run the scanner.
Report **findings-first**: lead with Critical/High; omit clean categories rather
than narrating "checked X, found nothing"; no per-step process narration.

## Finding dispositions

Per the nautilai finding-dispositions convention, every finding maps to one of:

- **auto-fix** — *none.* This is a security audit; it never edits code to "fix" an authorization gap. A wrong silent edit to auth logic is unrecoverable in the way that matters.
- **report** — the scanner inventory, the role-permission matrix, verified-secure patterns, and every Low/Medium finding where remediation is informational. Surface and stop.
- **ask-user** — every Critical/High finding (missing-authz, cross-tenant, idor, write-side-gap, data-leak/phi-filter-gap). These need human judgment on remediation and possibly disclosure. **Only surface and wait** — never self-resolve, never decide a finding is "not worth fixing," and never skip one as trivial. Remediation is the `rbac-remediation-playbooks` skill's job, gated on the user.

If the user asks for fixes, hand off to `rbac-remediation-playbooks` (which reads
this skill's `docs/rbac-audit/` output) rather than editing inline.

## Finding type definitions

| Type | Description | Typical severity |
|------|-------------|-----------------|
| `missing-authz` | View/endpoint has no permission enforcement | Critical/High |
| `cross-tenant` | Queryset doesn't filter by user's tenant | Critical |
| `idor` | Object lookup without ownership validation | Critical/High |
| `over-privileged` | Role has more access than documented/intended | Medium/High |
| `data-leak` | Serializer exposes data across tenant boundaries | High |
| `inconsistent-role` | Same role enforced differently across endpoints | Medium |
| `inline-check` | Authorization logic outside permission classes | Medium/Low |
| `frontend-mismatch` | Frontend guards don't match backend enforcement | Low |
| `role-name-coupling` | Auth decisions depend on hardcoded group-name strings | Medium |
| `write-side-gap` | Membership/through-model create lacks scope validation | High |
| `phi-filter-gap` | Serializer handles sensitive data but lacks the filter mixin | High |
| `logging-gap` | Authorization decisions not logged for audit trail | Low |

## Important caveats

- **Staff bypass is usually intentional.** Don't flag `if user.is_staff: return all()` unless docs say otherwise — but note staff reach in the matrix.
- **`DEFAULT_PERMISSION_CLASSES` matters.** Read settings before flagging views with no explicit `permission_classes`.
- **Test code is not production code.** Don't flag factories, fixtures, or mocks. The scanner already skips `/tests/` and `/migrations/`.
- **`AllowAny` on auth endpoints** (login, password reset, health check) is correct.
- **Verify before claiming.** Trace the full request path — middleware → permission class → queryset → serializer — before reporting a gap. A "missing" check at one layer may be enforced at another. Cite the evidence; if you can't trace it, mark it unverifiable.

## Shoal entry format

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger**. Mention a capture in one line; don't
narrate it. Never write a sensitive value (PHI/PII/secret) into a shoal — record
judgment only. See `docs/conventions/shoals.md`.
