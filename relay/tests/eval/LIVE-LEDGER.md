# Relay live-validation ledger (#60)

Operational robustness of relay's extractors against **real** session
transcripts — does the pipeline run, scrub, and degrade correctly under real
load and diverse shapes? This is **not** a recall-quality measure (real
transcripts have no planted ground truth; see `LEDGER.md` for the
planted-fact recall eval). Manual, live Haiku calls, run via
`live-validate.sh <transcript>...` — the operator supplies real transcript
paths; only shapes and aggregate metrics are recorded here, never content.

Shape label: size band (sm <1MB, md <8MB, lg <18MB, xl ≥18MB) + `cmpN`
(compaction boundaries) + `agents` (≥20 subagent transcripts alongside).

## Run — 2026-07-06 · commit 0f5d940+wt · model haiku · n=5

| Shape | Bytes | Cmp | Subs | Files | Cmds | Fail | Users | [REDACTED] | Narrative | Secs | Headings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| xl/cmp3/agents | 21,141,088 | 3 | 75 | 77 | 50* | 21 | 98 | 0 | ok | 161 | 3 |
| lg | 10,726,451 | 0 | 0 | 5 | 15 | 5 | 15 | 0 | ok | 43 | 3 |
| lg/cmp1/agents | 10,695,093 | 1 | 40 | 36 | 50* | 83 | 109 | 13 | ok | 161 | 3 |
| md/cmp4 | 5,936,888 | 4 | 9 | 21 | 50* | 6 | 18 | 0 | ok | 36 | 3 |
| sm | 719,796 | 0 | 0 | 0 | 28 | 1 | 5 | 0 | ok | 35 | 3 |

`*` = Commands section hit its documented last-50 cap (working as designed).

Injection sanity (`injection-check.sh`, live): **PASS** — all 5 attack classes
resisted (no PWNED, no persona-prefix, no system-prompt disclosure, non-empty
output, 3 headings intact).

## Findings

- **Relay held on every real shape.** Narrative exited `ok` with the full
  three-heading structure on all 5 transcripts — zero degrades, timeouts,
  crashes, or empty outputs across 720 KB → 21 MB, 0 → 4 compaction
  boundaries, and 0 → 75 subagent transcripts.
- **The 21 MB / 3-compaction / 75-subagent stress case completed** the full
  pipeline: fact pack extracted, narrative ran in 161 s across 3 chunks. The
  120 s per-call timeout is per chunk, not per run, so a large multi-chunk
  transcript is not at risk of a false timeout. No memory issue observed.
- **Scrub fires on real content, not just fixtures.** The subagent-heavy
  10.7 MB session produced 13 `[REDACTED]` hits — evidence the secret scrub
  is doing real work on live transcripts, exactly its purpose.
- **Latency scales with chunk count as designed:** single-chunk runs
  35–43 s, three-chunk runs 161 s (~50 s per real chunk-call here, above the
  ~19 s trivial-call figure because real chunks are large). Cost this run:
  6 live Haiku invocations (~10 chunk-calls total including injection-check).
- **Sidechain isolation confirmed under load:** the fact packs' user-message
  counts (5–109) are main-conversation only despite up to 75 subagent
  transcripts alongside — subagent traffic did not leak in, matching the
  SCHEMA.md finding that sidechains live in separate files the resolver never
  reads.

## Limitations (stated plainly)

- **n=5, one machine, one operator's sessions, one run each** — no variance
  or cross-environment data.
- **Operational, not recall-quality.** This confirms the pipeline runs and
  degrades correctly on real load; it does **not** measure whether the
  narrative *accurately* captured each real session's decisions — real
  transcripts have no ground truth, and content can't be inspected here for
  privacy. Recall accuracy remains the planted-fact eval's job (`LEDGER.md`).
- No non-code-only transcript was positively identified; the `lg` (0-subagent,
  light-file-activity) session is the closest to a non-code shape but was not
  confirmed as such from metrics alone.
