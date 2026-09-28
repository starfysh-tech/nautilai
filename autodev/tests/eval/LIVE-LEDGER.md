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

No live run recorded yet.
