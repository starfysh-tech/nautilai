---
name: review-plan
description: Validate an implementation plan against the actual codebase AND drive it to the smallest correct version. Surface risks and breaking changes, but first find what can be reused, deleted, or left unbuilt — then revise the plan in place to the leanest staff-quality approach and list the assumptions to validate before coding. Use when the user asks to review / validate / pressure-test / sanity-check a plan before building.
argument-hint: "[plan-file-path]"
allowed-tools:
  [
    Read,
    Edit,
    Grep,
    Glob,
    Task,
    AskUserQuestion,
    ToolSearch,
    Bash(git:*),
    Bash(find:*),
    Bash(grep:*),
    Bash(ls:*),
    Bash(node:*),
    Bash(head:*),
  ]
---

# Review Plan — validate a plan and shrink it to the smallest correct version

Validate the plan against the actual codebase, then make it **smaller**. Two jobs,
in this order: (1) find what can be **reused, deleted, or not built** so the plan
produces much less code for the same goal; (2) find what will **break or is
missing** and fix it with the *cheapest correct* change. Be deliberately
skeptical and ground every claim in `file:line`. The goal is the smallest diff
that is still correct at staff-engineer quality — never fewer lines at the cost of
correctness.

If `AskUserQuestion` is deferred in this environment, load it via `ToolSearch` (`select:AskUserQuestion`) before Phase 4.

**If you're not in plan mode and there's no plan file yet, suggest `/plan` first** — this skill reviews an existing plan, it doesn't write one.

## Additional context

### Recent changes
!`git diff --name-only HEAD~5 2>/dev/null | head -20`

### Current branch state
!`git status --short 2>/dev/null | head -10`

### Recent commits
!`git log --oneline -10 2>/dev/null`

---

## Phase 1: Locate & extract the plan

- If a path argument was given, use it. Otherwise use the active plan-mode plan, or — if `~/.claude/plans/` exists — list it (`ls -t ~/.claude/plans/`) and ask which to validate.
- Extract: the goal/outcome, proposed changes, files/components touched, dependencies, and — explicitly — every **assumption** the plan rests on (about the codebase, data, contracts, or environment). Assumptions drive Phase 3 and the final "validate before implementing" list, so capture them as you read.

---

## Phase 2: Investigate (parallel)

Delegate each aspect below to its own read-only subagent, in parallel. Each aspect
answers the named parts of `references/validation-questions.md`:

1. **Reuse, reduction & interface shape** — Simplification Pass (including deep
   modules). Highest priority.
2. **Dependencies & breaking changes** — "What will BREAK?", "What DEPENDENCIES are
   affected?", API/schema/version checklist items.
3. **Error handling & edge cases** — "What was MISSED?", "What EDGE CASES?", reachable
   failure modes; type invariants if the plan adds types.
4. **Tests** — "What TESTS will fail?", coverage for new code paths.
5. **Soundness & assumptions** — "Why will this NOT work?", "What ASSUMPTIONS are
   unverified?", architectural trade-offs.

Rules:
- Give each subagent its full aspect prompt plus the Phase 1 extraction as context; it starts fresh and returns a summary only.
- Every prompt demands condensed output: "Return only findings with file:line refs; if you can't verify from code, say 'unverifiable' — don't guess. Keep it under ~500 tokens."
- Use the runtime's own subagent primitive. Do not invent a specialist type. On Claude Code, prefer an installed specialist that matches the aspect (`feature-dev:code-explorer`, `code-reviewer`, `pr-review-toolkit:silent-failure-hunter`, `pr-review-toolkit:type-design-analyzer`, `pr-review-toolkit:pr-test-analyzer`); if a spawn returns "Agent type … not found", use `Explore` or `general-purpose` with `model: haiku`. Named specialists keep their own model.
- If no delegation primitive exists, run the aspects inline with Read/Grep, serially. Never abort.
- Wait for all results before Phase 3.

### Optional: Codex cross-model review

If the Codex companion is installed, get an independent GPT review. Run its script **directly via Bash** — do **not** use the `codex:codex-rescue` subagent (it may lack tool permissions when spawned as a subagent).

```bash
CODEX_SCRIPT="$(find "$HOME/.claude/plugins" -name codex-companion.mjs -path '*/codex/*' 2>/dev/null | head -1)"
[ -n "$CODEX_SCRIPT" ] && node "$CODEX_SCRIPT" task "<prompt>" --effort high || echo "Codex unavailable — continuing with Claude-only analysis"
```

Build `<prompt>` from the Phase 1 plan summary and the affected file paths (Codex reads the files itself), then ask for the five Phase 2 aspects as `##` sections in that order, with: "Cite file:line for every claim. Distinguish observed facts from inferences. If you cannot verify a claim from the code, say so. Skip speculative edge cases."

- Use the `task` command (not `review`/`adversarial-review` — those diff branches, not designs). Do **not** pass `--write`.
- Avoid the literal string for environment files in the prompt (security hooks may block it) — say "environment file" / "dotenv config".
- **Codex is additive** — if it's missing, times out, or returns nothing, note it to the user and continue.

---

## Phase 3: Validate — simplify first, then harden

Apply `references/validation-questions.md` **in order** to the Phase 2 findings: Simplification Pass, then reconcile each risk (must-handle vs. speculative, cheapest correct mitigation), then guardrails. Keep `file:line` evidence throughout.

---

## Phase 4: Synthesize & revise the plan in place

1. Combine the findings into a severity-ranked picture; keep any Codex findings labeled as a separate cross-model perspective (don't merge into the Claude buckets).
2. Resolve conflicts or ambiguous decisions with the user via `AskUserQuestion` **before** finalizing.
3. **Before editing, ensure the change is recoverable**: if the plan file is inside a git repo and already tracked, the working-tree history covers it. Otherwise (untracked file, or no git repo), write a `<plan>.bak` copy first, or show the full diff in chat — then state what was preserved.
4. Revise the plan in place with `Edit` and add the assumptions section, per `references/output-template.md` (A and B).

## Finding dispositions

This skill follows the nautilai convention. Disposition of every finding:

- **auto-fix** — revise the plan file in place to the leaner correct version (reuse/delete/simplify + cheapest-correct mitigations);
- **report** — verdict, footprint, and risks dropped as speculative;
- **ask-user** — conflicting or ambiguous plan decisions, resolved via AskUserQuestion (step 2) *before* finalizing. Never silently resolve an ask-user decision.

---

## Report to the user (in chat, not the plan file)

Report using `references/output-template.md` (C). Then ask: "Plan revised in place. How would you like to proceed?" — Review decisions | Validate assumptions | Create tickets | Abandon.

## What to read when

- `references/validation-questions.md` — the simplification pass, reconciliation rule, guardrails, and risk/edge-case questions. Read every run.
- `references/output-template.md` — the in-plan revision rules, the assumptions block, and the user-facing report.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/review-plan.review-plan.md` from the
project root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — how you scope, what you flag as a risk, or
how aggressively you shrink the plan — append a shoal to that file (creating
`.claude/shoals/` if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger**. Capture only explicit behavioral
corrections, not passing preferences. Mention the capture in one line; don't
narrate it.
