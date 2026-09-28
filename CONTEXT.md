# nautilai

A Claude Code plugin marketplace. Each plugin ships skills, agents, and scripts into end-user repos.

## AutoDev

**Lane**:
One independent task from an autodev request, plus everything it owns while it runs: its lane dir, its git worktree and branch, and its state entry. Retries of the same task reuse the same lane.
_Avoid_: task (collides with `TASK.md` and the task text), track, job

**Test-fix lane**:
A lane whose task is to repair an existing test the pre-launch test review flagged, proposed by the orchestrator and started only when the user (or, in an unattended run, the advisor) accepts it.
_Avoid_: cleanup lane, refactor lane

**Slice**:
One acceptance scenario worked end to end inside a lane: its red test, then the code that makes it pass. A lane runs its slices one at a time.
_Avoid_: step, iteration, cycle

**Red test**:
A failing test the orchestrator writes for one slice before that slice's attempt, encoding one acceptance scenario. It is the slice's spec: the worker must make it pass and must not change it.
_Avoid_: seed test, spec test

**Launch checkpoint**:
The one stop before any attempt starts, where the user confirms or edits each lane's seams, acceptance scenarios and their order, and the first slice's red test, judged by its actual failure output. After it, the run is autonomous.
_Avoid_: approval gate, review gate (that is the post-verify reviewer)

**Advisor**:
The staff-engineer role that makes an allowed decision when no user can answer, in a fresh context separate from the orchestrator. Each decision is logged and validated by the user at the end of the run.
_Avoid_: decision-advisor, reviewer, review gate (that is the post-verify reviewer)

**Guard**:
A check the spec demands the code enforce (a permission check, a trigger bypass, an abort-on-truncation). Each guard must have a test that goes red when the guard is removed.
_Avoid_: validation, safeguard

**TDD profile**:
The committed, project-specific test facts for one repo — commands, test DB isolation, fixture and mocking conventions, guards — confirmed by the user during autodev setup. Only autodev reads it.
_Avoid_: tdd skill, test config
