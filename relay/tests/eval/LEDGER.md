# Semantic recall scenario ledger

Method: `relay/tests/eval/fixtures/semantic.jsonl` plants 14 synthetic facts
(6 decisions, 4 dead ends, 4 constraints — 2 stated by the user, 2 discovered
by the assistant) as prose inside assistant *text* turns, each carrying two
distinctive content keywords a faithful paraphrase would keep. The baseline
jq fact-pack extractor (`relay/scripts/extract-transcript.sh`) only reads
tool_use/tool_result/user-text turns, so it structurally cannot see assistant
prose — its recall on the 12 assistant-turn facts (decisions + dead ends +
constraint-assistant) should be ~0 by construction. That's the control, not
noise. The 2 user-stated constraints also appear verbatim in user turns, so
the baseline recovers those — that's the calibration check confirming the
scorer itself works.

`relay/tests/eval/semantic-recall.sh` runs both extractors over the fixture,
scores each fact (recovered = both keywords present, case-insensitive) and
prints a PASS/FAIL shipping gate: **PASS iff the Haiku narrative layer
recovers >= 80% of the 12 assistant-turn facts (>= 10/12).**

This is a **manual eval** (calls the live `haiku-narrative.sh`, a real model
call) — not part of CI. Run it by hand before shipping a narrative-layer
change, and record the result as a new row below. Any README or doc claim
about narrative recall must cite a row here.

| Date | Commit | Model | Decisions (A/B) | Dead ends (A/B) | Constraint-user (A/B) | Constraint-assistant (A/B) | Gate | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-07-05 | 54f1bd5+wt | haiku | 0/6 vs 4-6/6 | 0/4 vs 4/4 | 2/2 vs 1-2/2 | 0/2 vs 2/2 | PASS 3/3 | Official series after v2 keywords + verbatim-token prompt: gate 11/12, 12/12, 11/12 (need ≥10). Prompt examples deliberately avoid fixture tokens (no teaching-to-test). Earlier single runs pre-prompt-fix: 10/12 PASS, 8/12 FAIL — variance was the finding; verbatim-token instruction removed it. |
| 2026-07-05 | 54f1bd5+wt | haiku | 0/6 (baseline) | 0/4 | 2/2 | 0/2 | n/a | Baseline (fact pack only) row for comparison: 2/14 overall — assistant-turn facts structurally invisible to jq extractor, as designed. |

- A = baseline (`extract-transcript.sh`), B = narrative (`haiku-narrative.sh`).
- "Model" is the model `haiku-narrative.sh` invoked (e.g. `claude-haiku-4-5`).
- "Gate" is PASS / FAIL / SKIPPED (narrative unavailable that run).

## Methodology v2 — token keywords, not phrases

First cut used multiword prose phrases as keywords (e.g. `"NAT gateways"`,
`"goroutine per client"`, `"YAML file parsed"`, `"starve the shared connection
pool"`). Every faithful paraphrase breaks a phrase like that — a narrative
that says "IP addresses collide behind NAT" instead of "…behind corporate NAT
gateways" is not a recall failure, it's the keyword being too brittle to
survive rewording. That inflated the miss count and made the gate measure
prose-matching luck, not semantic recall.

**Token rule**: each fact's 2 keywords are now the shortest distinctive
technical tokens taken verbatim from the fact's planted sentence in the
fixture — header/algorithm names, numbers, and single tech nouns (`"token
bucket"`, `"429"`, `"YAML"`, `"NAT"`, `"2x"`) rather than the surrounding
prose. `semantic-recall.sh`'s `present()` now matches case-insensitive
whole-word/whole-phrase (`grep -qiFw`), so a short token like `"NAT"` can't
false-hit inside an unrelated word, and inflection isn't papered over: a
keyword only matches its own exact form (`"skews"` won't match a paraphrase's
"skew"). That's an accepted, honest limitation of the token — not something
to special-case.

**No-output-peeking guard**: keywords were re-chosen by reading only
`fixtures/semantic.jsonl` — the planted sentences — never by looking at any
`haiku-narrative.sh` output. Choosing a keyword because it happened to appear
in a specific narrative run would bias the gate toward whatever wording that
run used; the token must be justifiable from the fixture alone.

One deviation from the keyword set proposed when this revision was
requested: `ca2` uses `"skews"` (the exact word in the fixture: "the CI
sandbox's clock skews by up to 2 seconds") instead of the suggested `"clock
skew"` — under word-boundary matching `"clock skew"` scores zero against the
fixture itself (`"skews"` doesn't satisfy a trailing word boundary after
`"skew"`), which would fail the "keyword appears exactly once in the
fixture" check before any narrative is even run. `"skews"` is the shortest
token that both stays in the fixture's own wording and is unique.
