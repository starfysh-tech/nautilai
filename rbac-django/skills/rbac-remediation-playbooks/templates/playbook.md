### [CLUSTER-ID]: [Descriptive Title]

**Findings:** RBAC-H1, RBAC-H3
**Priority:** Now | Next | Later
**Complexity:** S (isolated) | M (multi-file) | L (cross-cutting)

#### Target State
[1-3 sentences referencing the role-permission-resource matrix.]

#### Implementation Steps
1. **Permission class** — file `[discovered permissions path]`; add/modify `[discovered class name]`
2. **ViewSet wiring** — file `[finding location]`; change `permission_classes`; add/fix `get_queryset()` filtering
3. **Serializer** — file `[finding location]`; add `[discovered mixin]` (from `[discovered phi file]`); verify discovered fields
4. **Group permissions** — file `[discovered group-setup path]`; add permission tuple to `[GROUP]_PERMISSIONS`
5. **Audit logging** — add the project's audit mixin / log auth decisions

#### Test Scaffold
Use the project's established test patterns (discover them — e.g. pytest +
factory fixtures + DRF `APIClient`, or Django `TestCase`). Provide outlines:
- **Negative:** [role] cannot [action] [resource] outside their tenant scope
- **Positive:** [role] can [action] [resource] within their scope
- **Staff bypass:** staff can [action] across all tenants
- **Edge case:** [from the finding's impact]

#### Verification Checklist
- [ ] Permission class added/modified
- [ ] ViewSet wiring updated
- [ ] `get_queryset()` filters by the user's tenant scope
- [ ] Tests pass (run the project's test command)
- [ ] Manual test: [specific step]
