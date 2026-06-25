# RBAC Audit Report

**Scope:** {{scope}}
**Date:** {{scan_date}}
**Codebase:** {{codebase_name}}

---

## Executive Summary

{{executive_summary}}

---

## Scanner Summary

| Metric | Value |
|--------|-------|
| ViewSets scanned | {{total_viewsets}} |
| Without explicit permissions | {{viewsets_without_explicit_permissions}} |
| Through-model viewsets without perform_create | {{through_model_viewsets_without_perform_create}} |
| Serializers with PHI filter | {{serializers_with_phi_filter}}/{{total_serializers}} |
| Hardcoded role name locations | {{hardcoded_role_name_locations}} |
| Unclassified views | {{unclassified_view_count}} |

---

## Role-Permission-Resource Matrix

<!-- Columns are the roles DISCOVERED in this codebase — replace the example
     header below with the actual role names. Always keep Staff (intentional
     bypass) and Unauthenticated columns. -->

| Resource | Staff | {{role_a}} | {{role_b}} | … | Unauthenticated |
|----------|-------|------------|------------|---|-----------------|
{{#each role_permission_matrix}}
| {{resource}} | {{staff}} | {{role_a}} | {{role_b}} | … | {{unauthenticated}} |
{{/each}}

---

## Findings

### Critical

{{#each findings_critical}}
#### {{id}}: {{title}}
- **Type:** `{{type}}`
- **Location:** `{{location}}`
- **Description:** {{description}}
- **Impact:** {{impact}}
- **Evidence:** {{evidence}}
- **Recommendation:** {{recommendation}}

{{/each}}
{{#unless findings_critical}}
_No critical findings._
{{/unless}}

### High

{{#each findings_high}}
#### {{id}}: {{title}}
- **Type:** `{{type}}`
- **Location:** `{{location}}`
- **Description:** {{description}}
- **Impact:** {{impact}}
- **Evidence:** {{evidence}}
- **Recommendation:** {{recommendation}}

{{/each}}
{{#unless findings_high}}
_No high findings._
{{/unless}}

### Medium

{{#each findings_medium}}
#### {{id}}: {{title}}
- **Type:** `{{type}}`
- **Location:** `{{location}}`
- **Description:** {{description}}
- **Impact:** {{impact}}
- **Evidence:** {{evidence}}
- **Recommendation:** {{recommendation}}

{{/each}}
{{#unless findings_medium}}
_No medium findings._
{{/unless}}

### Low

{{#each findings_low}}
#### {{id}}: {{title}}
- **Type:** `{{type}}`
- **Location:** `{{location}}`
- **Description:** {{description}}
- **Impact:** {{impact}}
- **Evidence:** {{evidence}}
- **Recommendation:** {{recommendation}}

{{/each}}
{{#unless findings_low}}
_No low findings._
{{/unless}}

---

## Verified Secure Patterns

{{#each verified_secure_patterns}}
- {{this}}
{{/each}}

---

## Methodology Notes

**Checked:**
{{#each methodology.checked}}
- {{this}}
{{/each}}

**Out of scope:**
{{#each methodology.out_of_scope}}
- {{this}}
{{/each}}

**Tools used:** {{methodology.tools}}
