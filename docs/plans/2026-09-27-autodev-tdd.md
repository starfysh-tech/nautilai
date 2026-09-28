# AutoDev TDD port — plan

Source: `mqol-aerie/.claude/skills/tdd/` (SKILL.md, README.md, HOW_TO_USE.md,
sample_input.json, expected_output.json). Goal: maximum parity inside autodev.
Glossary: `CONTEXT.md` (Lane, Slice, Test-fix lane, Red test, Launch checkpoint,
Advisor, Guard, TDD profile). Delivery: one PR.

## Decisions

| # | Decision |
|---|---|
| 1 | The full generic rule set lives in `autodev/skills/autodev/references/tdd.md`. The advisory modes run as orchestrator steps. |
| 2 | Keep general stack patterns (pytest/Factory Boy, Vitest/RTL), each in a section marked with its stack. aerie-only facts become generic rules. `pgtrigger` stays as a labeled example. |
| 3 | Setup writes the TDD profile: `.claude/autodev.md` in the main checkout. It is meant to be committed; the user commits it. |
| 4 | Lanes read the TDD profile only. A script decides what each role reads. Agents get no conditional instructions. |
| 5 | Setup detects each value with its source file (the same stack markers `verify.sh` auto-detects, plus task runners and CI). The user confirms or fixes each value. Missing evidence gives `unknown`. |
| 6 | `init_task_lane.sh` freezes the TDD content per role into the lane dir (see 29). It also freezes a copy of the profile frontmatter (`.autodev/<slug>/profile.md`), which the scripts read. Lanes never read the live profile. Keep the term "lane". |
| 7 | Red tests are written **one slice at a time** by the orchestrator, never all up front. A task with no testable behavior gets a structured `red_tests: exempt — <reason>` field in TASK.md, confirmed at the checkpoint. Exempt lanes skip red check, red commit, guard check and refactor, and verify through the lane `VERIFY.sh` as today. |
| 8 | One launch checkpoint. It confirms for each lane: seams, all GWT scenarios in slice order, quadrant placement and First-U choice, guards, exemptions, proposed test-fix lanes, and the first slice's red test with its actual failure line. |
| 9 | The quadrant sets the red-test kind: Q1/Q4 unit, Q3 integration at the outer seam, Q2 extraction authorized in TASK.md (unit red tests on the extracted part, integration on the coordinator). The First-U choice sets slice and lane order. |
| 10 | Guard check, run after the review gate passes. The orchestrator writes one guard-removal patch per guard. `expect_run.sh guard` makes a detached worktree at the green commit, confirms the guard's named test passes, applies the patch (a failed apply is an error, not a pass), and requires that named test to fail. A guard that stays green is a counted failure. Runs serially when the profile has no `db_isolation`. The result goes into DONE.md. |
| 11 | Review gate blocking: tautological assertion, a test that can never fail, implementation-coupled, test interdependence/shared mutable state, unseeded random values or real time, a test at an unconfirmed seam, a guard or scenario with no test. Advisory: private-method tests, fragile assertions, sleep/slow tests (FIRST-U F), placeholder data, coverage-driven tests, naming (FIRST-U U), and `getByTestId` over `getByRole` (included in `TDD-review.md` only when the profile `stack` lists `rtl`). |
| 13 | `verify.sh` attempt pipeline, stopping at the first failure: (1) frozen-test check: `git diff --quiet <red_sha> -- <red test paths> <profile test_config paths>`, which covers edits, deletes, renames and skip markers in test config; (2) every recorded red test via `test_file` (earlier slices must stay green); (3) `lint` + `format_check` on files changed since the lane's `base_sha`; (4) lane `VERIFY.sh` when present; (5) full suite from profile `full_suite`, then repo `VERIFY.sh`, then auto-detect. Steps 1–3 are skipped in the `baseline` phase. A non-exempt lane with no recorded red test, or with red tests and no `test_file`, fails. Other absent keys give a logged skip; an invalid value fails. Exempt lanes use the single-verifier path. |
| 14 | Lane order: plan, init lanes + worktrees (store `base_sha`), baseline (unchanged), first slice's red test, `expect_run.sh red` (must fail; exit 124/126/127 rejected; failure line saved), red commit, launch checkpoint, then slices: attempt, verify, review gate, green commit, next slice's red test + red check + red commit. After the last slice: guard check, then refactor. |
| 15 | Each slice's red test is committed on `autodev/<slug>` before its attempt. `red_sha` holds the latest red commit; the frozen check diffs against it, and earlier red tests are unchanged since their own commit because each slice's verify ran before its green commit. |
| 16 | Commits run hooks. The orchestrator fixes hook failures itself (format, lint, message, auto-fixer changes; the red test is re-run after each fix). It escalates only when a decision is needed: the hook rejects because tests fail, a fix would change a red test's assertion, or a secret scanner flags test data. |
| 17 | Hook fix cap: 3 tries. A repeated identical failure stops earlier. |
| 18 | Worker: on a spec gap it pins the current rule with a test, does not widen the code, and returns `status: blocked` with `spec_gap:` in `failure_signature`. The orchestrator records it directly with `controller.sh record-failure <slug> specification` (no log classification). The worker works one slice at a time, runs `format` before it returns, may add tests only at confirmed seams, and never edits red tests. |
| 19 | Coverage is measured and reported, never gated. After a pass, `verify.sh` runs `coverage` and saves the report in the lane dir. The review gate uses it for advisory findings. |
| 20 | Flags `--plan-only` and `--review-tests` run on their own. Both are part of the default flow. Input is a plan or ticket(s); the SKILL.md description changes to say so. |
| 21 | Pre-launch review of existing tests at touched seams. No auto-fix. Blocking-class findings become proposed test-fix lanes (ask-user). Advisory findings, FIRST-U scores and coverage gaps are reported. |
| 22 | Flags: `--setup`, `--plan-only`, `--review-tests`, `--unattended`. No flag gives the default flow. |
| 23 | With no profile, the default flow runs setup first (a one-time extra stop). |
| 24 | Profile format: flat YAML frontmatter with keys `test_file` (template with `{file}`), `full_suite`, `lint`, `format`, `format_check`, `coverage`, `db_isolation` (env assignment template with `{slug}`), `test_config` (paths frozen with red tests), `stack` (e.g. `pytest, factory_boy, vitest, rtl`). The prose body holds conventions. It is parsed by a python3 stdlib helper (autodev already requires python3, `controller.sh:12`): quoted values are supported; an absent key or `unknown` means skip; a present-but-empty or unparseable value is an error. |
| 25 | One green commit per slice, after verify and the review gate pass. It uses the same hook rules as 16/17. A green commit resets `counted_failures` and `last_failure_fingerprint` (new `controller.sh record-slice-green`), so each slice gets its own 3-cap; a repeated identical failure still stops the lane at once. |
| 26 | One refactor attempt after the last green commit. `expect_run.sh green --no-test-changes` checks that red tests and the full suite are green and no test file changed, and the review gate reviews it. On failure: `git reset --hard <green_sha> && git clean -fd` in the lane worktree, then assert HEAD equals `green_sha` and the tree is clean. A failed refactor never counts against the lane. |
| 27 | sample_input/expected_output become a live eval for `--plan-only` under `autodev/tests/eval/`, following the `relay/tests/eval/` layout. It uses structural checks only, a threshold across runs, and `LIVE-LEDGER.md`. It is not in CI. |
| 28 | `references/tdd.md` keeps rationale sentences that change behavior. Pure justification is stripped and listed in the PR body. |
| 29 | `init_task_lane.sh` cuts `tdd.md` by section markers and by the profile `stack` into `TDD-worker.md` (loop rules, spec gap, slices, format, extra-test seams, matching stack patterns, profile prose) and `TDD-review.md` (blocking/advisory split, anti-patterns, coverage gaps, guards, profile prose). The orchestrator reads the full `tdd.md`. An unknown or missing marker fails init. |
| 30 | In the main session the stops stay up front. With `--unattended`, recorded in state.json by a script, the advisor makes allowed decisions and logs each one to `.autodev/<slug>/decisions.md`. The user validates at the end; an adjustment re-runs only the affected lanes. Without the flag and with no user reachable, the run stops, saves, and sets each lane's `checkpoint` to `awaiting`. `init_task_lane.sh` sets `checkpoint: pending`; the `controller.sh check` gate stops until it is `confirmed`. A lane that is fully confirmed runs with no stops and no advisor. |
| 31 | Never-advisor list (always escalate): changes outside the lane branch (hook config, CI, shared config), secret-scanner hits, anything irreversible. The advisor may accept test-fix lanes. Extend the autodev "Noted exception" in `docs/conventions/finding-dispositions.md`. |
| 32 | Commits go through CommitCraft when it is installed for this repo (`installed_plugins.json` entry with `scope: user`, or `scope: project` with `projectPath` equal to the repo root); otherwise through `commit_lane.sh`. The picker script prints the one command to run and logs why. A parse error falls back to `commit_lane.sh` with a warning. CommitCraft's `commit` workflow gains a file-allowlist mode, so it stages only the lane's named files (today it stages every modified or untracked file, `commit.md:25-29`). |
| 34 | `commit_path.sh` picks CommitCraft only when its installed `commit.md` documents `--files` (capability, not version). Found in the first dogfood run. |
| 35 | The review gate gets the current slice as "N of M" and judges scenarios and guards only up to it. Found in the first dogfood run. |
| 36 | A `specification` or `environment` failure sets `needs_guidance`, so `controller.sh check` stops the lane by script. Found in the failure-path dogfood run. |
| 37 | Test files that existed at `base_sha` are frozen in `verify.sh` unless TASK.md lists them under `## Test edits authorized` (test-fix lanes). Workers add tests in new files. Found in the failure-path dogfood run. |
| 38 | Unattended spec gap: the advisor keeps the current rule and `drop_slice.sh` drops the slice (reverts its red commits, prunes red tests, logs `dropped.md`); the user validates the drop at the end. Avoids the retry loop on an unsatisfiable red test. |
| 39 | Setup is always a user stop: Claude Code treats `.claude/autodev.md` as a sensitive file, so an unattended run with no profile writes `.autodev/profile-draft.md`, reports `awaiting_setup`, and stops before any lane. The advisor never answers setup (revises 30). Found in the headless validation run. |
| 40 | Step 3 writes `.autodev/<slug>/test-review.md`, and `controller.sh set <slug> checkpoint confirmed` refuses a TDD lane without it. Found in run #10, where the test review was skipped. |
| 41 | A scenario dropped at the launch checkpoint is logged by `drop_slice.sh --checkpoint`, so `dropped.md` records every drop. In an unattended run the worker skips the spec-gap pinning test, since `drop_slice.sh` cleans the worktree; the existing test that holds the rule is the evidence. Found in runs #10–#12. |
| 33 | Design rationale goes in the PR body and a `docs/plugin-changelog.md` entry. No ADR. This plan is committed with the PR. |

## Components

- **New scripts:**
  - `expect_run.sh red|green|guard` holds the red check, the refactor check and the guard check.
  - `commit_lane.sh` stages an allowlist, writes a Conventional Commit, runs hooks, and never uses `--no-verify`.
  - `commit_path.sh` picks CommitCraft or `commit_lane.sh`.
  - `profile.py` reads the frontmatter (`get`) and cuts `tdd.md` per role (`cut`).
  - `lane_run.sh` (sourced) holds the timeout runner and lane env shared by `verify.sh` and `expect_run.sh`.
- **Changed scripts:**
  - `init_task_lane.sh` renders TASK.md from `templates/TASK.md`, so there is a single source. It freezes the role files and the profile.
  - `create_worktree.sh` stores `base_sha`.
  - `baseline_verify.sh` resets only `needs_guidance` to `pending` and never overwrites `confirmed`.
  - `controller.sh` gets the `checkpoint` gate in `check`, `record-slice-green`, `run-set`/`run-get` for `unattended`, and `get`.
  - `verify.sh` gets the pipeline from decision 13.
- **`parallel_safe.sh`** keeps reading TASK.md at init. The new template sections use placeholder text free of its trigger words (`parallel_safe.sh:8`).
- **Agents:**
  - `haiku-worker.md` reads `TDD-worker.md`.
  - `review-gate.md` reads `TDD-review.md`.
  - New `advisor.md` (staff-engineer role, `model: opus`).
- **Skill:** `SKILL.md` becomes a router plus `workflows/{run,setup,plan-only,review-tests}.md`, mirroring commitcraft (`commitcraft/skills/commitcraft/SKILL.md:21-29`). Plus `references/tdd.md`.
- **Templates:** TASK.md gains seams, scenarios (GWT, slice order), quadrant/First-U, guards, authorized extractions, the exemption field, and red-test paths per slice. DONE.md gains guard check results, coverage, the decision log, and advisory findings.
- **CommitCraft:** an allowlist mode in `workflows/commit.md`.

## Tests

- `autodev/tests/tdd.test.sh` (new; `scripts.test.sh` keeps covering the existing scripts):
  - A `make_repo` helper builds every fixture repo. `scripts.test.sh` keeps its inline fixtures; refactoring it is out of scope.
  - Parser cases: `: `, `#`, `{file}`, quoted and unquoted values, CRLF line endings, body `---`, present-but-empty value.
  - Role-file cutting.
  - `expect_run.sh`: all 3 modes, including exit 124/127 rejection and failed patch apply.
  - The frozen-test check, including delete and rename.
  - `verify.sh`: stage order, phase skip, precedence.
  - `commit_lane.sh`: allowlist and hook failure.
  - `commit_path.sh`: fake `HOME` with present, absent, other-project and malformed states.
  - Controller statuses, `record-slice-green` resetting the cap, and `baseline_verify.sh` preserving `confirmed`.
  - A `parallel_safe` regression with the new template.
- `tdd.test.sh` runs in CI (`validate.yml`) next to `scripts.test.sh`.
- Run locally with a PATH shim that puts `/bin/bash` 3.2 first. `bash` resolves to Homebrew 5.x, so the shim is required for a real 3.2 run.
- The CommitCraft allowlist mode has no script suite; check it live once.
- The live eval (decision 27) covers the model-driven parts.

## Docs

- Update the description in `SKILL.md`, `plugin.json` and `marketplace.json` (sync is CI-enforced).
- Update `docs/plugins/autodev.html`, `docs/llms.txt`, the `autodev/README.md`, `docs/plugin-changelog.md`, and the finding-dispositions table and exception.
- Update the `commitcraft/README.md` and `docs/plugins/commitcraft.html` for the allowlist mode.

## Assumptions to validate before implementing

- [x] **A repo whose pre-commit hook runs tests rejects every red commit.** Checked mqol-aerie: `.husky/pre-commit` and `lint-staged.config.mjs` run no tests (ruff check --fix, ruff format, prettier, eslint, semgrep, comment-blocks). Red commits can pass there. ruff/prettier are auto-fixers, handled by decision 16. semgrep `p/secrets` scans `server/**/*.py` including tests, so test data can hit the never-advisor list. Other repos stay unknown until setup reads their hooks; setup records "hook runs tests: yes/no" in the profile prose.
- [ ] **`installed_plugins.json` keeps its current shape.** Shape confirmed on disk (`scope`, `projectPath`; commitcraft appears as user and as project for 2 repos). No documentation found for it. Stays unverified; the fallback to `commit_lane.sh` is safe.
- [x] **CommitCraft can take a file allowlist without breaking callers.** No other plugin calls `/commitcraft commit` (only `/commitcraft push` from pr-comment-review). The staging step is `workflows/commit.md` Phase 2 step 3. No script test covers the commit workflow (`commitcraft/tests/` has `detect-rp`, `pr-template`), so the allowlist mode needs a live check, not a suite update.
- [x] **A plugin agent can set `model: opus`.** Official plugins do (`claude-security`, `code-simplifier` agents). Spawning it from a subagent context stays unverified; the existing `general-purpose` fallback (`SKILL.md:90-94`) covers it.
- [x] **TASK.md placeholders avoid `parallel_safe.sh:8` trigger words.** Draft sections (Seams, Scenarios, Quadrant with "complexity and coupling", Guards, Authorized extractions, Red tests) returned `true`. Re-run on the final template.
- [x] **Per-slice commits keep the 3-cap meaningful.** `counted_failures` never resets today (`controller.sh:57-58`; `record-success` at :81-87 sets `done` only). Resolved by decision 25: reset at each green commit.
- [x] **The sample pair supports a structural eval.** `expected_output.json` has scenario ids AC-001 to AC-004, First-U "Password validation…" in Q1, per-quadrant lists (OAuth and 2FA in Q2, SendGrid and PostgreSQL CRUD in Q3, email format and bcrypt in Q4), and 2 evaluated tests scored 23 and 14.

## Environment notes (mqol-aerie)

- `.husky/post-checkout` runs `mise run setup-worktree` on every `git worktree add` unless `SKIP_WORKTREE_SETUP` is set. Every lane worktree and every guard-check worktree pays that setup. The guard worktree needs a working env to run tests, so the setup is required, not waste.
- `.husky/pre-commit` blocks commits on `main`/`master`. Lane branches are `autodev/<slug>`, so this does not fire.
