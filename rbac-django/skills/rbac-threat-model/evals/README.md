# rbac-threat-model evals

Eval **definitions** for this skill, preserved when it was ported into nautilai
(from the original skill-creator workspace). Run outputs/grading/timing were
dropped — they regenerate.

- `evals.json` — the suite: prompt + `expected_output` per case.
- `cases/<eval>.json` — per-case assertions (structural + quality checks).
- `benchmark.json` — the last recorded baseline (pass rate / time / tokens,
  with-skill vs without-skill).

Scenarios are generic (HIPAA clinical-trials, multi-tenant SaaS, findings-only) —
no project-specific data. Use them to re-validate the skill after edits.
