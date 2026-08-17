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
| Routes ({{routes_resolved}} resolved · {{routes_router_inferred}} router-inferred · {{routes_unresolved}} unresolved) | {{total_routes}} |

---

## Route Exposure

<!-- Draw EXACTLY the clusters in the scanner's `route_clusters` array — one
     diagram each, in the order given. Do not add a cluster it omitted and do
     not skip one it included: whether a shape branches is a data question the
     scanner already answered (a view reached by >1 route, or sharing a
     permission class), so it is not yours to re-decide here. Each cluster
     carries its `reason` — use it as the note under the diagram.

     If `route_clusters` is empty, keep the {{#unless}} fallback and draw
     nothing. Never draw one graph of the whole API.

     Unresolved hops are RENDERED, never dropped (nautilai convention #14,
     rule 3): a route graph that silently omits an edge it could not follow
     reads as the complete authorization surface and gets trusted as one. Use
     each route's `resolution` verbatim — dashed edge to `?` for unresolved —
     and keep the legend. -->

{{#each route_clusters}}
### {{view}}

```mermaid
flowchart LR
{{cluster_mermaid}}
```

Qualified because it is {{reason}}.

{{/each}}
{{#if route_clusters_omitted}}
> {{route_clusters_omitted}} further qualifying cluster(s) were not drawn (cap of
> 5). They are listed in `rbac-audit-findings.json`; this section is a sample,
> not the full set.
{{/if}}
{{#unless route_clusters}}
No view in this codebase is reached by more than one route or shares a
permission class, so every route path is a straight line — described in the
findings rather than drawn.
{{/unless}}

**Legend.** Solid edge = statically resolved. Dashed edge to `?` = the scanner
could not follow this hop (`include()` chain, DRF router expansion, string view
reference, or a computed pattern); the real route may reach the view by a path
not shown. A finding that depends on an unresolved hop is reported at reduced
confidence and says so.

{{#if routes_unresolved}}
> **{{routes_unresolved}} of {{total_routes}} routes are unresolved.** This graph
> is not the complete authorization surface. Confirm those hops by hand before
> treating an absent edge as proof that a view is unreachable.
{{/if}}

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
