# Report template

Use this structure for the final report (workflow step 4). Findings-first: lead
with what matters, omit empty sections. Only include the OWASP section if the
optional pass (step 3) actually ran.

```
## PHI Scan Results

### Summary
- Files scanned: X
- PHI candidates: X (high-confidence: X, likely false positive: X, manual review: X)
- OWASP findings: X        ← only if the OWASP pass ran

---

## PHI Findings

### High-confidence PHI
- `file:line` — <type> — <value or redaction> — <recommended fix>

### Likely false positives
- `file:line` — <type> — why it's probably not PHI (test data, config, copyright date, etc.)

### Requires manual review
- `file:line` — what needs a human decision (ambiguous name, context-dependent date, possible MRN)

---

## OWASP Findings        ← omit this whole section if the OWASP pass didn't run

### Critical
- Hardcoded secrets, raw-SQL injection

### High
- XSS vectors (mark_safe / innerHTML), sensitive data in logs

### Medium
- Missing permission_classes / authz gaps

---

## Recommendations

**Immediate:**
1. <critical PHI exposures>
2. <critical security issues, if any>

**Short-term:**
1. <high-severity items>

**Best practices:**
1. <medium/low items; e.g. add a phi-scan pre-commit hook>
```

Notes:
- Redact actual PHI values in the report where possible (`536-**-****`) rather than re-printing them in full.
- For each high-confidence PHI item, give a concrete remediation (remove, move to env, de-identify per Safe Harbor), not just a flag.
- If the OWASP pass was skipped (non-Django/React repo), say so in one line instead of showing an empty section.
