---
name: rbac-threat-model
description: >-
  Think like an attacker who already holds a valid account. Generate ranked abuse cases for RBAC
  misuse — privilege escalation, tenant boundary violations, data exfiltration through legitimate
  access patterns, and role confusion — given an app's roles, tenants, and data categories (with
  or without audit findings). Use when the user mentions a threat model, abuse cases, attacker
  stories, RBAC risk assessment, privilege-escalation scenarios, "how would an attacker exploit
  this", or "prioritize these RBAC findings by business impact". Complements rbac-audit-django:
  the audit finds code-level gaps; this skill translates them into business-risk narratives.
context: fork
allowed-tools: [Read, Glob, Grep, Write]
---

# RBAC Threat Model

Generate adversarial abuse cases for any RBAC system. Where the audit skill asks
"is this permission check correct?", this skill asks "if I were a malicious
insider with a valid account, what's the most damage I could do?"

Code-level severity and business-level risk diverge. A "Medium" missing check on
a bulk-export endpoint can be a critical threat if it exposes regulated data
across tenant boundaries. This skill bridges that gap. It is **advisory** — it
produces a report; it never edits code.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/rbac-django.rbac-threat-model.md`
from the project root if it exists, and honor every entry. When the user corrects
your behavior (which assets are out of scope, how to weight BIL, which principals
to model), append a shoal using the format at the end of this file. Append-only;
dedup on **Trigger**; explicit behavioral corrections only; never write outside
`.claude/shoals/`. See `docs/conventions/shoals.md`.

## When to use this vs rbac-audit-django

| Question | Use |
|----------|-----|
| "Are our permission classes correct?" | rbac-audit-django |
| "What could a compromised account do?" | **this skill** |
| "Scan our viewsets for missing authz" | rbac-audit-django |
| "Prioritize these findings by business impact" | **this skill** |
| "Full security review" | rbac-audit-django first, then feed output here |

## Inputs — three modes

- **Mode A — App description only:** the user describes roles, tenants, data categories, integrations. Generate abuse cases from first principles.
- **Mode B — Audit findings only:** parse `rbac-audit-django` output (or any structured findings) and generate abuse cases that exploit the discovered gaps.
- **Mode C — Both (recommended):** cross-reference findings with the role model — the richest output.

If the user doesn't specify, ask which mode. **Auto-lookup:** when they say "use
the audit findings" or "threat model our RBAC" without a path, check
`docs/rbac-audit/` for `rbac-audit-findings.json` (preferred) or `report.md`.

## Methodology: PACE

An RBAC-specific framework (not STRIDE, not OWASP top-10) focused on who can do
what to which data through which paths.

### P — Principals

Enumerate every actor: each defined role, unauthenticated users, service
accounts / integration tokens, automated processes (cron, webhooks, workers).
Use the app's *actual* role names. For each, document: **intended access**,
**adjacent access** (reachable if one check fails), **forbidden access**. Abuse
cases live in the gap between adjacent and forbidden.

### A — Assets

Classify data by sensitivity:

| Tier | Description | Breach consequence | Examples |
|------|-------------|-------------------|----------|
| **Tier 1** | Regulated / high-sensitivity | Legal/regulatory action, mandatory breach notification | PHI, PII, financial records, consent docs, credentials |
| **Tier 2** | Business-confidential | Competitive harm, contractual breach | Internal analytics, pricing, org structure, protocols |
| **Tier 3** | Operational | Minor inconvenience | UI prefs, feature flags, non-sensitive metadata |

Map each Tier 1/2 asset to which principals touch it and through which paths.

### C — Channels

Access paths often left open while the front door is locked: direct API
endpoints, nested serializer inclusion, export/download endpoints, search/filter
enumeration, integration webhooks, admin panel, error/debug responses, logs and
audit trails.

### E — Escalation paths

For each principal, how they gain a higher-privileged principal's capabilities:
**horizontal** (same role, different tenant), **vertical** (lower role gains
higher capability), **integration** (abuse an external trust relationship), **role
confusion** (ambiguous role assignment, self-assignment, a name that grants
unintended permissions).

## Generating abuse cases

For each principal + asset + channel that crosses a trust boundary, answer:
**starting position**, **single failure** (the one thing that goes wrong), **what's
exposed**, **discovery method**, **audit trail** (what it does *not* log is the
danger), and **enabling findings** (if audit findings are available).

Generate 5-10 cases. Fewer than 5 = under-analysis; more than 10 = under-
prioritization (combine or drop low-impact). **Group by criticality tier**
(CRITICAL → HIGH → MEDIUM → LOW); assign AC numbers sequentially top-to-bottom
after grouping. A compound case scoring CRITICAL goes in the CRITICAL group, not
a trailing "summary."

## Risk scoring: BIL

BIL (Business Impact Level) scores each case on three 1-3 dimensions:

| Dimension | 1 (Low) | 2 (Medium) | 3 (High) |
|-----------|---------|------------|----------|
| **Blast radius** | Single record/user | Multiple within one tenant | Cross-tenant or all-tenant |
| **Data sensitivity** | Tier 3 | Tier 2 | Tier 1 (regulated) |
| **Exploitability** | Insider knowledge + coordinated steps | Valid account + parameter tampering | Discoverable by any authed user via normal UI/obvious API |

**BIL** = Blast × Sensitivity × Exploitability (1-27).

| Criticality | BIL | Meaning |
|------------|-----|---------|
| **CRITICAL** | 18-27 | Immediate remediation; regulatory exposure / cross-tenant regulated leak |
| **HIGH** | 8-17 | This sprint; significant exposure within a trust boundary |
| **MEDIUM** | 4-7 | This quarter; limited scope, effort to exploit |
| **LOW** | 1-3 | Tech debt; theoretical/low-impact |

BIL intentionally diverges from code-level severity — that divergence surfaces
the findings that matter most to the business.

## Consuming audit findings (Mode B/C)

Read `docs/rbac-audit/rbac-audit-findings.json` (preferred) or `report.md`.

1. **Parse by finding type** — `missing-authz`, `cross-tenant`, `idor`, `over-privileged`, `data-leak`, `inconsistent-role`, `inline-check`, `frontend-mismatch`, `role-name-coupling`, `write-side-gap`, `phi-filter-gap`, `logging-gap`.
2. **Map each finding to ≥1 abuse case.** When the finding cites a `file:line`, carry that citation into the abuse case's enabling-findings so the chain stays evidence-grounded; don't invent code facts the audit didn't establish.
3. **Cross-reference** — two "Medium" findings may compound into a CRITICAL case.
4. **Use `verified_secure_patterns` as dark spots** — acknowledge in Assumptions; do not generate abuse cases for them.
5. **Flag undetectable cases** — business-logic / social-engineering / integration-trust abuse that code scanning can't surface.

### Finding type → typical abuse pattern

| Finding type | Typical abuse pattern |
|-------------|----------------------|
| `missing-authz` | Under-privileged access to protected resource |
| `cross-tenant` | Horizontal escalation across tenants |
| `idor` | Object-reference manipulation to reach unauthorized records |
| `over-privileged` | Compromised account has outsized blast radius |
| `data-leak` | Sensitive fields via serializers / nested relations / errors |
| `write-side-gap` | Read-only role mutates through unprotected create endpoint |
| `phi-filter-gap` | Regulated data accessible without filtering/logging |
| `logging-gap` | Abuse leaves no audit trail |
| `role-name-coupling` | Permission logic depends on role-name strings |
| `frontend-mismatch` | UI hides what the API still allows |

## Output

Read `${CLAUDE_PLUGIN_ROOT}/skills/rbac-threat-model/references/threat-model-template.md`
and populate it. Replace all `{{PLACEHOLDER}}` values; do not add, remove, or
reorder sections. Repeat the abuse-case block per case. The `Findings-to-Abuse
Mapping` section is Mode B/C only — delete it entirely for Mode A. Group by tier,
then number top-to-bottom.

Write the report to `docs/rbac-audit/threat-model.md` (alongside the audit output,
so `rbac-remediation-playbooks` can consume the whole pipeline from one directory).

## Finding dispositions

This skill is propose-only — it never edits code.

- **auto-fix** — *none.*
- **report** — every abuse case, the BIL ranking, the risk summary, and the recommended remediation order. This is the skill's product: surface it and stop.
- **ask-user** — acting on any recommended control. The threat model proposes; deciding to remediate (and how) is the user's call, handed to `rbac-remediation-playbooks`. Never self-resolve a proposed control or downgrade a CRITICAL case on your own.

## Caveats

- Adversarial analysis, not penetration testing — theoretical paths, not confirmed exploits.
- BIL scores are relative within this app, not absolute across apps.
- Mode A cases are hypothetical; validate against code before prioritizing.
- Integration cases need each external system's real trust model; state it as an assumption if unknown.
- Staff/superuser abuse is out of scope by default (intentionally broad access). Model insider threat only if the user explicitly asks.

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
