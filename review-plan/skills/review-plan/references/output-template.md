# Output templates

Two outputs, kept separate on purpose:

- **A + B** go in the plan file.
- **C** goes to the user in chat, never into the plan file.

---

## A. In-place plan revision

Edit the plan so it *becomes* the leanest correct version: apply reuse/delete/
simplify wins and cheapest-correct mitigations directly into the relevant steps.
Do **not** append a validation-results, before/after, or changes log; it confuses
whoever implements the plan later. The only added section is B.

## B. The one section to ADD to the plan

```markdown
## Assumptions to validate before implementing

- [ ] **[Assumption]** — verify by: [concrete check — file to inspect, command to
      run, query to confirm] · _if false_: [what in the plan changes]
- [ ] **[Assumption]** — verify by: [...] · _if false_: [...]
```

Each item must be empirically checkable *before* any code is written. This is the
gate, not a wish list — phrase every assumption as something you can prove or
disprove by inspecting the codebase/data/contracts.

---

## C. User-facing report (chat only — do NOT write to the plan)

```markdown
**Verdict:** CRITICAL | CAUTION | REASONABLE
**Footprint:** LEAN | ACCEPTABLE | OVER-ENGINEERED

### What changed in the plan
- [revision applied] — `path/to/file:line`

### Code you can avoid writing
- [planned step] → already handled by `existing_thing` at `path:line`

### Must-handle risks addressed (cheapest correct fix)
- [risk] → [smallest mitigation applied] — `path:line`

### Risks dropped as speculative
- [risk considered] — not coded because [reason]

### Assumptions to validate
- See the `## Assumptions to validate before implementing` section now in the plan.
```

Keep the footprint qualitative — call out over-engineering, but don't promise line
counts or effort estimates.
