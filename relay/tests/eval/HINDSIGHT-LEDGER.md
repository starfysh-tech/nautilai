# Hindsight eval ledger

Scores relay's extractors on **real** transcripts against what each session
went on to use. `hindsight.sh split` cuts a transcript at line K; "needed"
tokens are distinctive tokens (paths, flags, identifiers, numbers with units,
issue refs) present both before and after K, excluding compaction summaries,
`isMeta` turns, and `<system-reminder>` blocks. `hindsight.sh score` reports
the share of needed tokens an output contains (`recall`), the share of the 50
most-used needed tokens (`top50`), tokens absent from the prefix
(`invented`), and output bytes. Manual and live (real Haiku calls); only
aggregates are recorded here, never content.

Cut set: 21 compaction cuts (cut at a real `compact_boundary`, prefix and
suffix each ≥200 lines), 10 synthetic cuts (50% of a >1MB, ≥600-line
transcript), 8 multi-chunk cuts (prefix dialogue >150KB; 5 at a real
boundary, 3 at 85%). One machine, one operator's sessions.

## Run — 2026-10-16 · main 725adc1 · model haiku

### V1: run narrative chunks in parallel

V1 changes only `haiku-narrative.sh`'s chunk loop: chunks a/b/c run as
background subshells and `wait` collects their status, instead of a→b→c in
series with short-circuit. Single-chunk runs are unchanged by construction.

Multi-chunk cuts, 2 serial V0/V1 pairs per cut (order alternated), no other
load:

| Variant | Runs | Mean secs | Mean recall | Mean top50 | Mean bytes | Degrades |
| --- | --- | --- | --- | --- | --- | --- |
| V0 (serial) | 16 | 151 | 0.154 | 0.260 | 22,337 | 0 |
| V1 (parallel) | 16 | 60 | 0.149 | 0.248 | 21,901 | 0 |

Per-cut speedup 2.2×–2.8×. The recall difference is inside V0's own
run-to-run spread (e.g. m01 V0 0.149 vs 0.195).

### V0 variance baseline (single-chunk cuts)

31 cuts × 3 runs = 93 runs, 0 degrades, mean 41s. Narrative alone: recall
0.093, top50 0.152. Per-cut min–max spread is mostly ≤0.05 (widest c04
0.143–0.242).

### Baselines

| Output | Cuts | Mean recall | Mean top50 | Mean bytes |
| --- | --- | --- | --- | --- |
| Fact pack alone | 39 | 0.113 | 0.140 | — |
| Fact pack + narrative (run 1) | 21 compaction | 0.165 | 0.232 | 17,204 |
| Built-in compaction summary | 21 compaction | 0.226 | 0.414 | 31,429 |

Do not read the summary row as a head-to-head. On a compaction cut, the agent
wrote the suffix while working from that summary, so tokens the summary kept
were easier to reuse. The answer key leans toward the summary by
construction.

### Lost-by-compaction tokens

This is the comparison that fits relay's job. For each of the 26 real
compaction cuts (21 + m01/m02/m03/m06/m08), the lost set is needed tokens
minus the summary's tokens. These are tokens the session used again after
compaction even though the summary had dropped them.

| Measure | Mean over 26 cuts |
| --- | --- |
| Lost share (lost / needed) | 0.80 |
| Fact pack recall on lost | 0.089 |
| Narrative recall on lost (all V0 runs) | 0.043 |
| Fact pack + narrative (run 1) recall on lost | 0.123 |

The summary scores 0 on this set by definition. The 10 synthetic cuts have
no summary, so they have no lost set.

### Where lost tokens live (upper bound per variant)

Each of the 5,377 lost tokens is assigned to the first prefix region that holds it.
No model calls. A variant cannot recover a token its input never shows.

| Region | Share | Variant that reaches it |
| --- | --- | --- |
| First 2000 chars of user/assistant text | 13% | V0 (today's narrative input) |
| Text past char 2000 of a turn | 2% | V2 head+tail |
| `tool_use` inputs | 39% | V3 tool-call lines |
| `tool_result` content only | 41% | Jev-style result selection |
| None of the above | 5% | flatten gaps |

V2's ceiling is +2%, so V2 was not run.

### Jev as a tool-result selector

This test asks whether Jev can pick the tool results a handoff should
carry. For each cut, up to 150 tool results were sampled outside the first
message and the last 6, with a fixed seed. Each one went to `jev-latest` with
fast-jev-compaction's own "full output should stay verbatim" `noul` question.
The state followed that plugin's shape: the whole history, results replaced
by notes, fitted to about 25k tokens.

The client is a stdlib reimplementation, so the plugin's own code never ran.
Its fitting stages are simpler than the plugin's. A result counts as
"reused" if its tokens show up in the needed set.

| Measure | Value |
| --- | --- |
| Results scored | 5,002 across 39 cuts |
| Reused share | 0.52 |
| Jev probability, p50 / p99 / max | 0.13 / 0.24 / 0.39 |
| Kept at the default 0.5 threshold | 0 |
| AUC (reused vs not) | 0.649 overall, 0.561 mean within result-size deciles |
| Precision at a 6% keep rate: Jev top-p | 0.58 |
| Same, "last Read of this path" rule | 0.75 |

**This run does not measure Jev as TypeSafe intends it to be used.** Like
fast-jev-compaction, it broke three rules in TypeSafe's Noul guidance:

- The state held no evidence: each result was replaced by a size note.
- The question combined two conditions.
- The question named no path to the evidence and had no `criteria`.

The docs say a Noul at or below 0.5 can mean the state lacks the evidence,
which matches the p99 of 0.24. So these numbers rate that plugin's request
design, not Jev.

### Jev rerun per TypeSafe guidance (V4b)

This rerun follows TypeSafe's Noul guidance:
- Each result's text goes in state, abridged to the first 1,500 and last 300 characters.
- The state also carries the task goal (the last 3 user prompts) and the last 12 messages.
- Each question has one condition: "Does `results[i].text` contain specific facts … that the work described in `goal` will need again?" It has true/false criteria.
- Batches of 8 results, at most 4 requests in flight.

The sample is 40 results per cut, a subset of the first run's sample, for 1,524 results in total.

| Measure | First run (same 1,524 calls) | V4b |
| --- | --- | --- |
| Probability p10 / p50 / p90 / max | — | 0.17 / 0.41 / 0.68 / 0.90 |
| AUC (reused vs not) | 0.662 | 0.628 |
| AUC, mean within result-size quintiles | — | 0.565 |
| Precision at p ≥ 0.5 (keeps 34%) | — | 0.62 (base rate 0.49) |
| Precision at p ≥ 0.7 (keeps 9%) | — | 0.71 |
| Precision on lost tokens at p ≥ 0.5 | — | 0.29 (base rate 0.26) |

At the same 34% keep rate, ranking by result size gives precision 0.80. On
these calls, the last-Read rule gives 0.82 (n=92).

With the evidence in state, Jev's probabilities spread out, but its ranking
did not improve. Within a size band it is close to chance, and two
zero-cost rules beat it. Not adopted.

Limits: the label is token reuse, not semantic need. The goal is built from
the prefix, as it would be at handoff time.

### V3: tool-call lines in the narrative dialogue

V3 adds one `TOOL: <name> <main argument>` line per tool call. The main
argument is the first of file_path, command, pattern, url, query, and
description, capped at 200 characters. V3 also adds one `TOOL ERROR:` line
per failed result (first 300 characters), and a prompt sentence that tells
Haiku to use these lines as evidence. Successful tool output stays out.

| Measure (31 cuts × 3 runs) | V0 | V3 |
| --- | --- | --- |
| Mean recall | 0.093 | 0.116 |
| Mean top50 | 0.152 | 0.181 |
| Mean output bytes | 6,355 | 8,065 |
| Mean secs | 42 | 46 |
| Runs that crossed 150KB into 3 chunks | 0 | 12 |
| Degrades | 0 | 0 |
| Lost-token recall (26 compaction cuts) | 0.040 | 0.052 |

On the 27 cuts that stayed single-chunk under V3, which is the size-fair
comparison, recall rose by +0.013 on average: 11 cuts better and 1 worse
(threshold ±0.01), at +250 bytes. By hand: V3 dead ends quote exact commands
and error strings more often, and on some cuts they drop a prose-only
decision nuance that V0 kept.

### Reader probe: V0 vs V3 at the doc level

This measures the doc, not the packs. For each cut, Sonnet:
- writes 10–14 questions about pre-cut context that the suffix used, each one
  with a prefix locator and suffix evidence; it keeps a question only when the
  locators straddle the cut;
- writes a handoff doc per SKILL.md from each variant's fact pack and narrative
  pack, with no repo access;
- answers each question from one doc;
- grades every answer blind against the reference (correct 1, partial 0.5,
  missing or wrong 0).

37 of 39 cuts, 422 questions. s03 failed to parse and m01 kept 1 question.

| Doc from | Cuts | Correct | Wrong | Missing | Mean bytes |
| --- | --- | --- | --- | --- | --- |
| V0 packs | 37 | 0.654 | 0.006 | 0.179 | 14,324 |
| V3 packs | 37 | 0.697 | 0.008 | 0.146 | 14,703 |
| Fact pack only | 37 | 0.100 | 0.004 | 0.842 | 12,691 |
| Compaction summary only | 25 | 0.629 | 0.007 | 0.206 | 28,690 |

Paired V3 − V0 per cut, with a 95% bootstrap CI:

| Cut set | n | Mean | CI | Sign +/−/= |
| --- | --- | --- | --- | --- |
| All | 37 | +0.042 | +0.016, +0.071 | 22/11/4 |
| Single-chunk | 30 | +0.031 | +0.002, +0.064 | 15/11/4 |
| Compaction | 21 | +0.051 | +0.013, +0.093 | 12/6/3 |
| Synthetic | 9 | −0.016 | −0.052, +0.013 | 3/5/1 |
| Multi-chunk (V0 ×2 vs V3 ×1) | 7 | +0.092 | +0.057, +0.130 | 7/0/0 |

By question type on single-chunk cuts, `state` gains (+0.055, CI +0.007,
+0.106). `decision` dips without significance (−0.014, CI −0.056, +0.031),
which matches the hand-check note above. Run-to-run spread within a variant
is about 0.10–0.12, so a single run decides nothing.

V3 passes the gate: the CI excludes 0 on all cuts and on single-chunk cuts.
The single-chunk gain is small.

167 of the 201 V0/V3 docs are over 10,000 characters. The probe gives the
reader the full doc. A real SessionStart injection above 10,000 characters
shows the model a 2KB preview and a file path, so these scores overstate
what a real pickup sees.

### V1 ported to `relay/scripts/haiku-narrative.sh`

Live run of the repo script on m08: 47s, recall 0.106, 3 headings (V0 on
m08: 108s and 128s).

## Limitations

- Needed-later tokens reward concrete identifiers; they do not score a
  decision stated in prose and followed later without restating its terms.
- Packs are not the handoff doc: the main model writes the doc from packs plus
  in-window context, so these numbers bound the packs' contribution only.
- Synthetic 50%/85% cuts are not real handoff points.
- The reader probe uses one model family to write questions, docs, answers,
  and grades. The writer cannot verify narrative claims against the repo.
- `invented` counts tokens missing from the flattened prefix; flattening drops
  some content (skill text, non-string tool input), so it overcounts.
