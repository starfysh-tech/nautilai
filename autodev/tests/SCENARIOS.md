# AutoDev validation scenario ledger

The improvement loop for this plugin: every live validation run produces
findings; every finding lands as (a) a fix, (b) a deterministic regression case
in `scripts.test.sh` when it's script-level, and (c) a row here so the *skill-
level* behavior — orchestration decisions scripts can't capture — has a named
scenario that a future run must re-confirm. A fix without a row/case here is
unconfirmed.

Scorecard metrics carried across runs: completion rate, counted failures per
completed lane, misclassification incidents (implementation logged as
environment/transient = uncounted grinding — worst regression), escalation
actionability (1–5), isolation violations (target 0), verify wall time,
tokens per lane.

## Run #1 — 2026-07-03 — nautilai (greenfield, single lane)

Task: author `autodev/tests/scripts.test.sh` through the loop itself.
Orchestrator: Sonnet subagent; worker: haiku ×1.
Score: 1/1 complete, 0 counted failures, 0 isolation violations, ~53k
worker tokens, verify <10s.

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| Greenfield deadlock: baseline and completion shared one VERIFY.sh with no phase signal | `AUTODEV_PHASE=baseline\|attempt` exported to lane verifiers | `scripts.test.sh` phase-contract cases |
| Relative lane dirs (what SKILL.md passes) broke after `verify.sh` cd'd | resolve lane dir before `cd` | `scripts.test.sh` "relative lane dir resolves after cd" |
| `record-success` never counted the attempt | increments `attempt_count` | `scripts.test.sh` state-accuracy case |
| `worktree_path` never populated in state.json | `create_worktree.sh` records it | `scripts.test.sh` state-accuracy case |
| Orchestrator-as-teammate never receives worker completion signals | documented: poll lane state in that context | **closed by run #2** — 5s polling on git status + RUNSTATE.md caught all 3 completions |

## Run #2 — 2026-07-03 — agent-feed (parallel lanes, auto-detected verifier)

Venue: `~/Code/agent-feed` (clean at `4866b7e`; `npm test` = `node --test`,
26 files, ~7.6s). Three lanes from its `TODO.md`, difficulty-tiered:

1. `pkg-main` (easy): fix `"main"` pointing at a nonexistent file — `package.json` only.
2. `db-wal-size` (medium): `getDbSizeBytes()` must count WAL sidecars — `src/database.js` + test.
3. `pipeline-cap` (hard, failure-prone on purpose): cap unbounded `sessionTurnCounts` Map + eviction regression test — `src/pipeline.js` + test.
4. `drop-sqlite-deps` fed as a 4th candidate only to confirm `parallel_safe`
   rejects it (touches lockfile) — run sequentially or not at all.

Score: 3/3 lanes complete, 1 attempt each, 0 counted failures, 0 isolation
violations (per-lane diffs matched declared scope exactly), verify 8.1–11.8s.
Orchestrator: Sonnet teammate; workers: haiku ×3 spawned in one message.

- [x] `verify.sh` stack auto-detection carried the loop — no lane VERIFY.sh ever written
- [x] 3 concurrent lanes: disjoint worktrees, no cross-lane file bleed
- [x] ~~concurrent `controller.sh` writes don't clobber `state.json`~~ **failed live** (torn read + lost update demonstrated) → fixed, see findings
- [ ] live failure path — NOT exercised (hard lane's TODO target was stale; substitute task one-shotted). Carries to run #3.
- [ ] escalation actionability — NOT exercised (no escalation). Carries to run #3.
- [x] existing suite (204 tests) stayed green in every lane

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| `state.json` corruption under concurrent lanes: bystander reader hit JSONDecodeError mid-write (would kill the loop under `set -e`); 3-lane stress lost an update (expected 4, got 3) | `controller.sh`: exclusive `fcntl` lock around read-modify-write + atomic temp-file `os.replace` | `scripts.test.sh` concurrency cases (same 3-lane × 4-write stress shape) |
| `parallel_safe.sh` marked a `package.json` dependency-removal task safe — same-file collision with another lane + lockfile drift | added `package\.json` and `dependenc` to unsafe patterns | `scripts.test.sh` parallel_safe cases |
| Teammate orchestrators can't spawn *named* workers ("roster is flat") — SKILL.md's spawn step didn't say so | SKILL.md 4b: omit `name`, poll for completion | doc-level; observed working in run #2 |
| Per-lane token cost unobservable from a teammate orchestrator (transcripts off-limits) | accepted gap — scorecard tokens come from the main session or usage data | n/a |
| Worktrees inherit `node_modules` from the main checkout via Node's resolution walk-up — fine until a lane *changes* dependencies, which would silently test against the parent's packages | documented assumption (this row); interacts with the parallel_safe fix above, which keeps dependency tasks out of parallel lanes | n/a |

## Run #3 — 2026-07-03 — cc-hooks-metrics (red-first failure path)

The one unvalidated core behavior after two runs: bounded failure. Both runs
one-shotted every lane, so classify → fingerprint → record-failure → gate →
escalation has never fired on a live log. Lesson from runs #2 and the
wemo-rescue scout: TODO files lag the code (four stale items across two
repos), so **TODO mining cannot supply a genuinely failing target**. Run #3
inverts the setup: the failing test is written *before* the run by the main
session (red-first), so failure is real by construction and acceptance
criteria can't be softened by the worker.

Venue: `~/Code/cc-hooks-metrics` (clean at `cc2b2a9`; pytest, 251 tests,
~9.6s; fixtures isolate all I/O; no env/network/interactive blockers).
Targets verified unimplemented against current code (quoted evidence in
scout report, 2026-07-03):

1. Lane `broken-hooks-semantic` (hard, primary): `broken_hooks()` in
   `hooks_report/db.py:672-697` hardcodes `exit_code = 0` as success; for
   `SEMANTIC_EXIT_STEPS` (`config.py:56`) exit 1 means "findings found" and
   such steps show as perpetually broken. Pre-written red tests seed
   semantic and non-semantic steps and assert the CTE distinguishes them.
   Subtle SQL + set-conditional logic — the lane most likely to burn
   attempts honestly.
2. Lane `span-validation` (easy, control): `Span` dataclass in
   `hooks_report/spans.py:12-23` has no `__post_init__`; red tests assert
   ValueError on bad trace/span id lengths, kind, status, time ordering.

Mechanics: red test files are dropped into each lane's worktree at setup
(not committed to the repo); lane VERIFY.sh branches on `AUTODEV_PHASE` —
baseline runs the repo suite only (must be green), attempt runs repo suite
plus the red tests (all must pass). Task text forbids editing the red tests.

Results:

- [ ] live failure path — NOT exercised (3rd consecutive run): both lanes,
  including the hard SQL lane, one-shotted. Carries to run #4.
- [ ] escalation actionability — N/A, nothing escalated.
- [~] misclassification watch — synthetic only: a realistic pytest-failure log
  classified `implementation` correctly, and one live `command not found`
  baseline log classified `environment` correctly. No live implementation
  failure existed to grade.
- [x] red tests untampered (sha256 identical at placement and after attempt);
  per-worktree diffs scoped to exactly one target module each.
- [x] cap-generosity evidence recorded: 7/7 lanes across 3 runs one-shotted.
  For haiku + a fully-specified failing test as the spec, the 3-cap has
  never been approached.

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| A failed baseline set `needs_guidance` permanently — a later green baseline never cleared it, so the check gate blocked the lane forever (hit live via a `python` vs `python3` verifier typo) | `baseline_verify.sh` success branch resets `status` to `pending` | `scripts.test.sh` "green baseline clears needs_guidance" |
| `haiku-worker` agent type doesn't resolve from a teammate orchestrator (roster lists only built-in types) | SKILL.md 4b documents the fallback: `general-purpose` + `model: haiku` + inline contract | doc-level; fallback used successfully in runs #2–3 |

## Run #4 — planned — force the failure path

Three runs of honest hard-task selection have not produced a live failure;
red-first with a full failing spec makes tasks *too* tractable for haiku.
Run #4 must manufacture difficulty structurally, not aspirationally:

- Seed the lane's worktree with a plausible-but-wrong patch the worker must
  first diagnose and unwind (debugging someone else's fix is reliably harder
  than writing fresh), and/or withhold the target file/function from TASK.md
  so the worker must locate it by search.
- Keep a fully-specified red test as the verifier so failure remains
  objective. Grade the escalation handoff if the gate finally fires; if even
  this one-shots, consider dropping the cap to 2 or accepting the cap as
  cheap insurance and closing the scenario as "validated by fixtures only".
