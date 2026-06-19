# Validation Questions

Work this file **in order**: the Simplification Pass first (shrink the plan), then
the reconciliation rule, then the risk/edge-case questions, then the guardrails.
Answer everything with `file:line` evidence.

---

## Simplification Pass (run FIRST, before risk-hunting)

The default failure mode of a plan is too much code, not too little. For each
proposed change, find the smallest correct version. Answer with evidence.

- **Reuse over write.** Does a utility / helper / hook / framework feature in THIS
  repo already do this? Grep for the verb before adding code. Cite what you found,
  or confirm you looked and it's absent.
- **Delete or configure instead of add.** Can the goal be met by removing code,
  flipping a flag, or changing config rather than adding a code path?
- **Challenge the requirement.** Is every part of the goal actually needed now?
  Name any sub-goal that's speculative, gold-plating, or "while we're here" scope.
- **YAGNI / rule of three.** Reject new abstractions, files, params, or layers
  added for a single caller or a hypothetical future one. Inline until a third
  real use exists.
- **No new dependency unless it earns it.** A new package must replace materially
  more code than it adds, and be justified vs. the stdlib / existing deps.
- **Follow this codebase's existing pattern.** If similar features exist, mirror
  that shape — don't invent a parallel one. Cite the pattern to copy.
- **Smallest diff that's still correct.** Prefer the change touching the fewest
  files/lines without hiding complexity or duplicating logic.

For each item, output either a concrete shrink ("replace step 3 with existing `X`
at path:line") or "no simpler way found — checked X, Y."

---

## Reconciling risk findings with simplicity

Risk-hunting adds code; simplification removes it. Resolve the tension per finding:

1. **Classify every risk:** MUST-HANDLE (correctness, security, data loss, a real
   reachable failure mode) vs. SPECULATIVE (hypothetical input, scale you won't
   hit, defense against states the type system / caller already prevents).
2. **Drop or defer speculative ones** — record them as "considered, not handled
   because <reason>" instead of adding code.
3. **For each MUST-HANDLE, require the cheapest correct mitigation,** preferring in
   order: make the bad state unrepresentable (types/invariants) > one guard at the
   boundary > reuse an existing error/validation path > new defensive code. One
   check at the right layer beats scattered checks everywhere.
4. **Never let a guard duplicate validation that already happens upstream** — cite
   where it's already handled.

Net rule: surface the real risk, then prescribe the smallest code that makes it
correct — not the most code that makes it feel safe.

---

## Risk & edge-case questions

For each part of the plan, answer:

| Question                               | Focus Area                                          |
| -------------------------------------- | --------------------------------------------------- |
| **Why will this NOT work?**            | Fundamental flaws, incorrect assumptions            |
| **What will BREAK?**                   | Existing functionality, APIs, contracts             |
| **What was MISSED?** *(YAGNI-gated)*   | Edge cases / error handling / rollback that are **reachable in production** — do not invent defensive code for inputs that can't occur |
| **What DEPENDENCIES are affected?**    | Imports, services, external systems                 |
| **What TESTS will fail?**              | Unit, integration, e2e implications                 |
| **What EDGE CASES weren't addressed?** *(YAGNI-gated)* | Null, empty, concurrent, large scale — only ones the code can actually hit |
| **What ASSUMPTIONS are unverified?**   | Anything the plan takes on faith — flag for the "validate before implementing" list |
| **What DECISIONS need input?**         | Ambiguous requirements, multiple valid approaches   |

### Deep checklist (apply what's relevant — each added item must earn its complexity)

- [ ] API contracts preserved (or migration planned)
- [ ] Database schema changes have migrations
- [ ] Authentication/authorization implications
- [ ] Error handling for **reachable** failure modes
- [ ] Logging and observability (no sensitive data exposed)
- [ ] Performance implications at realistic scale
- [ ] Rollback strategy if deployment fails
- [ ] Version compatibility with dependencies
- [ ] No hardcoded values that should be configurable
- [ ] Test coverage for new code paths

---

## Guardrails — never trade these for fewer lines

Simpler means less code for the SAME correctness, not less correctness. A
simplification is INVALID if it does any of:

- Drops error handling for a failure mode that can actually occur.
- Removes input validation, authz, or escaping/sanitization at a trust boundary.
- Swallows or hides errors to shrink a catch block.
- Trades a real edge case (null/empty/concurrent/overflow the code can hit) for brevity.
- Weakens a type/invariant so bad states become representable.
- Cuts line count by increasing coupling, hidden side effects, or duplication.

If a shrink would cross any line above, keep the code and label it
"MUST-HANDLE — not removable." Brevity never overrides correctness or security.

---

## Validation Mindset

Be the devil's advocate, in both directions:

- Assume the plan has flaws **and** assume it's bigger than it needs to be.
- Look for hidden dependencies the author forgot.
- Find existing code/patterns that make planned code redundant.
- Consider race conditions and concurrency that are actually reachable.
- Verify backward compatibility and public-API breakage.
- Question optimistic assumptions — and list them for empirical validation.

The goal is to surface concerns early and ship the smallest correct plan — not to block progress or pad it with defensive code.
