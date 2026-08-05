# Skill Audit Report

**fallback run — scores are self-reported by cheap scorers without independent
verification; treat as an upper bound.**

Run 2026-08-05. Scope: project skills only (`<repo>/*/skills/*/SKILL.md`), 21 skills
across 5 haiku batches. The primary Workflow path (Haiku scorers → Sonnet
fact-checkers → ranking agent) was unavailable in this run's forked context; this
used the documented Task-fan-out fallback. A parent fact-check pass (below) spot-
verified a sample of claims against disk — it is not exhaustive per-skill Sonnet
verification, so individual scores are still self-reported.

## Summary

| Skill | Blockers | High | Medium | Verdict |
|---|---|---|---|---|
| review-plan | — | — | — | Ready |
| autodev | — | — | — | Ready |
| cc-adoption-audit | — | 1 | — | Fix |
| commitcraft | — | — | — | Ready |
| github-issue-auditor | — | — | — | Ready |
| react-component-architecture | — | — | — | Ready |
| tailwind-design-token-validator | — | — | — | Ready |
| rbac-audit-django | — | — | — | Ready |
| rbac-threat-model | — | — | 1 | Fix |
| rbac-remediation-playbooks | — | — | — | Ready |
| new-plugin | — | — | — | Ready |
| wireframe | — | — | — | Ready |
| cc-skill-audit | — | — | 1 | Fix (see also: sweep-mode defect below, not caught by this checklist) |
| phi-scan | — | — | — | Ready |
| sentry-hygiene | — | — | — | Ready |
| dep-review | — | — | 1 | Fix |
| handoff | — | — | 1 | Fix |
| pr-review-deep | — | — | 1 | Fix |
| pr-comment-review | — | — | — | Ready |
| cc-validate-hooks | — | — | — | Ready |
| action-first | — | 1 | — | Fix |

16 of 21 clean. 2 High, 5 Medium across the remaining 5.

## High-severity findings

**cc-adoption-audit** (`cc-adoption-audit/skills/cc-adoption-audit/SKILL.md`)
Description's "when" clause is process language, not intent language — verified
on disk: `"User-invoked — run /cc-adoption-audit; the agent will not auto-fire
it."` A user asking "what Claude Code features am I missing?" won't match.
Fix: add use-case phrasing, e.g. `"Use when you want to discover underused
features and optimize your configuration."`

**action-first** (`action-first/skills/action-first/SKILL.md`)
Description's when-clause, verified on disk: `"Invoke with /action-first;
persists until 'stop action-first' or 'normal mode'."` — no use-case trigger
phrases at all; only fires on the literal slash command. Fix: add phrasing like
"Use when you want action-focused, no-preamble responses" so it surfaces on
natural-language asks, not just direct invocation.

## Medium-severity findings

**rbac-threat-model** (`rbac-django/skills/rbac-threat-model/SKILL.md`)
Confirmed on disk: no `disable-model-invocation` field, unlike its sibling
`rbac-remediation-playbooks` (which has it with an explicit "user-invoked only"
comment). Ambiguous whether threat-model should auto-suggest after an audit
completes or stay user-invoked. Resolve the intent, then set the field to match.

**cc-skill-audit** (`cc-skill-audit/skills/cc-skill-audit/SKILL.md`)
`references/audit-checklist.md` (confirmed 14 KB) has structured `##` headers but
no table-of-contents block. Cosmetic, non-blocking.

**dep-review** (`dep-review/skills/dep-review/SKILL.md`)
`references/decision-matrix.md` (178 lines) and `analysis-steps.md` (137 lines)
are long enough that a TOC would help navigation. Not verified against disk in
this pass (batch B flagged it as "should check"); treat as unconfirmed until
looked at directly.

**handoff** (`relay/skills/handoff/SKILL.md`)
Confirmed on disk (line 110-113): recover mode is documented as a pointer to
`workflows/recover.md` but the preamble doesn't say whether recover reuses steps
1-7 or is fully separate. Minor ambiguity, not a defect.

**pr-review-deep** (`pr-review-deep/skills/pr-review-deep/SKILL.md`)
Non-scope statement ("does not run tests, security tooling, or coverage checks")
sits mid-body rather than in a dedicated preamble. UX polish only.

## Cross-cutting notes

- **No duplicate-name collisions** found in this scan (project-skills scope only;
  a plugin-cache scope would additionally need to check for the known
  `cc-skill-audit` self-collision documented in its own SKILL.md gotchas).
- **No security/portability findings** — no hardcoded user paths, no credentials,
  `${CLAUDE_PLUGIN_ROOT}` used correctly everywhere it was checked.
- **Batch C's "3 of 4 clean" and Batch E's "2 of 3 clean" are plausible, not a
  calibration smell** — spot-checks against disk (below) confirmed the specific
  claims made, and the findings that were raised (action-first, cc-skill-audit
  TOC) hold up under inspection. Still, no exhaustive Sonnet-verify pass ran, so
  treat every unflagged skill as "no obvious problem found," not "certified clean."

## Fact-check pass (this run's parent, replacing the missing Sonnet-verify phase)

Spot-verified 5 claims directly against disk:

| Claim | Result |
|---|---|
| action-first description text (batch E) | Confirmed verbatim |
| cc-adoption-audit description text (batch A) | Confirmed verbatim |
| rbac-threat-model missing `disable-model-invocation` (batch B) | Confirmed absent |
| cc-skill-audit's audit-checklist.md has no TOC (batch C) | Confirmed |
| handoff recover.md wording (batch D) | Confirmed |

All 5 held up. This is a sample, not exhaustive — unverified per-skill claims
(e.g. dep-review's reference line lengths) are marked above where relevant.

## This run's own defect

Sweep mode itself didn't complete — all 5 batches finished but the parent forked
subagent ended its turn before collecting them, orphaning ~52k chars of finished
report for 2+ hours until manually recovered. See the companion fix to
`cc-skill-audit/skills/cc-skill-audit/SKILL.md` (spawn without `name:`, block on
children with `TaskOutput`). That defect is not one this checklist itself checks
for — it's a fork/orchestration bug, not a SKILL.md authoring problem — noted here
because it's why this report exists as a manual recovery rather than a normal run.
