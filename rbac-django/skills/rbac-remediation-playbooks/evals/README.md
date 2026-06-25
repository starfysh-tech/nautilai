# rbac-remediation-playbooks evals

Eval **definitions** for this skill, preserved when it was ported into nautilai
(from the original skill-creator workspace). Run outputs/grading/timing were
dropped — they regenerate.

- `cases/<eval>.json` — per-case assertions (structural + quality checks). The
  upstream workspace had no top-level `evals.json`; each case file carries its
  own prompt + assertions.
- `benchmark.json` — the last recorded baseline (pass rate / time / tokens,
  with-skill vs without-skill).

Use them to re-validate the skill after edits.
