# Plugin changelog

Curated, human-written log of **major** changes to nautilai's plugins —
new plugins, new skills/subcommands, conventions adopted, behavior changes a user
would notice. Reverse-chronological.

> **Not the release changelog.** Per-release, per-commit notes are auto-generated
> by release-please in the root [`CHANGELOG.md`](../CHANGELOG.md) from Conventional
> Commits. That file is machine-owned and grouped by commit type across the whole
> linked repo. *This* file is the opposite: hand-curated, organized by plugin, and
> only the changes worth a human skim. Do not hand-edit the root `CHANGELOG.md`.

See [`CLAUDE.md`](../CLAUDE.md) → "Plugin changelog" for when and how to update this.

---

## 2026-07-23

- **sentry-ops** — narrowed from four workflows to two (`audit`, `instrument`) to
  complement Sentry's official `sentry` plugin instead of competing with it. That plugin
  is first-party, bundles a Sentry MCP server, and owns the two biggest jobs — SDK setup
  across ~20 languages and fixing production issues (`sentry-fix-issues`). `sentry-ops`'s
  `triage` and `investigate` duplicated the issue-fixing half with a worse setup story
  (you had to wire the MCP yourself), so they were dropped. What's left is the two gaps
  the official plugin leaves and does not cover: auditing an *existing* setup against
  current docs, and the *inbound* PII gate — what the SDK attaches to events on its own.
  The plugin is now fully repo-only (no Sentry MCP), which also makes the two PII models
  cleanly complementary: the official plugin guards data coming out of Sentry, this
  guards what goes in.

## 2026-07-22

- **sentry-ops** — the Sentry knowledge worth keeping was trapped in one project's
  repo-specific skill, so it was generalized into a plugin. The part that justified the
  move is the PII boundary: the dangerous exposure is not what you pass to
  `captureException`, it is what the SDK attaches on its own — console-call breadcrumbs
  that survive build-time stripping of `console.log`, and server-side request data
  (cookies, headers, query strings, bodies, URLs) collected by default, which turns any
  route carrying a token or share ID in its URL into event data. Notably, porting that
  section is what caught a wrong rule in the original skill: it asserted that IP-derived
  geo could not be disabled from `Sentry.init`, and the docs say `sendDefaultPii` (which
  defaults to `false`) gates the IP address. The plugin now verifies that boundary
  against docs instead of asserting it. The audit half is deliberately *not* a checklist: a static list
  of "correct" Sentry config rots as the SDK moves, so `audit` re-queries the official docs
  at runtime (Context7, degrading to `WebFetch` and then to structural-only checks, saying
  so in the report either way) and compares against what the repo actually has. Claude Code
  only — it is MCP-centric and a Hermes port would have nothing to call.

## 2026-07-17

- **review-plan, dep-review, pr-comment-review** — these skills now fan out on Hermes
  via delegation instead of always degrading to inline-sequential. The prior "Hermes has
  no subagent primitive" premise was **wrong**: probing the live binary showed Hermes has
  `delegate_task`, and — like Claude's `Task` — a loaded skill drives it just by stating
  fan-out *intent*, so each SKILL.md gained an additive runtime-translation note (it names
  no Hermes tool; the agent picks delegation up itself). Inline Read/Grep stays the fallback
  only where no delegation primitive exists.
- **autodev stays Claude-only, but for the real reason.** The same probe found Hermes
  subagents share the parent's one working directory — there is **no git-worktree
  isolation**. autodev's value is isolated worktrees per lane (clean per-attempt rollback),
  not the mere existence of subagents; parallel workers in one directory would collide. The
  convention (`docs/conventions/dual-runtime.md` Rule 7) and `docs/llms.txt` were corrected
  to test *worktree isolation*, not "subagents exist."

## 2026-07-14

- **phi-scan, cc-validate-hooks** — both now ship an offline **eval** that pins the
  deterministic core to a measured signal. This came out of reviewing
  microsoft/SkillOpt for adoption: the conclusion was that the scarce asset is the
  *benchmark*, not an optimizer — a hand-authored skill has no regression net, so a
  refactor can quietly break it. `phi-scan` grades its scanner's recall/precision;
  `cc-validate-hooks` grades one fixture per validator branch. Authoring the second
  one earned its keep immediately — it surfaced that the validator core crashes on
  invalid JSON, guarded only by its shell wrapper. The pattern is now convention
  [#13](conventions/README.md#13-skill-evals--gradeable-regression-nets)
  ([full spec](conventions/skill-evals.md)); the rest of the fleet is triaged in
  [`skill-eval-backlog.md`](skill-eval-backlog.md).

## 2026-07-13

- **commitcraft** — `setup` and `check` are now **Claude Code only**; Hermes ships `commit`,
  `push`, `pr`, `release`. Hermes security-scans every installed skill, and
  `commitcraft-setup.sh` — which `npm install`s commitlint/husky, `pip install`s pre-commit, and
  reads `~/.ssh/*.pub` to configure signing — scored HIGH `exfiltration` + MEDIUM `supply_chain`
  and blocked the **entire bundle** (`Verdict: CAUTION`). All 12 findings came from that one
  script and its templates; the other four scripts are clean.

  The verdict is right: provisioning tooling *is* installing packages. So the bundle omits the
  script rather than asking anyone to `--force` past a security gate, and Hermes users configure
  a repo once by hand — steps now in
  [commitcraft's README](../commitcraft/README.md#hermes-repo-setup).

  Worth remembering: our scanner probe *passed*. It was a 30-line analogue of a 1,500-line
  provisioning script, and it had no equivalent of the `~/.ssh` reads that produced the HIGH
  findings. A probe proves a mechanism, not a payload — see
  [dual-runtime.md](conventions/dual-runtime.md) lesson 5.

## 2026-07-12

- **commitcraft** ([`skills/commitcraft/SKILL.md`](../commitcraft/skills/commitcraft/SKILL.md)) —
  now runs in **Hermes Agent** as well as Claude Code, from this same repo. The constraint that
  shaped the design: Claude's validator refuses a `skills` path containing `..`, and Hermes ships
  the *skill directory only* — so the two layouts cannot share one directory, and something has to
  be generated. We chose to generate the **Hermes** side
  ([`hermes/sync-resources.sh`](../hermes/sync-resources.sh)) rather than relocate Claude's scripts,
  because a Claude regression was the one unacceptable outcome. Claude's diff is a single additive
  "Resource paths" section; its scripts, templates, tests, and manifests are byte-identical.

  Each runtime substitutes only its own path token and ignores the other's, which is what lets one
  SKILL.md serve both. Validated end-to-end in both runtimes before merge (throwaway probe repo,
  since the published Hermes docs proved wrong on several points — `tap add` indexes nothing, and
  the "required" frontmatter fields are not enforced). Two findings worth remembering: Hermes
  **strips the executable bit** on install (hence `bash <script>` on the Hermes path), and
  `${CLAUDE_PLUGIN_ROOT}` inside workflow files has *always* been model-resolved rather than a shell
  variable — so the Hermes adapter leans on the same mechanism CommitCraft already relied on.

  `autodev` stays **Claude-only**: its value is subagent fan-out and git-worktree isolation, and
  Hermes has no subagent primitive — a port would be a hollow shell.

## 2026-07-08

- **relay** ([`skills/handoff/SKILL.md`](../relay/skills/handoff/SKILL.md)).
  Handoff docs now demand a done-criterion for every in-progress item, and the
  curation guidance names what to keep verbatim (errors/stack traces, function
  signatures/type definitions, test names + failure reasons) vs drop. Resuming
  sessions were re-deriving what "done" meant for half-finished work — a target
  the previous session already knew but never wrote down.

- **commitcraft** ([`templates/.commitlintrc.yml`](../commitcraft/templates/.commitlintrc.yml)).
  Raised the commit `subject-max-length` from 50 to 72 (the Conventional Commits
  default) in the shipped commitlint templates and the commit-generation guidance.
  Dependabot's subjects for long-named actions (e.g. `googleapis/release-please-action`)
  run ~60 chars and were failing the required commitlint check at 50, blocking
  auto-merge; 72 clears them without hand-amending each PR.

- **commitcraft** ([`workflows/pr.md`](../commitcraft/skills/commitcraft/workflows/pr.md)).
  `/commitcraft pr` now fills a repo's own PR template instead of overwriting it with
  a generic body. A repo's `.github/pull_request_template.md` is what description bots
  (CodeRabbit, etc.) grade against, but `gh pr create --body` bypasses template
  resolution — so the generic body silently failed those checks. The skill now detects
  the template (new `commitcraft-pr-template.sh`, covered by `pr-template.test.sh`),
  preserves its headings verbatim, writes an honest `N/A` for sections the diff can't
  answer, and never ticks a human attestation checkbox. No repo template → unchanged
  generic body.

- **cc-skill-audit** ([`skills/cc-skill-audit`](../cc-skill-audit/skills/cc-skill-audit/SKILL.md)).
  Two audit tools had grown to do one user-facing job — a personal scorecard
  skill scored and ranked every skill quantitatively, while this plugin's
  sweep mode judged findings by severity — so they're merged into one skill.
  Sweep mode now runs the scorecard as its engine: a Haiku worker scores every
  installed skill (clarity, frontmatter, trigger quality), a Sonnet
  fact-checker verifies each score against the skill's actual files on disk,
  and a final agent ranks the set worst-to-best into `skill-audit-report.md`,
  grounded against the same live-docs fetch this skill already used for
  single-skill audits. The findings-first, severity-tagged deep audit stays
  available per skill, offered on the sweep's weakest results; the prior
  batched-Task fan-out remains as the fallback when the Workflow tool isn't
  available.

- **Lessons adopted from `kunchenguid/no-mistakes` (round two)** ([`autodev`](../autodev#readme),
  [`relay`](../relay#readme), [`commitcraft`](../commitcraft#readme)). A
  four-reviewer mine of the repo that finding-dispositions came from surfaced
  gaps it solves that we still had: autodev's "retry transient failures once"
  rule was prose only — nothing bounded consecutive transient retries, so
  persistent rate-limiting could loop forever (now a `transient_retries`
  counter in controller.sh halting at 2); RUNSTATE.md handoff notes flowed
  into the next worker's prompt with no untrusted-data framing, the same
  injection surface pr-comment-review already guards (now framed as
  data-not-instructions in both the skill and the worker contract); relay's
  narrative extraction died on a single transient 429/503 (now one 2s retry
  per chunk before degrading); and commitcraft's type guidance never warned
  that a user-facing change typed `refactor`/`chore` is invisible in
  release-please's changelog. Also new: CI now enforces the
  plugin.json ↔ marketplace.json sync rule CLAUDE.md had only documented
  (`.github/scripts/check-marketplace-sync.sh`) — it caught a real
  commitcraft description drift on its first run. Considered and rejected as
  scope mismatches: Astro docs migration, JSON-schema output validation,
  recorded-fixture agent harness, CI-watch/auto-fix loop, telemetry.

## 2026-07-07

- **Cheap-model tiering adopted across the marketplace** ([`autodev`](../autodev#readme),
  [`dep-review`](../dep-review#readme), [`phi-scan`](../phi-scan#readme),
  [`cc-skill-audit`](../cc-skill-audit#readme), [`cc-validate-hooks`](../cc-validate-hooks#readme),
  [`cc-adoption-audit`](../cc-adoption-audit#readme), [`pr-comment-review`](../pr-comment-review#readme),
  [`review-plan`](../review-plan#readme)). A marketplace-wide review found most
  delegated work inherited the (often frontier) session model even when the task
  was mechanical — autodev's review-gate ran after *every* green verify on the
  parent model, dep-review spawned one parent-model agent per Dependabot PR. Now:
  judgment-adjacent review work pins `sonnet` (review-gate, dep-review per-PR
  agents); mechanical classification/extraction fans out to `haiku` (phi-scan
  triage, cc-skill-audit sweeps, pr-comment-review triage at scale, review-plan
  Explore fallbacks, cc-adoption-audit inventories); the run-a-script-and-relay
  skill (cc-validate-hooks) runs entirely on `haiku` in a fork.

- **commitcraft no longer converts an unrecognized subcommand into a commit**
  ([`commitcraft`](../commitcraft#readme)). `/commitcraft pr for the auth fix`
  used to miss the workflow-file lookup and silently fall back to the *commit*
  workflow — a wrong state-changing action. Dispatch now keys on the first token
  and refuses unknown subcommands. Same sweep: issue extraction only trusts a
  trailing `-<num>` branch suffix (so `fix/upgrade-node-18` no longer comments on
  issue #18), and the pr/release flows derive the default branch instead of
  hardcoding `main` — the plugin now works on `master` repos.

- **Silent-blank-audit gaps closed in the scanners**
  ([`rbac-django`](../rbac-django#readme), [`phi-scan`](../phi-scan#readme),
  [`cc-validate-hooks`](../cc-validate-hooks#readme)). Three review skills could
  report "clean" while structurally unable to see the problem: rbac's
  permission-class and `@api_view` inventories were *empty* (not "reduced")
  without ast-grep — they now have stdlib AST fallbacks; phi-scan's
  restricted-ZIP prioritization was dead code its own SKILL.md told the triage
  agent to trust — restricted prefixes are now genuinely flagged
  (`zip_5(restricted)`); cc-validate-hooks never looked at
  `.claude/settings.local.json`, the most common home for personal hooks — it's
  now in the validated set.

- **review-plan is now invoke-on-request and leaves plans recoverable**
  ([`review-plan`](../review-plan#readme)). It auto-fired on *any* shared plan
  and then edited the plan file in place — an unrequested destructive edit, and a
  violation of the finding-dispositions recoverability contract for non-VCS
  plans. The trigger now requires explicit review intent, and in-place edits back
  up untracked/non-repo plans first.

- **Stale docs purged where they contradicted the shipped behavior**
  ([`frontend-review`](../frontend-review#readme),
  [`github-issue-auditor`](../github-issue-auditor#readme)). frontend-review's
  README still described the pre-restore "no engine, model-only" design and its
  `references/HOW_TO_USE.md` files documented import APIs that never shipped;
  github-issue-auditor's HOW_TO_USE predated the Phase-3 approval gate and the
  taxonomy-detection feature (and analyzer.py still hardcoded `type: *` labels —
  now parameterized to the detected taxonomy).

- **wireframe component catalogs are now project-local**
  ([`wireframe`](../wireframe#readme)). `--update-reference` wrote per-project
  catalogs into the plugin's own install cache — leaking one project's components
  into every project and getting wiped on every plugin update. Default target is
  now `.claude/wireframe-catalog.md` in the project.

## 2026-07-06

- **relay `pending`-marker TTL is now startup-only, never on `/clear`**
  ([`relay`](../relay#readme)). The 30-minute staleness guard was meant to stop
  a long-dead marker from injecting a stale session as authoritative context —
  but it fired on `source=clear` too, where it's actively wrong: a `/clear` is a
  *deliberate* handoff-then-continue, and a normal handoff→break→clear routinely
  exceeds 30 minutes, silently dropping the plugin's primary flow (observed live
  at 36 min). Time was a poor relevance proxy anyway — consume-once already
  bounds a marker to a single injection. The TTL now guards only `source=startup`
  (opening Claude Code cold, possibly days later on unrelated work); `/clear`
  honors the marker regardless of age.

- **relay secret scrub and harness-noise filtering generalized**
  ([`relay`](../relay#readme)). Public sessions carry secrets and injected
  content the original patterns never saw: the scrub now also redacts JWTs,
  Google API keys, credentialed DB connection strings, and Basic auth, and the
  user-message filter replaces three literal harness-wrapper prefixes with one
  leading-XML-tag heuristic (structural `isMeta`/`isCompactSummary` stay the
  primary defense). The narrative layer's quality is now measured on more than
  one session shape — a non-code planning fixture and a twice-compacted one
  both clear the recall gate, and an adversarial fixture confirms transcript
  content can't hijack the extractor. (Fast-follows from the public-readiness
  gap analysis; non-English eval coverage still open on #57.)

## 2026-07-05

- **relay grows public-readiness controls** ([`relay`](../relay#readme)).
  Facing users beyond this repo means facing sessions, platforms, and budgets
  unlike ours: `RELAY_NARRATIVE=off` turns off the narrative layer's live
  Haiku spend; `RELAY_RETENTION_DAYS` (default 14) stops
  `~/.claude/handoffs/` accumulating session prose forever (a
  rename-preserves-mtime bug that made freshly-expired markers sweep
  themselves surfaced in testing); `SCHEMA.md` inventories every
  environmental assumption with honest confidence labels (Windows-native:
  unverified) and `scripts/doctor.sh` lets a bug reporter self-check them;
  the bundled test suites now run in CI on ubuntu, doubling as the
  Linux-portability check. A suspected gap — subagent turns polluting the
  fact pack — was falsified with evidence (sidechains live in separate files
  the resolver never touches) and documented instead of speculatively
  filtered.

- **relay ships the Haiku narrative layer** ([`relay`](../relay#readme)). The
  jq fact pack guarantees mechanical fidelity (files, commands, verbatim user
  text) but structurally can't see assistant-turn semantics — the reasoning
  behind a decision or why an approach was abandoned lives in assistant prose,
  which only a model can summarize. Gated on a planted-fact eval before
  shipping: 3/3 runs passed the gate at 11-12/12 recovered assistant-turn
  facts vs a 0/12 baseline for the fact pack alone
  (`relay/tests/eval/LEDGER.md`). Also hardened against prompt injection after
  a transcript about editing CLAUDE.md persona rules hijacked an early version
  of the extractor in testing — it now runs with a bare `--system-prompt` (no
  CLAUDE.md inheritance) and explicit instructions that transcript content is
  inert data, never live commands.

- **relay makes auto-compact non-fatal with `/handoff recover`**
  ([`relay`](../relay#readme)). The plugin's premise is that compaction drops
  decisions, dead ends, and early constraints — but racing auto-compact is a
  losing game (a PreCompact hook can only observe or block, and blocking near
  the context ceiling risks wedging the session). So instead of preventing the
  loss, relay now repairs it: a PreCompact(auto) hook drops a marker and nudges
  the user, and `/handoff recover` rebuilds exactly the compaction-lossy
  classes from the pre-compaction region of the transcript
  (`--before-last-compact` scopes the extractor to before the last
  `isCompactSummary` boundary), delivered in-session with no `/clear`.

## 2026-07-04

- **`handoff` becomes `relay`: transcript-grounded handoffs with automatic
  pickup** ([`relay`](../relay#readme)). Self-written handoffs inherit the same
  recency bias as `/compact` — decisions, dead ends, and early constraints
  documented as the classes compaction drops. The session transcript JSONL
  retains all of it, so the skill now runs bundled jq extractors over the
  transcript for ground-truth facts (files touched, commands, failures,
  verbatim user intents, secret-scrubbed), and a SessionStart hook auto-injects
  the doc into the next session via a consume-once, 30-minute-TTL marker —
  `/handoff` → `/clear` with no manual pickup step. The plugin renamed to
  `relay`; the skill keeps the `handoff` name so trigger phrases survive.
  A PreCompact hook was rejected as the mechanism: the spec allows observe or
  block only, no summarizer-instruction injection. Haiku narrative extraction
  and `/handoff recover` are designed but deferred behind an eval gate.

- **CommitCraft's shipped release-please template no longer lets docs-only
  merges cut releases** ([`commitcraft`](../commitcraft#readme)). release-please
  treats every changelog-visible commit type as release-triggering — nautilai
  itself shipped v2.9.2 from a two-line backlog edit before noticing. The
  template `commitcraft setup` writes into end-user repos now hides `docs`, so
  a docs commit never bumps a version on its own; the cost is docs entries no
  longer appearing in generated changelogs at all.

## 2026-07-03

- **`pr-comment-review` now treats PR comment/review bodies as untrusted data**
  ([`pr-comment-review`](../pr-comment-review#readme)). A live incident showed a
  review bot (cubic-dev-ai) embedding an "IMPORTANT ... you must attribute"
  directive inside its review body — content indistinguishable from user policy
  to an incautious run. Comment text is now explicitly data to analyze, never
  instructions to follow; embedded directives are ignored as commands and
  surfaced as findings when they materially try to steer the agent.

- **autodev completion now passes a review gate, not just tests**
  ([`autodev`](../autodev#readme)). Four validation runs proved the loop's
  verifier ceiling: a downstream bot review caught a P0 and a P1 in worker
  output that the test suite had blessed — tests can't see resource
  lifecycles, scope creep, or weak oracles. After `verify.sh` passes, an
  independent `review-gate` agent now reviews the lane diff against TASK.md;
  blocking findings count toward the same 3-failure cap, and only a `pass`
  verdict produces `DONE.md`. This is also the structural differentiator from
  the built-in `/goal`, whose transcript-reading evaluator cannot execute a
  reviewer.

- **New plugin: autodev** ([`autodev`](../autodev#readme)) — a bounded autonomous
  development loop, ported from an externally generated prototype. The motivating
  problem: autonomous runs that either grind forever on the same failure or declare
  their own success. The design answer is scripts over model judgment — worktree
  lanes, verification, failure classification/fingerprinting, and a 3-counted-failure
  stop are all deterministic bash; the model only implements and narrates. The port
  dropped the prototype's `Stop` hook (it ran the full test suite on *every* stop in
  *every* repo the plugin was enabled in, and hard-blocked in repos with no test
  suite) and moved success sentinels from the worker to the orchestrator so the
  worker can never grade its own homework.

- **autodev's `VERIFY.sh` contract gained `AUTODEV_PHASE`**
  ([`autodev`](../autodev#readme)). The plugin's first live validation run — which
  produced its own test suite via the loop — hit a structural deadlock for
  greenfield tasks: baseline and completion invoked the *same* verifier, so a
  deliverable that doesn't exist yet either fails baseline (lane never starts) or
  falsely passes completion. Lane verifiers now branch on
  `AUTODEV_PHASE=baseline|attempt` instead of every author reinventing a
  marker-file hack. Same run surfaced that relative lane paths broke verifier
  resolution after `cd` — fixed by resolving before entering the worktree.

## 2026-06-25

- **commitcraft's manual release notes now honor the repo's own
  `release-please-config.json` sections** ([`commitcraft`](../commitcraft#readme)).
  Phase 3 used a hardcoded type→section table, so a repo with a release-please
  changelog config only got *its* categories if release-please actually ran. Now the
  manual path reads `changelog-sections` from the config when present (built-in table
  as fallback) — a repo declares its categories once and gets a consistent changelog
  whether release-please automates the release or commitcraft cuts it by hand. No
  automation required to honor the config.

- **commitcraft `release` no longer dead-ends on a disabled release-please**
  ([`commitcraft`](../commitcraft#readme)). Phase 1 deferred to release-please on
  the mere *presence* of its workflow file — so a scaffolded-then-neutered
  release-please (skip flags, no `contents: write`, manifest stuck at `0.0.0`)
  left the user unable to release at all, with no actionable error. It now detects
  whether release-please is actually *functional* (new
  `commitcraft-release-detect-rp.sh`, with bash tests + CI) and falls back to the
  manual tag/release path — stating one line of *why* — when it's `DISABLED`/`ABSENT`.
  The release analyzer's clean-tree guard also relaxed: a tag is commit-based, so it
  blocks only when local `main` is out of sync with origin and merely warns on
  unrelated working-tree changes.

- **Five plugins ported from a private project**, conventionalized on the way in
  (degenericized off hardcoded paths/company specifics; finding-dispositions,
  shoals, `file:line` evidence, and `${CLAUDE_PLUGIN_ROOT}`-rooted scripts applied)
  rather than copied as-is — so battle-tested skills become installable without
  dragging in repo-specific assumptions:
  - **rbac-django** ([`rbac-django`](../rbac-django#readme)) — a 3-skill RBAC
    security workflow for Django/DRF + React: audit gaps → threat-model abuse
    cases → remediation playbooks. Backend/frontend roots auto-detected; the
    bundled scanner fails open when `ast-grep`/`rg` are absent.
  - **frontend-review** ([`frontend-review`](../frontend-review#readme)) — React
    architecture + Tailwind design-token audits; auto-detects the frontend source
    root instead of assuming `client/`.
  - **dep-review** ([`dep-review`](../dep-review#readme)) — Dependabot PR triage.
    The source's silent auto-merge was demoted to a gated disposition: every merge
    needs approval unless an explicit `--auto-merge-patch` opt-in is passed.
  - **github-issue-auditor** ([`github-issue-auditor`](../github-issue-auditor#readme))
    — issue-hygiene audit (duplicates, orphans, stale, labels) against the repo's
    own auto-detected label taxonomy; read-only unless a mutation is approved.
  - **wireframe** ([`wireframe`](../wireframe#readme)) — low-fi UI wireframes
    (ASCII/wiremd/Mermaid). Generative, so finding-dispositions and shoals were
    deliberately skipped (noted in its README).

- **New plugin: pr-review-deep** ([`pr-review-deep`](../pr-review-deep#readme)).
  Existing review plugins address *received* comments (pr-comment-review) or
  validate *plans* (review-plan) — none generated a rigorous, structural
  code-quality review of a branch/PR. This fills that gap: an evidence-first
  reviewer that proposes behavior-preserving restructurings with cited `file:line`
  and never performs them. Propose-only by design so it can't expand a PR's scope.
  Follows the finding-dispositions (all `report`, `auto-fix` none) and shoals
  conventions; user-invoked and forked.

## 2026-06-24

- **Convention: shoals** ([`docs/conventions/shoals.md`](conventions/shoals.md), #11).
  Skills now auto-capture explicit user corrections to a project-local,
  append-only `.claude/shoals/<plugin>.<skill>.md` (committed by default) and read
  them back on the next run.
- **Adopted by:** commitcraft, review-plan, phi-scan, pr-comment-review,
  cc-skill-audit, handoff. **Deliberately skipped:** cc-validate-hooks,
  cc-adoption-audit (one-shot/mechanical — noted in their READMEs).
- **cc-skill-audit:** added checklist item 3.7 (persists user corrections across
  runs) so the pattern is auditable.

## 2026-06-22

- **Convention: finding dispositions** ([`docs/conventions/finding-dispositions.md`](conventions/finding-dispositions.md)).
  Every review/audit skill already decided "fix it / report it / ask me" — but each
  said so in its own words and none had an escalation rule, so behavior was
  unpredictable and an `ask-user` finding could get silently resolved. Unified to
  one `auto-fix`/`report`/`ask-user` model with a single guardrail (never
  self-resolve `ask-user`); severity vocabularies stay per-skill on purpose.

## 2026-06-21

- **phi-scan** — opt-in write-time PHI guard hook. Catching PHI only at commit is
  too late; the guard scans Write/Edit content before it hits disk so leaks are
  stopped at authoring time. Off by default (`PHI_SCAN_GUARD`) so installing the
  plugin never silently blocks edits, and it fails open rather than wedging work.

## 2026-06-19

- **review-plan** — new plugin. The expensive failure mode in plan-driven work is
  building too much; this validates a plan against the real codebase and drives it
  to the *smallest correct* version — simplification pass before risk-hunting, each
  risk reconciled to the cheapest fix, plan revised in place. Optional enhancers
  (review/Codex) degrade gracefully so it never hard-fails.
- **phi-scan** — new plugin. Made the personal PHI skill portable and publishable:
  a deterministic bundled scanner (auditable, not a black box), PHI-first with a
  stack-gated Django/React OWASP add-on, private org markers stripped.

## 2026-06-18

- **handoff** — new plugin. Cross-session context dies when a session ends and gets
  re-litigated; handoff persists goal/state/decisions so a fresh agent continues
  cold. Made installable rather than living in personal config.
- **cc-adoption-audit** — new plugin. Reframed from mining undocumented session
  logs (Windows-broken, stack-biased, prone to false "dead weight" removals) to
  reading config/stack directly and anchoring on the official docs index. Makes no
  "remove unused" claims — recommends what to adopt, never what to tear out.
- **pr-comment-review** — new plugin. Resolves *existing* PR comments (complements
  review *generators*, doesn't duplicate them). Personal dependencies decoupled via
  graceful degradation (GitHub MCP→`gh`, commitcraft→plain push, runner
  detect-or-skip), plus verify-before-accept so false-positive comments are refuted,
  not blindly applied.
- **cc-validate-hooks** — new plugin. Catches broken `.claude/settings.json` hook
  config early. Hardened for publishing: unknown events warn instead of throwing
  stale errors, `--fix` writes a `.bak` first.
- **cc-skill-audit** — new plugin. Audits skills against Anthropic's authoring
  guidance; anchors doc-dependent rules to a runtime `llms.txt` fetch instead of a
  frozen snapshot so it doesn't fail skills on outdated rules. Renamed from the
  personal skill to dodge a public name collision.
- **commitcraft** — setup gained branch protection, persisted issue-tracker config,
  and non-interactive flags so an *agent* can drive setup without a TTY; issue
  linking became tracker-aware (Linear/Jira refs from the branch with no `gh` call).

## 2026-06-17

- **commitcraft** — repackaged as a marketplace plugin distributed via
  `/plugin install`, replacing the standalone installer. Hardcoded `~/.claude` paths
  swapped for `${CLAUDE_PLUGIN_ROOT}` so it's portable across machines.
