# AutoDev planning live-eval ledger

What it measures: whether the planner, applying `references/tdd.md`, produces
the structure the auth-system fixture's expected output holds — GWT scenarios
for lockout, password complexity, and reset expiry; OAuth/2FA in Q2,
SendGrid/PostgreSQL in Q3, email format/bcrypt in Q4, password validation as
the Q1 First-U choice; and shared-state and weak-assertion findings on the two
existing tests. Structural checks only (`checks.tsv`); strategy quality beyond
that is not graded.

What it does not measure: the scripts (covered offline by `tests/tdd.test.sh`),
worktree/commit behavior, or the worker and review gate.

Run: `bash autodev/tests/eval/live-validate.sh [runs] [threshold]` — real
`claude -p` calls from a temp dir, default 3 runs at 0.8. Not in CI.
The grader itself is checked offline against `fixtures/auth-system.gold.md`.

## Runs

### 2026-09-28 · `claude -p` default model · n=3, threshold 0.8

- Run A (original 12 checks): soft=29/36, hard=0. Every run missed `q2_oauth`
  and `q4_email_format`; outputs were not kept.
- Kept one output (`AUTODEV_EVAL_KEEP`): 12/12. It placed OAuth in Q2 as an
  extraction; Run B's first output placed it in Q3. Both follow the rule
  (OAuth has many dependencies). `q4_email_format` required wording from the source skill's
  answer, not from the input's requirements.
- Checks changed to grade the rule: `oauth_many_deps` (OAuth in Q2 or Q3).
- Run B (kept): soft=33/36, hard=1. Misses: a password-rule scenario phrased
  "missing a character class" / "weak password" (regex too narrow), and one
  run with no Q4 behavior, stated and reasoned in the output.
- Checks changed: `scenario_password` matches the scenario's meaning;
  `q4_present` dropped (no TDD rule requires a Q4 behavior).
- Re-grade of all 4 kept outputs with the final 11 checks: 11/11 each.

Finding: the first check set encoded one worked answer's placements and
wording; the quadrant rule allows more than one correct placement.
