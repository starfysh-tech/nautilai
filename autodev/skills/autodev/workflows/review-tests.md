# Review tests — FIRST-U scores, anti-patterns, gaps

Read-only. Never edit a test here.

Input: a path (file or directory) from `$ARGUMENTS`, or, inside a run, the
existing tests at the seams the lanes touch.

Follow `${CLAUDE_PLUGIN_ROOT}/skills/autodev/references/tdd.md` → Test review. For each test file, report:

1. **FIRST-U scores** — each letter 0–10 with `file:line` evidence, and an
   overall score out of 100.
2. **Anti-patterns** — from the blocking and advisory tables, with `file:line`.
3. **Missing scenarios** — error cases, authorization, validation, boundaries,
   reachable concurrency.
4. **Proposed fix** — the refactored test for each finding, as a proposal.
5. **Coverage gaps** — from the Coverage checklist, when the TDD profile has a
   `coverage` command (run it; do not gate on it).

## Finding dispositions

- `auto-fix`: none.
- `report`: scores, advisory findings, missing scenarios, coverage gaps.
- `ask-user`: blocking-class findings. Standalone, list them with the proposed
  fix and stop. Inside a run, each becomes a proposed test-fix lane at the
  launch checkpoint (the advisor may accept one in an unattended run).
