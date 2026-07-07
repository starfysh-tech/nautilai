# Convention: finding dispositions

> Status: active · Applies to: every review/audit/validation skill in nautilai

A *finding* is anything a skill surfaces about the user's code, config, or plan —
a bug, a gap, a risk, a recommendation, a review comment. **Severity** says how
bad it is. **Disposition** says what the skill is *allowed to do about it*. The
two are orthogonal, and this convention standardizes the second axis so every
nautilai skill behaves predictably.

Severity vocabularies stay deliberately per-skill (PHI confidence, Blocker/High/
Medium, P1/P2/P3, CRITICAL/CAUTION) — those are domain-fit and we do **not**
flatten them. This convention governs disposition only.

## The three dispositions

Every finding resolves to exactly one of:

| Disposition | Meaning | Skill may… |
|---|---|---|
| **auto-fix** | Safe, mechanical, intent-preserving change | apply it in place, then report what changed |
| **report** | Informational; no change implied | surface it and stop |
| **ask-user** | Needs human judgment | **only** surface it and wait |

## The one hard rule

> **Never approve, fix, or skip an `ask-user` finding on your own. Surface it and wait.**

This is the guardrail the convention exists for. A skill may batch `ask-user`
findings behind a single approval gate (e.g. `AskUserQuestion`), but it must not
decide them silently — not even to "skip as trivial."

## The auto-fix safety contract

A skill that applies an `auto-fix` MUST:

1. Leave the change recoverable — a `.bak`/backup, a diff, or a VCS-visible edit.
2. Report exactly what it changed (file + what/why), not just "fixed".
3. Never widen scope under the auto-fix banner — if the "fix" requires a judgment
   call, it is `ask-user`, not `auto-fix`.

## Deciding the disposition

- Mechanical + reversible + intent-preserving → **auto-fix**
- Nothing to change, or remediation is the user's to perform → **report**
- Any judgment about intent, trade-offs, or correctness → **ask-user**

When in doubt between `auto-fix` and `ask-user`, choose `ask-user`. Under-acting
is recoverable; a wrong silent edit is not.

## How each skill maps today

| Skill | auto-fix | report | ask-user |
|---|---|---|---|
| **cc-validate-hooks** | `--fix`: add missing `type`, drop unused matcher (writes `.bak`) | passing checks; warnings (unknown event/type) | malformed config that `--fix` won't touch |
| **cc-skill-audit** | mechanical SKILL.md fixes (YAML, missing field) | clean skills; the findings list | description rewrites, monolith splits |
| **review-plan** | revise the plan file in place to the leaner correct version | verdict, footprint, dropped speculative risks | conflicting/ambiguous plan decisions |
| **pr-comment-review** | trivially mechanical review comments (still shown in the task list) | refuted false positives (reply with evidence) | every substantive comment — behind the Phase 3 gate |
| **phi-scan** | *none* (never auto-remediates PHI) | scanner candidates; triage results; OWASP grep hits | confirmed PHI exposure — remediation is the user's call |
| **cc-adoption-audit** | *none* | the full prioritized audit | acting on a recommendation ("set up X?") |
| **pr-review-deep** | *none* (propose-only; never edits code) | every review finding, with cited `file:line` | acting on a proposed restructuring ("apply this?") |
| **github-issue-auditor** | *none by default* (Phase 4 applies only user-approved batches) | the full audit report | every mutation — behind the Phase 4 gate |

**Noted exception:** autodev's `review-gate` agent is a pipeline-internal gate, not
a user-facing review — it returns `pass`/`block` with blocking/advisory findings.
`block` maps to `ask-user` (the orchestrator decides), `advisory` maps to `report`,
and there is no `auto-fix` (the reviewer is read-only). See `autodev/README.md`.

## Why this came from `no-mistakes`

The `kunchenguid/no-mistakes` pipeline classifies every finding as
`auto-fix` / `no-op` / `ask-user` and forbids the agent from resolving an
`ask-user` item itself. nautilai already did all three informally with
inconsistent wording; this convention adopts the one genuinely missing guardrail
(the explicit "don't self-resolve `ask-user`" rule) and a single shared
vocabulary. We renamed `no-op` → `report` because most nautilai skills are
advisory, and "report" reads truer than "no-op" for them.
