# Skill-eval backlog

Hand-curated list of skill evals **not yet built**. Tier 1 (offline,
deterministic core) is done for `phi-scan` and `cc-validate-hooks`; everything
below is the remaining work.

## What a "skill eval" is here

Same shape as `relay/tests/eval/` (see it for the reference implementation):

- **fixtures/** — input files the skill runs against (a repo tree, a transcript, a settings file, a PR).
- **a gold manifest** — a `.tsv`/`.jsonl` of expected labels, produced from **observed** behavior of the real core, never guessed.
- **a grader `.sh`** — diffs observed-vs-expected per fixture and fails when they diverge (never passes vacuously).
- **LEDGER.md** — results + provenance + honestly-recorded known limitations.

**The key split:**

- **Offline / deterministic evals are cheap.** A pure scanner (regex/AST/JSON
  parse) produces the same output every run, so its gold labels are just
  "what the scanner actually printed on this fixture." No model, no network, CI-safe.
  This is what `phi-scan/tests/eval/` and `cc-validate-hooks/tests/eval/` are.
- **Model-driven ("live") evals are expensive and non-deterministic.** Any eval
  that grades what a *model* produced (a narrative, a triage verdict, a review
  report, a commit message) varies run-to-run and burns API calls, so it can't
  live in CI as a hard gate. Relay already set this precedent: the recall gate
  and injection checks are **manual** live evals recorded in
  [`relay/tests/eval/LEDGER.md`](../relay/tests/eval/LEDGER.md), and the
  operational live-validation runs in
  [`relay/tests/eval/LIVE-LEDGER.md`](../relay/tests/eval/LIVE-LEDGER.md) — run
  by hand before shipping, each run appended as a dated row with model + commit,
  never gating a PR.

Everything below is either live (Tier 2/3, commitcraft) or a
deterministic-scanner-core slice that hasn't been carved out yet.

---

## Tier 2 — judgment/review skills (live, golden-fixture recall/precision)

These skills run a scan/inspection and then apply **model judgment** to
rank, filter, or verdict. The eval shape is a fixture repo/PR/tracker with
**seeded** defects plus a gold manifest, graded on two axes:

- **recall** — the report catches every planted finding;
- **precision** — it does not invent findings that weren't seeded.

All of these are **live / model-driven and higher-maintenance**: gold labels are
recall/precision targets (e.g. "≥ N/M planted, ≤ K false), scored as a manual
ledger row, not a CI gate. Emit the `(hard, soft)` shape (see bottom) so the
recall gate is the hard 1/0 and the fraction caught is the soft score.

Several of these ship a **deterministic scanner** underneath the judgment layer
(`frontend-review`, `github-issue-auditor`, `rbac-django`). That scanner layer
*could* get a cheap Tier-1 offline eval on its own (seed a fixture, assert the
scanner's raw JSON) independent of the live judgment eval — worth splitting when
built, since it's the CI-safe half.

- **cc-adoption-audit** — audits a Claude Code setup against available features
  and surfaces unused-but-should-use gaps. Fixture: a synthetic `.claude/`
  config tree with known-missing features (no hooks, no MCP, stale settings);
  assert the audit names each planted gap and doesn't hallucinate features
  already present. No bundled scanner — fully model-driven.
- **cc-skill-audit** — scores existing `SKILL.md`s against Anthropic authoring
  guidance (trigger reliability, bloat, portability, security). Fixture: a set
  of SKILL.md files with seeded defects (over-broad description, missing
  frontmatter, oversized body, injection risk); assert the worst-to-best ranking
  and per-skill findings match the seeds. Ships `scripts/` — the structural
  checks (frontmatter present, size) are deterministic and splittable.
- **dep-review** — assigns AUTO-MERGE/MERGE/SKIP/INVESTIGATE verdicts to
  Dependabot PRs from diff + changelog + codebase usage. Fixture: a set of
  canned PR payloads (patch bump, major bump, dev-dep, one with a known CVE);
  assert the verdict per PR. Live: the verdict is a judgment call; needs
  `gh`/PR data stubbed the way commitcraft stubs `gh`.
- **frontend-review / react-component-architecture** — flags oversized
  components, prop drilling, duplicated UI, loose-string variant props. Ships
  Python scanners (`component_analyzer.py`, `prop_drilling_detector.py`, …).
  Fixture: a small React/TS tree with each anti-pattern planted at a known
  file:line; assert every finding is cited. Scanner layer is deterministic
  (Tier-1-able); the "should extract to a primitive" judgment is live.
- **frontend-review / tailwind-design-token-validator** — flags arbitrary
  values (`bg-[#3b82f6]`), class-concatenation that breaks purging, `@apply`
  overuse, inline styles, missing a11y attrs. Ships `validate_class_usage.py`
  etc. Fixture: TSX files with each violation planted; assert file:line hits.
  This one is **mostly deterministic** — a strong Tier-1 candidate; the
  suggest-tokens step is the only live part.
- **github-issue-auditor** — finds fuzzy-duplicate titles, orphaned sub-issues,
  unlabeled/stale items, taxonomy-inconsistent labels. Ships
  `analyzer.py`/`discovery.py`. Fixture: a canned issue-list JSON with planted
  duplicates/orphans; assert the analysis catches each. Fuzzy-match layer is
  deterministic; the cleanup recommendation is live. Needs GitHub API responses
  stubbed.
- **pr-comment-review** — fetches review threads, categorizes them, implements
  agreed fixes behind approval gates. Fixture: a canned set of review-comment
  threads with known categories (nit vs blocking vs question); assert the
  categorization. Live and stateful (it edits code + replies) — hardest to
  fixture; the gradeable slice is the categorization, not the code edits.
- **pr-review-deep** — evidence-based quality review (abstraction design,
  type/boundary contracts, behavior-preserving simplifications). Fixture: a diff
  with seeded quality defects (leaky abstraction, unsafe cast, dead branch);
  assert recall of the planted issues + precision (no invented ones). Fully
  model-driven; the eval *is* recall/precision on planted defects.
- **rbac-django / rbac-audit-django** — scans Django/DRF+React for missing
  permission classes, unfiltered querysets, IDOR, serializer leaks, role
  coupling. Ships `rbac_scanner.py` (deterministic). Fixture: a minimal
  Django/DRF app with each gap planted at a known view/serializer; assert
  scanner hits + severity ranking. **Best Tier-1 split candidate** — the scanner
  is deterministic; only the severity/judgment layer is live.
- **rbac-django / rbac-threat-model** — turns audit findings into abuse cases.
  Fixture: a fixed audit-findings JSON; assert each finding yields the expected
  abuse-case class. Purely model-driven (consumes upstream output).
- **rbac-django / rbac-remediation-playbooks** — turns findings (+ abuse cases)
  into prioritized fix playbooks and paste-ready issues. Fixture: same fixed
  findings JSON; assert the playbook covers each finding and prioritizes by the
  seeded severity. Model-driven; grade structural coverage, not prose quality.
- **review-plan** — validates an implementation plan against the codebase and
  drives it to the leanest version (reuse/delete/don't-build). Fixture: a plan
  doc + a repo where some plan steps are already-implemented or reducible;
  assert it flags the reuse/delete opportunities and the breaking-change risks.
  Fully model-driven; recall on planted "you don't need to build this" cases.
- **wireframe** — see Tier 3; only its structural output is gradeable.

---

## Tier 3 — generative / subjective (low ROI)

For skills whose output is a **generated artifact** (a wireframe, a designed
component), only **structural** properties are honestly checkable:
`section_present`, `contains(<selector>)`, "the ASCII layout has a header and a
nav region," "the Mermaid diagram parses and has N states." You **cannot** grade
"is this a good design" deterministically — any such gate is theater.

- **wireframe** — gradeable: the emitted wiremd/Mermaid parses, and requested
  regions/states are present. Not gradeable: whether the layout is *good*.
- **frontend-review design-quality judgments** (the "extract to a primitive,"
  "this variant API is loose" recommendations, as opposed to the deterministic
  scanner hits) — subjective; only the scanner-backed findings are gradeable.

**State this honestly: Tier 3 is low ROI.** A structural-presence grader adds
little confidence over just running the skill, and the interesting property
(design quality) is exactly the ungradeable part. Build these only if a
structural regression (skill stops emitting a required section) is a real risk.

---

## commitcraft (live)

commitcraft's **deterministic scripts already have tests** — run them directly,
they're offline and stub `gh`:

- `commitcraft/tests/detect-rp.test.sh` — release-please detection.
- `commitcraft/tests/pr-template.test.sh` — PR-template selection.

So commitcraft is **not** a Tier-1 gap. The uncovered surface is the
**commit-MESSAGE prose** the model generates — is the conventional-commit
type/scope correct, is the subject imperative and ≤72 chars, does the body
explain the *why*. That's model-driven and non-deterministic, so it belongs
**here as a live eval**, not in Tier 1: a fixture of staged diffs with a gold
label for the expected type/scope (+ format assertions on the generated
message), scored as a manual ledger row like relay's recall gate. The
format-only checks (length, no emoji, no attribution footer) are deterministic
and could be a cheap sub-check even against a recorded model output.

---

## Grader contract — emit the `(hard, soft)` shape

Every eval here, when built, must emit the same two-part result so a future
optimizer (SkillOpt-style) is near-zero-glue:

- a **hard gate** — all-must-pass → `1`/`0`, exit nonzero when below threshold;
- a **soft fraction** — `passed/total` (e.g. recall = caught/planted), so
  partial progress is measurable and rankable.

Keep it relay/`phi-scan`-compatible (per-fixture PASS/FAIL lines, then the
aggregate). This is what makes an eval reusable as an optimization objective
rather than a one-off check.
