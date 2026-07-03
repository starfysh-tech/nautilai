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

## 2026-07-03

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
