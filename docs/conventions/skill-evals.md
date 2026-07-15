# Skill evals — gradeable regression nets

A skill eval pins a skill's behavior to a **measured** signal so a later edit
can't silently break it. It is the same instinct as the repo's other
conventions — validate assumptions, don't assume behavior you can inspect —
applied to the skill itself.

An eval is three parts plus a ledger:

- **Fixtures** — input files the skill (or its deterministic core) runs against.
- **A gold manifest** — the expected result per fixture, *derived by running the
  real code*, never guessed.
- **A grader** — a bash script that runs the code over the fixtures, diffs
  observed against gold, and exits nonzero when they diverge.
- **A `LEDGER.md`** — what's tested, the last run's output, and any known
  limitations the eval surfaced.

Mirror the layout of [`relay/tests/eval/`](../../relay/tests/eval/) — it is the
reference implementation.

## Offline vs. live — which kind a skill can have

The gradeable surface decides the eval's cost and where it can run.

- **Deterministic core → offline eval.** A skill whose load-bearing logic is a
  script (`phi-scan`'s `phi_check.py`, `cc-validate-hooks`'s
  `validate-hooks-core.py`) is graded by running that script over fixtures. No
  model, no network — it runs in CI on every PR.
- **Model-driven behavior → live eval.** A skill whose behavior is prose the
  model executes has nothing a static grader can run; it needs the model in the
  loop. That is a *live* eval (relay's
  [`live-validate.sh`](../../relay/tests/eval/live-validate.sh) →
  [`LIVE-LEDGER.md`](../../relay/tests/eval/LIVE-LEDGER.md)) — real calls,
  non-deterministic, run deliberately rather than on every PR. Expect run-to-run
  variance and gate on a threshold across repeated runs, never exact match.

A skill's bundled-script *tests* (`commitcraft/tests/*.test.sh`) are not skill
evals — they test the script, not what the model does with the skill. When the
only checkable surface is the script, that script test *is* the coverage; the
skill's model-driven part still needs a live eval.

## The grader contract — emit `(hard, soft)`

Every grader prints two aggregates and sets its exit code from the hard gate:

- **`hard`** — the all-must-pass gate: `1` if every fixture matches gold, else
  `0`. Exit nonzero when `hard` is `0` (or below threshold).
- **`soft`** — the pass fraction (`passed / total`), for visibility into a
  partial regression.

Keep this shape even though nothing consumes it yet: it is exactly the signal an
optimizer would need, so it keeps that door open at zero cost. It is also just a
better failure message than a bare exit code.

## Gold-from-observed discipline

The failure mode of an eval is a wrong gold label — it is worse than no eval,
because it asserts the wrong thing with a green check. So:

- **Derive gold by running the real code**, not by reasoning about what it
  *should* do. Record what it actually reports.
- **Where the code is wrong or surprising, do not encode it as correct and do
  not hide it** — record it as a known-limitation line in the `LEDGER.md`. An
  eval that documents a real defect has earned its keep (the `cc-validate-hooks`
  eval surfaced that the core crashes on invalid JSON, guarded only by its
  wrapper).
- **Prove the grader can fail.** Temporarily break one fixture's expectation,
  confirm the grader reports `FAIL` and exits nonzero, then restore it. A grader
  that can't fail protects nothing. Note the check in the ledger.
- **Only synthetic data in fixtures.** Never realistic PII/secrets — `phi-scan`'s
  fixtures use `@example.com`, `555-01xx`, RFC-5737 IPs.

## What an offline eval does and doesn't tell you

Because gold is derived from observed output, an offline eval is a **regression
detector, not a completeness proof.** `phi-scan`'s recall gate reads 100% by
construction — it will catch an edit that *breaks* a detection path, but it can
never tell you the scanner is *missing* a class it never detected. State this in
the ledger so the number isn't mistaken for a coverage claim.

## Wire it in, or it protects nothing

An eval that no CI step runs is inert. Add the grader to the `validate` workflow
([`.github/workflows/validate.yml`](../../.github/workflows/validate.yml))
alongside the other suites (`relay`, `autodev`, `commitcraft`) so a PR that
breaks a core fails the required check. Until it's wired, the eval is a
manual-run script, not a gate.

## Coverage and the backlog

Not every skill can bear an eval yet, and the judgment skills that most need one
are the most expensive to grade (they need seeded-defect fixtures and a
recall/precision grader run live). The standing list of what's built and what's
pending is [`docs/skill-eval-backlog.md`](../skill-eval-backlog.md).

## Exemplified by

- **`relay`** — offline semantic-recall (`semantic-recall.sh` + `facts.tsv`) plus
  a deterministic injection veto (`injection-check.sh`), and a separate live eval.
- **`phi-scan`** — offline recall/precision over the deterministic scanner;
  recall hard-gated, precision informational (AI-triage owns precision).
- **`cc-validate-hooks`** — offline verdict-match over the validator core, one
  fixture per branch.
