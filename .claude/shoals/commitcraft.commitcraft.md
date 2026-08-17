# Shoals — commitcraft

## Invoke the skill, don't imitate it
- **Trigger:** any commit or PR in this repo, including ones made mid-task by the main session or by subagents
- **Wrong:** ran raw `git commit` heredocs that followed CommitCraft's conventions by hand instead of invoking `/commitcraft commit`
- **Correct:** always invoke the CommitCraft skill for commits and PRs; hand-conformance is not a substitute
- **Why:** the skill carries staging rules, message generation, issue linking, and these shoals — bypassing it silently drops those behaviors (Randall, 2026-07-03)

## Changed skill output is a `feat`, not `docs`/`chore`
- **Trigger:** picking a commit type for a change that touches what a skill emits — a new section in a report, a rendered preview, a validation gate, different findings text
- **Wrong:** reasoned "no code path changed and nothing installs differently, so this is `docs`"
- **Correct:** if the user sees different output from running the skill, it is a behavior change — type it `feat` (or `fix`). Reserve `docs` for changes a user only encounters by reading the repo (READMEs, conventions, changelog) with skill output untouched.
- **Why:** release-please only sections `feat`/`fix` into the generated changelog, so a mistyped behavior change ships invisibly — the user gets new output with no release note explaining it (Randall, 2026-08-17)
