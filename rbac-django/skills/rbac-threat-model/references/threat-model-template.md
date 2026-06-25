# RBAC Threat Model

**Application:** {{APPLICATION_NAME}}
**Date:** {{DATE}}
**Domain:** {{DOMAIN}}
**Input mode:** {{INPUT_MODE}}

## System Profile

### Principals
| Principal | Trust Level | Tenant Scope | Notes |
|-----------|------------|--------------|-------|
| {{PRINCIPAL}} | {{TRUST_LEVEL}} | {{TENANT_SCOPE}} | {{NOTES}} |

### Asset Classification
| Asset Category | Sensitivity | Regulatory Scope | Intended Access |
|---------------|-------------|-----------------|-----------------|
| {{ASSET_CATEGORY}} | Tier {{1-3}} | {{REGULATORY_SCOPE}} | {{INTENDED_ACCESS}} |

### Access Channels
| Channel | Assets Reachable | Auth Enforcement |
|---------|-----------------|-----------------|
| {{CHANNEL_TYPE}} | {{ASSETS_REACHABLE}} | {{AUTH_ENFORCEMENT}} |

## Abuse Cases

<!-- Group by criticality tier. Assign AC numbers sequentially top-to-bottom. Omit empty tiers. -->

### CRITICAL

<!-- Repeat this block for each abuse case in this tier. -->

#### [AC-{{N}}]: {{TITLE — phrased as attacker action}}

**BIL Score:** {{SCORE}} (Blast: {{1-3}}, Sensitivity: {{1-3}}, Exploitability: {{1-3}})

**Attacker profile:** {{Which principal, what they know, what access they start with}}

**Preconditions:**
- {{What must be true for this to work}}

**Attack path:**
1. {{Step-by-step: what the attacker does}}
2. {{Include specific API calls, parameter manipulation, etc. where known}}

**Impacted assets:** {{Which asset categories, sensitivity tier}}

**Enabling findings:** {{FINDING-ID from audit report, or "None — business logic / integration trust / social engineering"}}

**Detection signals:**
- **Visible:** {{What would appear in logs or monitoring}}
- **Blind spots:** {{What would NOT be logged or detected}}

**Recommended controls:**
- {{Specific technical fix — reference the finding's recommendation if applicable}}
- {{Detection or monitoring improvement}}

---

### HIGH

#### [AC-{{N}}]: {{TITLE}}
<!-- Same block structure as CRITICAL -->

---

### MEDIUM

#### [AC-{{N}}]: {{TITLE}}
<!-- Same block structure as CRITICAL -->

---

### LOW

#### [AC-{{N}}]: {{TITLE}}
<!-- Same block structure as CRITICAL -->

---

<!-- MODE B/C ONLY: Include this section when audit findings were provided. Omit entirely for Mode A. -->

## Findings-to-Abuse Mapping

| Audit Finding | Abuse Case(s) | Risk Amplification |
|--------------|---------------|-------------------|
| {{FINDING_ID}}: {{FINDING_TITLE}} | {{AC-XX, AC-YY}} | {{How findings combine or amplify beyond individual severity}} |
| No finding | {{AC-XX}} | {{Why code scanning cannot detect this}} |

<!-- END MODE B/C ONLY -->

## Risk Summary

### By Criticality
| Level | Count | Top Abuse Case |
|-------|-------|---------------|
| CRITICAL | {{N}} | AC-{{XX}}: {{TITLE}} |
| HIGH | {{N}} | AC-{{XX}}: {{TITLE}} |
| MEDIUM | {{N}} | AC-{{XX}}: {{TITLE}} |
| LOW | {{N}} | AC-{{XX}}: {{TITLE}} |

### Recommended Remediation Order
1. {{First — why this one first, which AC-XX it addresses}}
2. {{Second}}
3. {{Third}}

## Assumptions and Limitations
- {{What was modeled and what was not}}
- {{Infrastructure-level access, DB direct access, and insider threats beyond role abuse are out of scope unless explicitly requested}}
- {{Staff/superuser abuse is out of scope by default — they have legitimate full access}}
- {{Verified secure patterns from audit (if available): list patterns confirmed correct that were NOT modeled as abuse cases}}
