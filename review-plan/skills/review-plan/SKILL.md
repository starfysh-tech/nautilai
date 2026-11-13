---
name: review-plan
description: Validate an implementation plan against the actual codebase AND drive it to the smallest correct version. Surface risks and breaking changes, but first find what can be reused, deleted, or left unbuilt — then revise the plan in place to the leanest staff-quality approach, list the assumptions to validate before coding, and run a clean-context adversarial check that tries to disprove those assumptions and the plan changes. Use when the user asks to review / validate / pressure-test / sanity-check a plan before building.
argument-hint: "[plan-file-path]"
allowed-tools:
  [
    Read,
    Edit,
    Write,
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

**If the plan exists only in the conversation, write the agreed plan verbatim to a file, then review and revise that file.** Phase 1 sets the location.

## Additional context

### Recent changes
!`git diff --name-only HEAD~5 2>/dev/null | head -20`

### Current branch state
!`git status --short 2>/dev/null | head -10`

### Recent commits
!`git log --oneline -10 2>/dev/null`

---

## Phase 1: Locate & extract the plan

- If a path argument was given, use it. Otherwise use the active plan-mode plan.
- If the plan exists only in the conversation, write it verbatim to a new file before you review it. Pick the location in this order:
  1. A location named in the project's shoals or CLAUDE.md.
  2. The repo's `docs/plans/`, if it exists.
  3. Otherwise ask the user once, and append the answer to `.claude/shoals/review-plan.review-plan.md` in the Shoals format below, with **Trigger** "plan exists only in the conversation", **Correct** "write it to `<answer>`", and **Wrong** and **Why** "n/a — first-run location answer".
- Otherwise find the plans directory: read `plansDirectory` from the project `.claude/settings.local.json`, then the project `.claude/settings.json`, then `~/.claude/settings.json`, and fall back to `~/.claude/plans/`. Resolve a relative value against the project root. If that directory exists, list it newest first with `ls -t` on its literal absolute path (never `~` or `$HOME` in the command), and ask which to validate.
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
- Every prompt carries the issue bar: "Report a risk only if it is MUST-HANDLE: correctness, security, data loss, or a failure reachable in production. Skip speculative edge cases."
- Prompts for aspects 2–5 add: "'None found — checked X, Y' is a complete answer."
- Use the runtime's own subagent primitive. Do not invent a specialist type. On Claude Code, prefer an installed specialist that matches the aspect (`feature-dev:code-explorer`, `code-reviewer`, `pr-review-toolkit:silent-failure-hunter`, `pr-review-toolkit:type-design-analyzer`, `pr-review-toolkit:pr-test-analyzer`); if a spawn returns "Agent type … not found", use `Explore` or `general-purpose` with `model: haiku`. Named specialists keep their own model.
- If no delegation primitive exists, run the aspects inline with Read/Grep, serially. Never abort.
- Wait for all results before Phase 3.

### Optional: Codex cross-model review

If the Codex companion is installed, get an independent GPT review. Run its script **directly via Bash** — do **not** use the `codex:codex-rescue` subagent (it may lack tool permissions when spawned as a subagent).

1. Locate `codex-companion.mjs` with the Glob tool, pattern `**/codex-companion.mjs`, with `path` set to the absolute `.claude/plugins` directory under the user's home (take the home path from the working directory or environment context). Or run `find` on that literal absolute path. Never put `$HOME`, `~`, or a shell glob in the command.
2. If both a `plugins/cache` copy and a `plugins/marketplaces` copy match, use the `plugins/cache` copy. If several `plugins/cache` copies match, use the one with the highest version directory.
3. Run the script with its literal path:

   ```bash
   node "<literal path>" task "<prompt>" --effort high
   ```

4. If no copy is found, tell the user "Codex unavailable — continuing with Claude-only analysis" and continue.

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
2. Resolve conflicts or ambiguous decisions with the user via `AskUserQuestion` **before** finalizing. Write each question per "Asking the user" in `references/validation-questions.md`.
3. **Before editing, ensure the change is recoverable**: if the plan file is inside a git repo and already tracked, the working-tree history covers it. Otherwise (untracked file, or no git repo), write a `<plan>.bak` copy first, or show the full diff in chat — then state what was preserved.
4. Revise the plan in place with `Edit` and add the assumptions section, per `references/output-template.md` (A and B).

---

## Phase 5: Adversarial check

Run on every review. Skip only when the claim list is empty.

1. Build a numbered claim list: every item in `## Assumptions to validate before implementing`, plus every finding that changed the plan, each with its cited `file:line`.
2. Delegate the check to one fresh read-only subagent. Pass only the line "Read `<absolute path of references/adversarial-check.md>` and follow it exactly. Read-only.", the plan file path, and the claim list. Do not pass the review's reasoning, the Phase 2 outputs, or the chat.
   - On Claude Code, spawn type `review-plan:plan-skeptic`.
   - If that type is not found, or the runtime has no agent types, spawn a general-purpose subagent with the same prompt.
   - If no delegation primitive exists, run the check inline and follow `references/adversarial-check.md`.
3. Apply the results:
   - `fails` — fold the correction into the plan with `Edit`. A `fails` that changes a decision is ask-user.
   - `holds` — check off the assumption item (`[x]`) and add the evidence. A finding that holds needs no plan change.
   - `unverified` and `needs you` — leave the item open and add the command or question.
   - For a finding claim that is `unverified` or `needs you`, add it to `## Assumptions to validate before implementing` as an open item with its status.

## Finding dispositions

This skill follows the nautilai convention. Disposition of every finding:

- **auto-fix** — revise the plan file in place to the leaner correct version (reuse/delete/simplify + cheapest-correct mitigations), and fold Phase 5 `fails` results and statuses into the plan;
- **report** — verdict, footprint, risks dropped as speculative, and Phase 5 `unverified` and `needs you` items with their commands or questions;
- **ask-user** — conflicting or ambiguous plan decisions (Phase 4 step 2) and Phase 5 `fails` results that change a decision, resolved via AskUserQuestion *before* finalizing. Never silently resolve an ask-user decision.

---

## Report to the user (in chat, not the plan file)

Report using `references/output-template.md` (C). Then ask: "Plan revised in place. How would you like to proceed?" — Build | Hand off | Create tickets | Abandon.

## What to read when

- `references/validation-questions.md` — the simplification pass, reconciliation rule, guardrails, and risk/edge-case questions. Read every run.
- `references/output-template.md` — the in-plan revision rules, the assumptions block, and the user-facing report.
- `references/adversarial-check.md` — the Phase 5 rules. Pass its path to the subagent; read it only when running Phase 5 inline.

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
