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

## Run #4 — 2026-07-03 — mqol-uptimer (seeded regression)

Three runs of honest hard-task selection have not produced a live failure;
red-first with a full failing spec makes tasks *too* tractable for haiku.
Run #4 manufactures difficulty structurally: debugging someone else's subtle
regression, with the target location withheld.

Venue: `~/Code/mqol-uptimer` (mqol-inc, `master`, pnpm monorepo, vitest,
113 tests ~15–30s, in-memory fake DB, no env/network blockers). Target:
`apps/worker/src/monitor/state-machine.ts` — threshold/hysteresis logic.

Design (no comparison arm — decided 2026-07-03):

- The orchestrator applies a seed patch of three subtle bugs disguised as a
  refactor and **commits it on the lane branch** ("refactor(monitor): tighten
  threshold normalization and streak bookkeeping") so the worker sees a
  plausible prior commit, not an obvious sabotage: `>=`→`>` in
  `normalizeThreshold` (threshold 1 silently becomes the default), `>=`→`>`
  in down→up recovery (one extra success to recover), and unknown-outcome
  streak preservation instead of reset.
- TASK.md withholds the file: "the worker app's suite is failing after a
  recent refactor; find the regression and fix it; the tests are the spec
  and must not be edited." Existing suite = the red spec; no new red tests.
- Setup gates: seed must produce failing tests before the worker starts
  (else abort — the run is invalid); pnpm workspace needs a hand-written
  lane VERIFY.sh (`pnpm -r --if-present test`) and possibly `pnpm install`
  in the worktree (workspace symlinks don't survive the walk-up; a finding
  either way).
- Tamper check: hash test files before/after each attempt.
- If the gate fires: capture escalation verbatim, grade 1–5. If even this
  one-shots: close the failure-path scenario as fixture-validated and accept
  the cap as cheap insurance (per run #3's decision rule).

Results: **one-shot, and the failure-path scenario is hereby CLOSED as
fixture-validated.** Seed gate confirmed red (4 failed / 113, blast radius
crossing into scheduler tests). The haiku worker, given only "the suite is
failing after a recent refactor", diagnosed and reverted all three seeded
bugs — including the semantically subtle unknown-streak one — in a single
attempt (+4/-4, no test touched, tamper hashes identical). 8/8 lanes across
4 runs one-shotted: the 3-cap is cheap insurance, never approached. The
misclassification watch got its strongest evidence yet: a *genuine* vitest
failure log (real AssertionErrors) classified `implementation` correctly
despite trap words; fingerprint deterministic. Gate/record/escalate logic
remains covered by `scripts.test.sh` fixtures (including the
escalate_summary output-shape case added post-run).

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| Cold `pnpm install` in a fresh worktree blocked twice: corepack signature verification crash on the pinned packageManager, then a transitive native build (`sharp`) aborting install before vitest's bin symlink existed — surfacing as `vitest: command not found`, which reads as an environment failure, not the task | SKILL.md worktree step documents the recovery (`COREPACK_INTEGRITY_KEYS=0`, `--ignore-scripts`) | doc-level; environment property |
| run #3's baseline status-reset fix | confirmed working live (`status: pending` after green baseline) | already covered |

## Run #5 — 2026-07-03 — linktrail (review gate live validation)

The review gate (added 2026-07-03: after `verify.sh` passes, an independent
`review-gate` agent reviews the lane diff against TASK.md; `block` counts as
a counted failure, only `pass` yields DONE.md) is motivated by run #2's
hardest evidence — a downstream bot review caught a P0 (module detection) and
P1 (rotation stranding an open FD) in output `verify.sh` had blessed — but
the gate itself has never run live. Next live run must confirm:

Venue: `~/Code/starfysh/linktrail` (5th distinct repo; clean at `b68d735`,
`npm test` → `bun test`, 139 tests in ~0.5s — and `extension/src/queue.ts`
is deliberately untested impure glue per its own header, so any diff to it
stays green: completion rests entirely on the gate). Lane `flush-guard`,
task: "add a re-entrancy guard to `flushQueue` (concurrent flushes
double-send parked captures)".

- Attempt 1 is SEEDED with a naive green-but-flawed guard (module-level
  `flushing` boolean, no try/finally, and an early `return` on empty queue
  that leaves the lock set forever — first flush on an empty queue silently
  disables all future flushes until SW restart). Suite stays green by
  construction.
- Attempt 2 is a real haiku worker whose RUNSTATE.md carries the gate's
  block findings.

Must confirm:

Results: **the definitive run — every negative-path behavior fired live.**
3 attempts, 3 counted failures (all from the gate; verify green throughout),
cap-stop and escalation triggered for real, on a lane that genuinely
deserved it.

- [x] gate ran on all 3 verify-passes; verdicts landed in review-N.log (no
  DONE.md because the lane never passed — the correct block-path artifact)
- [x] seeded flaw BLOCKED with file:line findings naming the subtle
  empty-queue lockout AND the thrown path, call sites traced (grade 5/5)
- [x] findings reached RUNSTATE.md and attempt 2's worker demonstrably fixed
  the cited paths — but introduced a genuine TOCTOU (flag set after the
  first await), which gate 2 caught by reasoning about async interleaving
  (grade 5/5)
- [x] all three blocks recorded as counted failures with three DISTINCT
  fingerprints (`e3651c1c…`, `69ebb022…`, `d8f4cd7e…`); repeat-stop
  correctly stayed dormant; the 3-cap fired instead
- [x] false-positive watch passed one round late: gate 3, explicitly told
  not to rubber-stamp the "expected" fix, credited the fixed TOCTOU and
  found one new REAL design-level defect — module-level state cannot cross
  MV3's popup/service-worker context boundary, so the whole in-memory-flag
  mechanism could never satisfy TASK.md's named scenario (grade 5/5)
- Escalation handoff graded 4/5: root cause + two concrete fix directions,
  decidable without transcripts; docked for burying the live blocker under
  superseded history (fixed — see table).

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| Gate found defects in depth order (mechanism-can't-work surfaced round 3, though visible from round 1) — two rounds spent polishing a dead end | review-gate.md now mandates a mechanism-first pass before line-level review | doc-level; next live multi-attempt lane |
| Gitignored env files don't survive worktree creation; symptom is a misleading wrong-credential test failure | SKILL.md worktree step: generate lane-scoped dummy credentials, never copy secrets; same rule added to haiku-worker.md | doc-level |
| Escalation buried the live blocker under 3 rounds of superseded history | escalate_summary.sh foregrounds a "Current blocker" section (tail of RUNSTATE.md) before history | `scripts.test.sh` ordering case |
| First live proof fingerprints discriminate review blocks by content | none needed | `scripts.test.sh` distinct-review-fingerprints case |

## Run #6 — 2026-09-28 — deltax-connectome-entity (first TDD-flow run)

First end-to-end run of the TDD flow: setup, plan, test review, baseline, red
test, launch checkpoint, two slices, guard checks, refactor. Venue: a Node
`node:test` repo under a research freeze (no artifact or seed changes). Plugin
run from the `feat/autodev-tdd` checkout with `${CLAUDE_PLUGIN_ROOT}`
hand-substituted; agents via the `general-purpose` fallback.

Lane `contract-input-guards`: reject a non-object input packet (slice 1, G1)
and a non-object candidate (slice 2, G2) with contract errors instead of a raw
`TypeError`.

- [x] setup detected `test_file` and `full_suite` with sources; 7 keys
  `unknown`, logged as skips by `verify.sh`
- [x] both red tests failed for the right reason (`TypeError` reading
  `timestamp` / `candidate_id`), shown at the checkpoint
- [x] each haiku worker one-shotted its slice; `verify.sh` pipeline and the
  review gate passed both; 4 commits (red, green, red, green)
- [x] per-slice cap reset observed (a synthetic failure went 1 → 0 at the green
  commit)
- [x] guard check: removing G1 or G2 turned the test red; throwaway worktree
  removed
- [x] refactor attempt made no change; `expect_run.sh green --no-test-changes`
  passed; HEAD = last green commit
- [ ] refactor drop path not exercised

## Run #7 — 2026-09-28 — deltax-connectome-entity (TDD failure path)

Lane `empty-candidates-escalate`, built to fail: the red test requires an empty
candidate list to return `ESCALATE`, contradicting an existing test that
requires a throw; TASK.md forbids editing existing tests.

- [x] attempt 1 edited the existing test to fit; `verify.sh` passed (gap);
  the review gate blocked on the TASK.md constraint (counted failure 1 of 3)
- [x] attempt 2 reverted, returned `spec_gap`, saved attempt 1 as a patch;
  `escalate_summary.sh` led with the spec gap as the current blocker
- [x] a worker-reported unrelated suite failure did not reproduce (machine load)

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| `commit_path.sh` picked an installed CommitCraft (2.28.1) that has no `commit --files` | picks CommitCraft only when its installed `commit.md` documents `--files` | `tdd.test.sh` capability cases; run #7 picked `script` live |
| Review gate's "scenario or guard with no test is blocking" would block slice 1 of 2 | gate gets the current slice as "N of M" and judges only up to it | doc-level; run #6 prompts carried it by hand |
| `record-failure … specification` left the gate at `continue`; escalation depended on the orchestrator | `specification` and `environment` set `needs_guidance` | `tdd.test.sh` controller cases |
| A worker could rewrite an existing test and pass `verify.sh` | test files present at `base_sha` are frozen unless TASK.md authorizes them | `tdd.test.sh` existing-test cases |
| `is_test_path` died under `verify.sh`'s `set -e` when `test_config` was absent, so no path was ever classified | `\|\| true` on the lookup | `tdd.test.sh` existing-test cases |

## Run #8 — 2026-09-28 — deltax-connectome-entity (installed-plugin headless run)

First run by a fresh orchestrator: two nested `claude -p` sessions with
`--plugin-dir autodev`, so `${CLAUDE_PLUGIN_ROOT}` and agent types resolved
natively; graded only from `.autodev/`, commits, and transcripts. Plan: 3
tickets — JSONL newline bug (`adapter.mjs`), unknown `candidate_id` guard, and
an empty-list ESCALATE ticket that contradicts an existing test.

- [x] session 1 `--plan-only --unattended`: 2 lanes (tickets 2 and 3 share
  `decide`), baselines green, red tests committed, `autodev:advisor` answered
  both checkpoints (3 native calls), decisions logged, stopped before slices
- [x] the orchestrator caught the ticket-3 contradiction while planning; the
  advisor dropped it before any red commit, logged in `dropped.md`
  (`drop_slice.sh` correctly not used — nothing to revert)
- [x] session 2 plain run resumed at the slice loop with no stops; both lanes'
  workers overlapped (spawned 5 s apart); `autodev:haiku-worker` ×4 and
  `autodev:review-gate` ×3 resolved natively
- [x] both lanes: verify pipeline, review gate pass, green commit, guard check
  caught its guard, refactor (ledger: no change; decide: committed after gate)
- [x] independent re-run on each branch: 83 and 82 pass, 0 fail; worktrees and
  main clean
- [ ] test review file written after the red commits (run.md step 3 comes
  first); findings were advisory only
- [ ] `drop_slice.sh` live path and the CommitCraft commit path: not exercised
  (offline tests only; CommitCraft path by decision)

## Run #9 — 2026-09-28 — throwaway repo (unattended with no profile)

- [x] `--plan-only --unattended` with no `.claude/autodev.md`: wrote
  `.autodev/profile-draft.md`, reported `awaiting_setup` with the copy command,
  created no lane, worktree, or commit, never tried to write the profile

Refactor-drop fixture (throwaway repo): a seeded refactor that edits a test
file is rejected by `expect_run.sh green --no-test-changes` (exit 1, names the
file); run.md's reset commands restore HEAD to `green_sha` with a clean tree.

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| Setup could not write `.claude/autodev.md` headless (Claude Code sensitive file); the session copied a draft into lanes by hand | setup is always a user stop; unattended without a profile reports `awaiting_setup` and stops before any lane | run #9 |
| Unattended spec gap would loop to the cap: the kept rule leaves the red test unsatisfiable | advisor keeping the rule drops the slice via `drop_slice.sh` | `tdd.test.sh` drop cases, run #11 |
| Live eval graded one worked answer's placements and wording | checks grade the quadrant rule (OAuth has many deps) and scenario meaning | `tests/eval/LIVE-LEDGER.md` |

## Run #10 — 2026-09-28 — throwaway repo (spec gap, cold run)

Fixture: a billing module with 3 scenarios. Scenario 2 (round half up in
`toCents`) contradicts a golden invoice fixture at another seam
(`test/fixtures/acme-march.json`, "truncated to the cent, never rounded").

- [x] the orchestrator read the fixture while planning; the advisor dropped
  scenario 2 at the launch checkpoint and kept the rule, logged in
  `decisions.md`; scenarios 1 and 3 green, full suite and golden test pass
- [ ] `drop_slice.sh` not reached (second cold run where planning caught the
  contradiction; see run #11)
- [ ] step 3 test review skipped: `review-tests.md` read at 21:34:37, worktree
  created 1 s later, no FIRST-U scores or report

## Run #11 — 2026-09-28 — throwaway repo (spec gap, seeded resume)

Same fixture, lane seeded with the real scripts: slice 1 green, slice 2 red
committed, `test-review.md` written, checkpoint confirmed. One headless
`--unattended` run resumed at the slice loop.

- [x] `autodev:haiku-worker` returned `status: blocked`,
  `spec_gap: … acme-march.json fixture requires truncation`
- [x] `autodev:advisor` chose "keep current rule", logged in `decisions.md`
- [x] `drop_slice.sh` ran: `dropped.md` written, restored to `green_sha`
  (slice 1), revert commit `revert(autodev): drop slice after spec gap`,
  `red_tests.txt` pruned to slices 1 and 3
- [x] the lane continued: slice 3 red, worker, review gate pass, green commit;
  full suite 4 pass, 0 fail; worktree clean

| Finding | Fix | Confirmed by |
| --- | --- | --- |
| Step 3 test review skipped with nothing to catch it (run #10) | step 3 writes `.autodev/<slug>/test-review.md`; `controller.sh set … checkpoint confirmed` refuses a TDD lane without it | `tdd.test.sh` checkpoint cases, run #12 |
| A drop at the launch checkpoint writes no `dropped.md` (runs #10, #12); run #8 wrote one. Nothing in the flow reads `dropped.md` | open | — |
| The worker returned `spec_gap` without a pinning test; `drop_slice.sh` runs `git clean`, so an uncommitted pinning test would be deleted anyway | open | — |

## Run #12 — 2026-09-28 — throwaway repo (test-review gate, plan-only)

Same fixture, fresh clone, one headless `--plan-only --unattended` run with
the step 3 wording from run #11's finding.

- [x] `test-review.md` written at 18:49:47 with FIRST-U scores per test file,
  before the first red commit (18:50:05); the gate never had to refuse
- [x] the advisor confirmed the checkpoint; `checkpoint: confirmed`
- [x] planning caught the scenario 2 contradiction again and dropped it at
  the checkpoint (no `dropped.md`, see the open finding in run #11)
