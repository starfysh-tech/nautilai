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
| Orchestrator-as-teammate never receives worker completion signals | documented: poll lane state in that context | open — needs a teammate-context run to confirm |

## Run #2 — planned — agent-feed (parallel lanes, auto-detected verifier)

Venue: `~/Code/agent-feed` (clean at `4866b7e`; `npm test` = `node --test`,
26 files, ~7.6s). Three lanes from its `TODO.md`, difficulty-tiered:

1. `pkg-main` (easy): fix `"main"` pointing at a nonexistent file — `package.json` only.
2. `db-wal-size` (medium): `getDbSizeBytes()` must count WAL sidecars — `src/database.js` + test.
3. `pipeline-cap` (hard, failure-prone on purpose): cap unbounded `sessionTurnCounts` Map + eviction regression test — `src/pipeline.js` + test.
4. `drop-sqlite-deps` fed as a 4th candidate only to confirm `parallel_safe`
   rejects it (touches lockfile) — run sequentially or not at all.

Behaviors this run must confirm (all currently unexercised live):

- [ ] `verify.sh` stack auto-detection carries the loop with NO lane VERIFY.sh
- [ ] 3 concurrent lanes: disjoint worktrees, no cross-lane file bleed
- [ ] concurrent `controller.sh` writes don't clobber `state.json` (no locking exists — a clobber is a finding, not a surprise)
- [ ] live failure path: classify → fingerprint → record-failure → gate stop on a real log
- [ ] escalation handoff is actionable without reading the transcript
- [ ] existing 26 test files stay green in every lane

Each failed checkbox becomes a Run #2 finding row with fix + regression case.
