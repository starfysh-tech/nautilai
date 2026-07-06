# Relay environmental assumptions

Relay's extractors were built empirically against one development machine
(macOS, bash 5.3 available but scripts written for bash 3.2 compatibility,
`jq` 1.8, Claude Code 2.1.199-2.1.201) by reading real transcript JSONL and
hook payloads produced there. Nothing here is from a published Claude Code
schema doc — none exists publicly — so every assumption below is "observed
behavior on that machine, on those versions" unless marked otherwise. If
Relay misbehaves for you, this is the list to check first, and
`scripts/doctor.sh` (bottom of this doc) automates most of it.

Confidence key:
- **Observed** — reverse-engineered from real transcripts/hook payloads; not
  documented anywhere; could change without notice in a Claude Code release.
- **Documented** — behavior Claude Code's own docs or `--help` commit to.
- **Inferred** — never directly observed to fail, but not verified either;
  a reasonable extrapolation from what *was* observed.

## Transcript location and identity

### Transcript path: `~/.claude/projects/<slug>/<session-id>.jsonl`
- **Where used:** `resolve-session.sh` (the only place this is hardcoded);
  everything else takes a transcript path as an argument.
- **Confidence:** Observed. Claude Code's storage layout for session
  transcripts is not part of any published API contract.
- **What breaks if wrong:** `resolve-session.sh` prints nothing usable (or
  errors "no transcript directory found"), and every downstream script
  (`extract-transcript.sh`, `haiku-narrative.sh`, the `/handoff` skill) has
  nothing to read. This is the single point of failure for the whole plugin.

### Project slug rule: `$PWD` with every `/` and `.` replaced by `-`
- **Where used:** `resolve-session.sh` (`project_slug()`),
  `session-start-pickup.sh` (inline, comment says "mirrors resolve-session.sh"),
  `hooks/precompact-notify.sh` (inline, same comment).
- **Confidence:** Observed, and only ever observed against **POSIX-style,
  forward-slash cwd paths on macOS**. The rule is applied identically in three
  separate files by convention, not by calling a shared function — if the real
  rule ever changes (e.g. a Claude Code version starts collapsing repeated
  slashes, or handling a trailing slash differently, or hashing instead of
  transliterating), all three copies drift out of sync simultaneously and
  silently.
- **What breaks if wrong:** every slug-dependent path (transcript project dir,
  `~/.claude/handoffs/<slug>/`) is computed wrong, so `resolve-session.sh`
  can't find the transcript directory, and the SessionStart/PreCompact hooks
  read and write handoff markers to a directory nothing else looks at — no
  crash, just silent no-ops (pickup hook fails open per its own design; see
  below).
- **Windows note:** a Windows-native cwd (`C:\Users\name\project`) has never
  been fed through this rule. Backslashes wouldn't be touched by
  `tr '/.' '-'` at all, and a drive-letter colon (`C:`) is untouched too — so
  the resulting "slug" would just be the raw Windows path with dots
  replaced, almost certainly not matching whatever directory name Claude Code
  actually uses on Windows. **This has never been tested on Windows and there
  is no reason to assume it's correct there.**

### `CLAUDE_CODE_SESSION_ID` / `CLAUDE_SESSION_ID` environment variables
- **Where used:** `resolve-session.sh`, checked in that order (first wins).
- **Confidence:** Observed, undocumented. Neither variable appears in Claude
  Code's published CLI/settings docs; they were found by inspecting the
  process environment of a running session on the dev machine. Two names are
  checked because both were seen used across different Claude Code versions/
  contexts during development — there is no confirmation of which one (if
  either) is guaranteed to be present in any given release, or whether a
  future version renames or removes them entirely.
- **What breaks if wrong:** not fatal — `resolve-session.sh` explicitly falls
  back to a newest-mtime guess over `*.jsonl` in the project dir, with a
  warning to stderr. The risk is a *silent wrong guess*: if another Claude
  Code session (or a background task) touches a different transcript file in
  the same project more recently than the real current session, the mtime
  fallback picks the wrong transcript and every downstream extraction is
  grounded in the wrong conversation, with no error — just a warning on
  stderr that's easy to miss.

## JSONL line shapes

### `type` field values: `"user"`, `"assistant"` are the only ones the extractors read
- **Where used:** every `select(.type=="user")` / `select(.type=="assistant")`
  filter in `extract-transcript.sh` and `haiku-narrative.sh`.
- **Confidence:** Observed. Live transcripts also contain other `type` values
  — during this review, a real transcript in this environment was found to
  contain `"attachment"`, `"last-prompt"`, and `"queue-operation"` lines in
  addition to `"user"`/`"assistant"`. **This is an assumption the original
  build didn't document**: the extractors implicitly assume any `type` other
  than `user`/`assistant` is safe to ignore. That has held up in every
  transcript seen so far (the `select()` filters just skip non-matching
  lines rather than erroring), but it means a hypothetical future line type
  that *should* count as conversational content (e.g. a new kind of
  system-relayed user turn) would be silently dropped, not flagged.
- **What breaks if wrong:** silent data loss — a message type that should
  contribute to the fact pack or narrative simply doesn't appear, with no
  error surfaced anywhere.

### `message.content` is a string, an object with `.text`, or an array of typed blocks
- **Where used:** the `if ($c|type)=="string" ... elif =="object" ... elif
  =="array" ...` branches in both `extract-transcript.sh` (user messages) and
  `haiku-narrative.sh` (user + assistant messages); also
  `files_json`/`cmd_list` in `extract-transcript.sh`, which assume assistant
  `message.content` is always an array of blocks with a `.type` field
  (`tool_use`, `text`, etc.) and never a bare string.
  and `is_error` on `tool_result` blocks (`extract-transcript.sh`'s Failures
  section) — the array-of-blocks shape is also assumed for tool_result
  `content`, which can itself be a string, an object, or an array (three-way
  branch mirrored there too).
- **Confidence:** Observed across the three shapes actually seen in real
  transcripts. Not documented as a stable wire format. All three shapes are
  handled by falling through to `null`/`empty` rather than erroring, so an
  unrecognized fourth shape degrades to "message text not found" rather than
  a crash — but that's a property of defensive coding, not a documented
  guarantee that only these three shapes occur.
- **What breaks if wrong:** a message with a content shape the scripts don't
  recognize is silently treated as having no text — it's dropped from the
  fact pack's "User messages" section and from the narrative dialogue stream,
  with no warning.

### `isMeta` and `isCompactSummary` boolean flags on user lines
- **Where used:** `select(.isMeta != true)` and
  `select(.isCompactSummary != true)` in both extractors, to exclude
  harness-injected content (skill prompts, compaction continuations) from
  what's treated as something the user actually typed.
- **Confidence:** Observed, undocumented. `isMeta` was found by inspecting
  which lines correspond to injected skill/system prompts vs. real user
  keystrokes; `isCompactSummary` similarly for post-compaction continuation
  turns.
- **What breaks if wrong:** if a future Claude Code version stops setting
  these flags (or renames them), harness-injected text starts appearing in
  the "verbatim user messages" section and the narrative dialogue as if the
  user typed it — polluting the handoff doc with noise, not a crash.

### String-prefix exclusions for content Claude Code injects without a structural flag
- **Where used:** the `startswith("<command-")`, `startswith("<local-command"`,
  `startswith("<system-reminder"`, `startswith("Base directory for this
  skill"`, `startswith("Another Claude session sent a message:"` checks,
  identical in both extractors.
- **Confidence:** Observed, and explicitly acknowledged in the extractor's
  own comments as covering "injections that carry no structural marker" —
  i.e., these are known-incomplete pattern matches against specific injected
  strings seen during development, not an exhaustive or versioned list. Any
  new injection format Claude Code adds later (different tag name, different
  boilerplate wording) won't be caught until someone notices it leaking into
  a handoff doc and adds a new prefix.
- **What breaks if wrong:** injected boilerplate text leaks into the fact
  pack / narrative as if it were a real user message.

### `isSidechain` / subagent turns — deliberately NOT filtered
- **Where used:** nowhere, and that's intentional.
- **Confidence:** Observed (surveyed all 160 top-level session transcripts on
  the development machine, plus a subagent-heavy project): sidechain/subagent
  turns are never inlined in the top-level `<session-id>.jsonl`. They live in
  separate files at `<project-dir>/<session-id>/subagents/agent-<hash>.jsonl`
  (tagged `isSidechain: true`, carrying the parent `sessionId`), which
  `resolve-session.sh` structurally never resolves to. A filter in the
  extractors would be dead code against any real input today.
- **What breaks if wrong:** if a future Claude Code version starts inlining
  sidechain turns in the main transcript, subagent prompts and outputs would
  silently pollute "User messages (verbatim)" and the narrative dialogue as
  if the user wrote them. That is the drift to watch for; the fix at that
  point is an `isSidechain != true` exclusion in both extractors' jq filters.

## Hook input fields

### SessionStart hook: `.source`, `.cwd`
- **Where used:** `session-start-pickup.sh` — `source` gated to
  `startup|clear` (any other value exits quietly, e.g. `resume` is
  deliberately excluded), `cwd` used to compute the slug.
- **Confidence:** Documented — `source` and `cwd` are part of Claude Code's
  published SessionStart hook payload.
- **What breaks if wrong:** if `cwd` is ever absent or empty, the hook exits
  0 with no injection (fail-open by design) rather than erroring — so a
  missing field degrades to "no handoff picked up," silently.

### PreCompact hook: `.trigger`, `.cwd`, `.transcript_path`
- **Where used:** `precompact-notify.sh` — gated to `trigger=="auto"` (manual
  `/compact` is intentionally excluded since nothing needs recovering), `cwd`
  for the slug, `transcript_path` written into the `compacted-<epoch>`
  marker for `/handoff recover` to read later.
- **Confidence:** Documented — all three are part of the published PreCompact
  hook payload.
- **What breaks if wrong:** same fail-open pattern as above; a missing field
  means the marker is never dropped and `/handoff recover` has nothing to
  find, not a hook error.

## `claude` CLI contract

### `claude -p --model haiku --system-prompt "<text>" "<prompt>"` reads stdin, writes result to stdout
- **Where used:** `haiku-narrative.sh`'s `run_with_timeout()`.
- **Confidence:** Documented CLI flags (`-p`/`--print`, `--model`,
  `--system-prompt` are all documented Claude Code CLI options), but the
  *specific combination* — piping transcript text via stdin as the subject
  matter while `--system-prompt` replaces (not appends to) the default
  CLAUDE.md-inheriting system prompt — was verified empirically against
  2.1.199-2.1.201 (see `relay/tests/eval/LEDGER.md` for the validation runs).
  No guarantee a future CLI version changes how stdin is treated relative to
  the trailing prompt argument.
- **What breaks if wrong:** the script's own degrade path handles this:
  `run_with_timeout` returns non-zero on any failure (bad flag, CLI missing,
  timeout), and `haiku-narrative.sh` exits 3 with "narrative unavailable" —
  callers are expected to treat that as graceful degradation, not a hard
  error. The `/handoff` skill proceeds without the narrative pack and notes
  it in Provenance.
- **Nested invocation:** the comment at `haiku-narrative.sh:208-210` asserts
  that `claude -p` invoked *from inside* a Claude Code session (i.e. this
  script running as a tool call in one) is "validated working; no recursion
  guard needed beyond what the CLI already enforces" — this is an
  observed-empirically claim about the current CLI's own recursion handling,
  not something Relay enforces itself.

## Secret scrubbing

### `scrub()` — best-effort redaction, intentionally independent of `.gitleaks.toml`
- **Where used:** identical `scrub()` in `extract-transcript.sh` and
  `haiku-narrative.sh` (a test asserts the two bodies stay byte-identical).
- **What it covers:** AWS `AKIA`, GitHub tokens, `sk-`, Slack `xox` + webhook
  URLs, Google `AIza`, JWTs, `Bearer`/`Authorization: Basic`, credentialed DB
  connection strings (redacts `user:pass@`, keeps the scheme), multi-line and
  single-line (JSON-escaped `\n`) PEM private keys, and `KEY=value` env-style
  secrets. Best-effort by design — over-redaction only loses fact-pack content,
  it never leaks; it is **not** a completeness guarantee.
- **Confidence:** the pattern set is exercised by the 150-assertion suite and
  ran over a 21 MB real transcript in live validation (`LIVE-LEDGER.md`, #60)
  with 13 redactions and no hang.
- **Provenance note:** the broadened family set (Slack, GCP single-line PEM,
  connection strings, env-secrets) entered via commit `d74b104`, which passed
  through a contaminated edit window (an unaccounted teammate agent altered the
  working tree mid-task; the fabricated justification comment it carried was
  removed in `96e2e63`). The *code* was subsequently read-audited line by line
  and found sound — correct loop termination, BSD-awk-portable, fail-safe — so
  it is kept, not reverted. The single-line PEM regex originally had a
  nested-quantifier (ReDoS) shape; it was rewritten to a single bracket-class
  quantifier (`[A-Za-z0-9+/=\n]*`) that redacts the same input with no
  backtracking risk — verified against a 20k-segment pathological input.

## Platform coverage

- **Built and tested on:** macOS, bash 3.2 compatibility targeted (no
  bash 4+ features used — no associative arrays, no `${var,,}`, no
  `mapfile`), `jq` present. All `stat` calls try GNU syntax (`stat -c '%Y'`)
  first, then BSD (`stat -f '%m'`) as the fallback, with a numeric guard on
  the result. The order matters and was learned from a real CI failure: GNU
  `stat -f` is FILESYSTEM stat and *succeeds* with a multi-line info block
  instead of erroring, silently poisoning a BSD-first fallback chain —
  whereas BSD `stat -c` errors cleanly into its fallback.
- **Linux:** verified by CI — the bundled suites run on ubuntu in the
  `validate` workflow (the GNU-stat ordering bug above is exactly what that
  run caught on its first execution). The pattern relies on
  (`resolve-session.sh`'s mtime loop, `session-start-pickup.sh`'s
  marker expiry check), but **not verified on an actual Linux machine** as
  part of this review — "expected compatible" is an inference from the
  fallback code existing, not a test result.
- **Windows (native, not WSL):** **UNVERIFIED.** Beyond the slug rule already
  flagged above as untested against a Windows-style path, the scripts
  themselves are bash — they assume a POSIX shell is available at all
  (`#!/usr/bin/env bash`), which on native Windows means running under Git
  Bash, MSYS2, or WSL rather than truly "native." Nothing about path
  separators, `$HOME` resolution, or the hardcoded `~/.claude/...` paths has
  been checked against a Windows-native `claude` install. Treat Windows as
  unsupported until someone actually runs `doctor.sh` there and reports back.

## Self-check

Run `relay/scripts/doctor.sh` from the project you're using Relay in to check
these assumptions against your actual environment — no model calls, read-only,
should finish in under 2 seconds. If you're filing a bug, paste its output
first.
