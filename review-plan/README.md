# Review Plan

Adversarially validate an implementation plan against the actual codebase **before** you build it — surface risks, breaking changes, missed edge cases, dependency impacts, and simpler alternatives, then revise the plan in place to the leanest correct version, reporting a clear verdict (CRITICAL | CAUTION | REASONABLE) in chat.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install review-plan@nautilai
```

## Use

1. Write a plan (plan mode) or point at a plan file.
2. Run `/review-plan` (optionally `/review-plan path/to/plan.md`).
3. Review the plan, now revised in place to the leanest correct version, and the verdict reported in chat — then proceed / revise / abandon.

## What it does

It does two jobs, in this order: **make the plan smaller**, then **make it safe** — aiming for the smallest diff that's still correct at staff-engineer quality (never fewer lines at the cost of correctness).

1. **Extracts** the plan's goal, proposed changes, touched files, dependencies, and the **assumptions** it rests on.
2. **Investigates in parallel** — starting with a **reuse & reduction scan** (existing code/patterns that make planned steps redundant), then dependency tracing, breaking-change risk, error-handling gaps, architecture, and (when relevant) type-design and test-coverage impact — each grounded in `file:line`.
3. **Validates** — runs a **simplification pass first** (reuse / delete / configure / YAGNI / smallest-diff), then risk/edge-case questions, reconciling the two so risks get the *cheapest correct* fix rather than piling on defensive code (`references/validation-questions.md`).
4. **Revises the plan in place** to the leanest correct version and adds one **"Assumptions to validate before implementing"** gate. It reports the verdict, a **LEAN / ACCEPTABLE / OVER-ENGINEERED** footprint, what changed, and the code you can avoid writing — **to you in chat**, not as a confusing changes-log in the plan file.

## Optional enhancements (graceful degradation)

The skill works out of the box using **built-in agents** (`Plan`, `code-reviewer`, `Explore`) and inline analysis. If you also have these installed, it automatically uses their specialists for deeper passes; if not, it falls back — it never hard-fails on a missing plugin:

- **feature-dev** plugin — `code-explorer` for deeper dependency tracing.
- **pr-review-toolkit** plugin — `silent-failure-hunter`, `type-design-analyzer`, `pr-test-analyzer`.
- **Codex** (`openai-codex/codex` plugin) — an independent GPT cross-model review. Read-only; located version-independently and skipped cleanly if absent.

None are required. Without any of them, `/review-plan` runs a complete Claude-only validation.

## Shoals (project corrections)

When you correct how this skill behaves, it records the lesson in
`.claude/shoals/review-plan.review-plan.md` in your project and reads it back on
the next run, so it won't repeat a mistake you already flagged. The file is
append-only and committed by default (teammates inherit it) — `.gitignore` it if
you'd rather keep it per-developer.

## Runtimes: Claude Code and Hermes Agent

### Shared behavior

The validation method is identical: reuse/reduction scan first, then simplification, then
risk — every finding cited to `file:line`, and the plan revised in place.

### Claude Code

```text
/plugin install review-plan@nautilai
/review-plan [plan-file]
```

### Hermes Agent

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/review-plan
```

Then ask the agent to review a plan. No tap and no configuration —
`hermes skills tap add` does not index this repo (it registers the tap and indexes nothing on
v0.18.2); install by the identifier above.

### Runtime-specific limitations

| Capability | Claude Code | Hermes |
| --- | --- | --- |
| Parallel specialist subagents | yes | **no** — Hermes has no subagent primitive |
| Analysis | fans out to `code-explorer`, `code-reviewer`, etc. | runs the **documented inline fallback** (Read/Grep) sequentially |

The skill already specifies that fallback for Claude (specialists are opportunistic, never
required), so Hermes gets the same analysis — serially, and slower. No finding is skipped.

### Update behavior

- **Claude Code** — `/plugin update review-plan@nautilai`
- **Hermes** — `hermes skills check` then `hermes skills update`. Drift is detected by **content**,
  so upstream fixes arrive with no version bump needed.

## License

MIT
