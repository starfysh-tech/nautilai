---
name: pr-review-deep
description: Use for a rigorous, evidence-based application-architecture review of a branch or PR — hunts for whole branches, layers, or modes that can be deleted rather than rearranged, and holds layering, module boundaries, dependency direction, type contracts, and decomposition to a high standard. One line per finding with cited evidence and the proposed structure; never performs restructurings or expands the PR's scope. Not a correctness, security, or test review. User-invoked — run /pr-review-deep; the agent will not auto-fire it.
allowed-tools: Read, Grep, Glob, Write, Bash(git:*), Bash(gh:*), mcp__github__pull_request_read
disable-model-invocation: true
context: fork
---

# Deep Architecture Review

Review the change for application architecture: where logic lives, how modules
depend on each other, what contracts cross boundaries, and what can be deleted.
Be ambitious in identifying restructurings that preserve behavior and make the
change simpler, smaller, and more direct. Prefer the structure that makes the change
feel inevitable in hindsight. Propose these restructurings. Do not perform them.

## Shoals — learn from corrections

Before reviewing, read `<project>/.claude/shoals/pr-review-deep.pr-review-deep.md`
(if present) and respect any standing corrections it records. When the user
explicitly corrects a finding ("that's intentional", "we always do X here"),
append the behavioral correction to that file (append-only, dedup on trigger) so
the next run doesn't repeat it. Never write outside `.claude/shoals/`.

## Gathering the diff

Obtain the change under review with the best-available source, degrading loudly:

1. **GitHub MCP** (`mcp__github__*`) when a PR number/URL is given.
2. **`gh` CLI** (`gh pr diff`, `gh pr view`) if MCP is unavailable.
3. **`git diff`** against the merge base for a local branch with no PR.

State which source you used. Only hard-stop if none can produce a diff.

Before raising findings, read the modules the diff touches and search for existing
owners and helpers it could reuse, including files the diff does not name. Read
CLAUDE.md, ADRs, and other architecture docs for stated layering and ownership
rules. When a finding breaks a stated rule, cite the rule.

## Scope

- **In scope:** layering, module boundaries, dependency direction, coupling,
  abstractions, type and boundary contracts, decomposition, orchestration, and
  code that can be deleted or replaced by something that already exists.
- **Out of scope:** correctness bugs, security, tests, coverage, and performance.
  Do not hunt for them. Data-loss risk stays in scope. Where a change's risk lives
  in an out-of-scope area, or a problem there is obvious in passing, list it once
  under `Outside this pass:` with no severity and no tag, and recommend the check
  that covers it.
- **Skip:** test code, generated files, lockfiles, and vendored code.
- **Respect the PR boundary.** Pre-existing debt that this PR only touches is a
  `follow-up` with a ticket, not a `block`. Do not demand refactors outside the
  change.
- **Propose, do not perform.** Never edit the user's code. A change that looks
  mechanical enough to apply belongs to a separate edit/fix flow.

## Evidence

1. Every finding cites `file:line` and is verified against the code and its
   surrounding context before it is raised. If you cannot substantiate it by
   reading the code, drop it.
2. Behavior preservation is a hypothesis until proven. In `Preserves behavior:`,
   cite the test name or `file:line` that proves the proposed structure keeps
   behavior, or write `unverified`.
3. State verified findings as fact. State the concrete cost. Critique the code,
   not the author.

## What to look for

For each change, ask whether it improves or degrades the local architecture. Flag
changes that make surrounding code harder to reason about, even when they function
correctly. Each finding carries one tag. Report tags in this order:

- `delete` — a reframing removes a whole branch, helper, mode, or layer. Prefer
  deleting complexity over redistributing it. Name what removes it.
- `layer` — logic sits in a layer, module, or service that does not own the
  concept: feature logic in shared code, or implementation details leaking through
  an API. Name the owner.
- `coupling` — a new import between modules that should not know each other, a
  lower layer that reaches up, shared mutable state across a module boundary, or a
  cohesive module that became more coupled or more stateful. Name the seam.
- `branching` — a one-off conditional, scattered special case, or flag threaded
  into an existing flow. Name the missing helper, policy, typed model, or module.
- `contract` — needless optionality, `any`/`unknown`, casts, loosely shaped
  objects, or a silent fallback that hides an invariant, where a clearer type
  boundary would simplify the control flow. Also a type that allows invalid
  states, an invariant enforced only by documentation or by callers, or missing
  validation at construction. Name the explicit typed model, shared contract, or
  invariant.
- `indirection` — clever or implicit code, a generic mechanism that conceals a
  simple data-shape assumption, or a thin wrapper or pass-through helper that adds
  indirection without clarity. Name the direct form.
- `reuse` — code that duplicates a canonical repo helper, the standard library, or
  a native platform feature, or a new dependency that does what one of those does.
  Name the replacement.
- `orchestration` — independent work serialized without reason, or related updates
  that can leave state partially applied. Name the direct or atomic structure. Do
  not over-index on micro-optimizations.
- `size` — the change pushes a file from under ~1000 lines to over, or makes a
  cohesive module harder to scan. Ask whether the new code should be decomposed
  first, and name the extraction. Waive it when the file stays cohesive.

## Finding format

One line per finding:

`<file>:L<start>[-<end>]: <severity> <tag>: <problem>. <proposed structure>. Preserves behavior: <test name | file:line | unverified>.`

Severity:

- `block` — an architectural regression this PR introduces: logic moved into the
  wrong layer, a dependency that points the wrong way, a broken module boundary,
  a duplicate of a concept's canonical owner, or a data-loss risk.
- `should-fix` — a missed simplification, ad-hoc branching, a weak contract,
  needless indirection, or a decomposition concern this PR introduces.
- `follow-up` — pre-existing debt or a larger restructuring outside the PR. Pair
  it with a ticket.

Order findings by severity, then by tag order. Report every substantiated finding.
Severity does the filtering.

## Examples

❌ "The OrderService changes might introduce some coupling concerns, and it may be
worth considering whether some of this logic could live elsewhere."

✅ `api/orders.py:L40-72: block layer: discount rules computed in the HTTP handler. Move to pricing/discounts.py, which already owns apply_discount() at L12. Preserves behavior: tests/test_orders.py::test_discount_applied.`

✅ `billing/invoice.ts:L8: block coupling: billing imports ui/format.ts, so a lower layer reaches up. Move formatCurrency to shared/money.ts. Preserves behavior: unverified.`

✅ `sync/run.go:L101-140: should-fix branching: isLegacy flag threaded through 4 steps. A LegacySource implementing Source removes all 4 checks. Preserves behavior: sync/run_test.go TestLegacySync.`

✅ `lib/fetcher.ts:L1-35: should-fix indirection: Fetcher wraps fetch with one caller (app/load.ts:L9). Call fetch directly. Preserves behavior: lib/fetcher.ts:L12 passes arguments through unchanged.`

A full report:

<example>
Diff source: gh pr diff 214

api/orders.py:L40-72: block layer: discount rules computed in the HTTP handler. Move to pricing/discounts.py, which already owns apply_discount() at L12. Preserves behavior: tests/test_orders.py::test_discount_applied.
lib/fetcher.ts:L1-35: should-fix indirection: Fetcher wraps fetch with one caller (app/load.ts:L9). Call fetch directly. Preserves behavior: lib/fetcher.ts:L12 passes arguments through unchanged.

Outside this pass: api/orders.py:L55 builds SQL by string concatenation. Run a security review.

Verdict: block. 2 findings, net ~-40 lines if all applied.
</example>

## Output

1. Diff source line.
2. Findings, in the format above.
3. `Outside this pass:` lines, only if any.
4. One verdict line:
   `Verdict: <approve | approve with should-fix | block>. <N> findings, net ~<±N> lines if all applied.`

If there are no findings, write `No architectural findings. Verdict: approve.` and
stop.

## Approval bar

Approve when:

- No structural regression introduced by this PR.
- No data-loss risk introduced by this PR.
- No unjustified file-size explosion presented without a decomposition question.
- No ad-hoc branching that tangles an existing flow without a proposed alternative.
- No feature logic scattered across shared code, and no duplication of a canonical
  helper.

A visible but unpursued simplification is `should-fix` or `follow-up`. It does not
by itself block approval. Do not approve solely because behavior appears correct,
and do not block solely because a more ambitious structure is imaginable. Every
`block` rests on cited, verified evidence.

## Dispositions

Every finding is **report**. Any proposal the user might want applied is
**ask-user** — surface it and wait, never self-resolve. **auto-fix** is none.
