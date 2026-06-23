---
name: review-plan
description: Validate an implementation plan against the actual codebase AND drive it to the smallest correct version. Surface risks and breaking changes, but first find what can be reused, deleted, or left unbuilt — then revise the plan in place to the leanest staff-quality approach and list the assumptions to validate before coding. Use whenever the user writes or shares a plan, or asks to review / validate / pressure-test / sanity-check it before building — even if the plan looks complete or confident.
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

Before starting, load interactive tools:
1. Call `ToolSearch` with query `select:AskUserQuestion`
2. Proceed with Phase 1.

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

## Phase 2: Investigate (parallel, with graceful degradation)

Run the analyses below in parallel. **Each has a preferred specialist subagent and a built-in fallback.** Spawn the specialist via `Task` only if it's installed; if a `Task` call returns "Agent type … not found" (the providing plugin isn't installed), **fall back to the built-in agent or inline Read/Grep — never abort.** `code-reviewer`, `Plan`, and `Explore` are built in and always available.

Every subagent prompt must demand **condensed output**: findings only, each with a `file:line` citation, no verbose narration ("Return only findings with file:line refs; if you can't verify from code, say 'unverifiable' — don't guess. Keep it under ~500 tokens."). This keeps synthesis grounded and small.

| Analysis | Preferred specialist (if installed) | Built-in fallback (always works) |
| --- | --- | --- |
| **Reuse & reduction scan** (run this first) | `feature-dev:code-explorer` — *tasked specifically*: find existing utilities, helpers, endpoints, or patterns in THIS repo that already do what the plan proposes, and what the plan could delete/replace instead of add | `Explore` agent, or inline Grep/Glob for the relevant verbs/types |
| Dependency & architecture tracing | `feature-dev:code-explorer` | `Explore` agent, or inline Grep/Read |
| Breaking-change risk | `code-reviewer` (built-in) | — |
| Error-handling / silent-failure gaps | `pr-review-toolkit:silent-failure-hunter` | inline analysis (see `references/validation-questions.md`) |
| Architectural soundness & trade-offs | `Plan` (built-in) | — |
| Type design (only if the plan adds types) | `pr-review-toolkit:type-design-analyzer` | inline analysis |
| Test-coverage impact | `pr-review-toolkit:pr-test-analyzer` | inline analysis |

Rules: give each agent ONE focused aspect; require specific `file:line` references; wait for results before synthesis.

### Optional: Codex cross-model review

If the Codex companion is installed, get an independent GPT review for a second perspective. Run its script **directly via Bash** — do **not** use the `codex:codex-rescue` subagent (it's a thin wrapper that may lack tool permissions when spawned as a subagent).

Locate the script version-independently and run it (skip cleanly if not found):

```bash
CODEX_SCRIPT="$(find "$HOME/.claude/plugins" -name codex-companion.mjs -path '*/codex/*' 2>/dev/null | head -1)"
[ -n "$CODEX_SCRIPT" ] && node "$CODEX_SCRIPT" task "<prompt>" --effort high || echo "Codex unavailable — continuing with Claude-only analysis"
```

- Use the `task` command (not `review`/`adversarial-review` — those diff branches, not designs). Do **not** pass `--write`; this is read-only.
- Fill the prompt from `references/codex-prompt.md` with the Phase 1 details.
- Avoid the literal string for environment files in the prompt (security hooks may block it) — say "environment file" / "dotenv config".
- **Codex is additive** — if it's missing, times out, or returns nothing, note it to the user and continue.

---

## Phase 3: Validate — simplify first, then harden

Work `references/validation-questions.md` **in order**: run the **Simplification Pass first** (reuse / delete / configure / YAGNI / smallest-diff), then the risk and edge-case questions and deep checklist. Capture `file:line` evidence throughout.

Two non-negotiable rules from that file:
- **Reconcile risk against simplicity** — classify each risk **must-handle** (real, reachable correctness/security/data failure) vs. **speculative** (hypothetical input, scale you won't hit, states already prevented upstream). Drop/defer speculative ones; for must-handle, prescribe the *cheapest correct* mitigation, not the most defensive one.
- **Guardrails** — simpler means less code for the **same** correctness. Never remove real error handling, validation, authz, or security to cut lines.

---

## Phase 4: Synthesize & revise the plan in place

1. Combine the findings into a severity-ranked picture; keep any Codex findings labeled as a separate cross-model perspective (don't merge into the Claude buckets).
2. Resolve conflicts or ambiguous decisions with the user via `AskUserQuestion` **before** finalizing.
3. **Revise the original plan in place with `Edit`** so the plan *becomes* the leanest correct version — apply the reuse/delete/simplify wins and the cheapest-correct mitigations directly. **Do not append a "validation results" or "changes" section to the plan file** — a retrospective log confuses whoever implements it later. The plan file should read as a clean, improved plan.
4. Into the plan, add exactly one forward-looking section — **`## Assumptions to validate before implementing`** — listing each assumption as an empirically checkable item (what to inspect/run to confirm it before writing code). This is the one addition that belongs in the plan; everything else is reported to the user (below).

## Finding dispositions

This skill follows the nautilai convention. Disposition of every finding:

- **auto-fix** — revise the plan file in place to the leaner correct version (reuse/delete/simplify + cheapest-correct mitigations);
- **report** — verdict, footprint, and risks dropped as speculative;
- **ask-user** — conflicting or ambiguous plan decisions, resolved via AskUserQuestion (step 2) *before* finalizing. Never silently resolve an ask-user decision.

---

## Report to the user (in chat, not the plan file)

After revising the plan, tell the user:

- **Verdict:** CRITICAL | CAUTION | REASONABLE, plus **Footprint: LEAN | ACCEPTABLE | OVER-ENGINEERED** (so a safe-but-bloated plan can't pass silently).
- **What changed in the plan** — the revisions you applied (reuse/delete/simplify + must-handle fixes), each with `file:line`.
- **Code you can avoid writing** — the existing utility/pattern/flag that replaces a planned step, with `file:line`.
- **Assumptions to validate** — point at the section you added to the plan.
- **Risks dropped as speculative** — what you considered and deliberately did *not* add code for, and why.

Use the structure in `references/output-template.md`. Then ask: "Plan revised in place. How would you like to proceed?" — Review decisions | Validate assumptions | Create tickets | Abandon.

## Success criteria

- [ ] Plan located; assumptions extracted
- [ ] Reuse/reduction scan run **first**, with `file:line` evidence
- [ ] Simplification pass applied before hardening
- [ ] Each risk classified must-handle vs. speculative; mitigations are cheapest-correct
- [ ] Guardrails respected (no correctness/security traded for brevity)
- [ ] Plan **revised in place** to the leanest correct version (no changes-log appended)
- [ ] `## Assumptions to validate before implementing` added to the plan
- [ ] User shown verdict + footprint + what changed + code avoided

## What to read when

- `references/validation-questions.md` — the simplification pass, reconciliation rule, guardrails, and risk/edge-case questions. Read every run.
- `references/codex-prompt.md` — prompt template for the optional Codex step.
- `references/output-template.md` — the user-facing report + the in-plan assumptions block.
