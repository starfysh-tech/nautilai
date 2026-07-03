# Shoals — commitcraft

## Invoke the skill, don't imitate it
- **Trigger:** any commit or PR in this repo, including ones made mid-task by the main session or by subagents
- **Wrong:** ran raw `git commit` heredocs that followed CommitCraft's conventions by hand instead of invoking `/commitcraft commit`
- **Correct:** always invoke the CommitCraft skill for commits and PRs; hand-conformance is not a substitute
- **Why:** the skill carries staging rules, message generation, issue linking, and these shoals — bypassing it silently drops those behaviors (Randall, 2026-07-03)
