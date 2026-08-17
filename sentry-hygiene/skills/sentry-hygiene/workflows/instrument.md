# Instrument

Add or fix capture sites behind the PII gate. Repo-only — reads code, not the Sentry MCP.

This is not SDK setup. Installing or wiring a Sentry SDK in a new project is the official
`sentry` plugin's `sentry-sdk-setup`. This workflow assumes the SDK is already installed
and covers the part that plugin doesn't emphasize: getting each capture site right against
this repo's conventions, and the **inbound-PII gate** (§4).

Complete Phase 0 in `SKILL.md` first. Steps 1 and 2 are entirely built on it.

## 1. Follow this repo's conventions, not a template

Phase 0 sampled the existing capture sites. **Those are the spec.** Match the tag keys,
the casing, the context-key style, and the import style already in use.

Where the existing sites disagree with each other, the majority pattern wins — and note
the minority as a consistency finding rather than propagating it. A single non-compliant
outlier is a defect to fix, not a variant to copy.

If the repo has **no** existing convention, propose one and get agreement before writing
20 call sites against it. A good default is two low-cardinality tags — one naming the
module, one naming the operation — plus structured context for IDs. Keep tags
low-cardinality; high-cardinality values belong in context, not tags, or they degrade
search and grouping.

## 2. Normalize non-`Error` values before capture

Passing a plain object to `captureException` produces a useless title (a short minified
token, or `[object Object]`) and no stack — the real message ends up buried in serialized
context. `audit` flags existing sites with this defect; here you prevent new ones.

If Phase 0 found an existing normalization helper, **use it.** Do not hand-roll a second
one. If there is none, add one small dependency-free helper in a leaf module with no
heavy imports, so any capturing module — on any runtime — can pull it in cheaply and
test in isolation.

Apply it at every site where a caught or destructured `error` can reach Sentry:

- Clients returning `{ data, error }` where `error` is parsed JSON.
- `catch (e)` where `e` may be a string, a rejected non-`Error`, or a response body.
- Rejected promises from `fetch`-style APIs.

Preserve the original error's own diagnostic fields into context — normalizing should
not lose the payload the raw value carried.

## 3. Other capture shapes

- **Non-error signal** worth recording: use the message-capture API with an explicit
  level. Do not capture messages at `error`.
- **A failure state that never throws** (a falsy result, an empty required response, a
  guard that silently returns): capture a synthetic error rather than staying silent.
  A silent failure path is invisible in production by construction.
- **Breadcrumbs**: add them for multi-step operations where the failing step is
  ambiguous from the exception alone. Check first whether the repo uses them at all —
  if it does not, that is a gap worth naming rather than silently starting.

## 4. PII gate — hard stop, both halves

Re-read the PII boundary in `SKILL.md`. Both halves apply to every capture you add.

**What you put in.** No emails, names, tokens, passwords, or raw request/response
bodies. Do not pass a raw caught error into context unchecked — third-party client
errors routinely embed a user email in the message text. And confirm against Phase 0
whether any ID you are about to log is a **bearer capability** rather than an
identifier; if possessing it grants access to the record, do not log it.

**What the SDK adds on its own.** Your capture call is not the only thing on the event;
default integrations enrich it — see the boundary in `SKILL.md` for what, and check it
against docs rather than from memory. Before adding a capture on a path whose URL carries
a token, code, or share ID — auth callbacks, share links, password resets — check what
the event will carry, not just what you passed.

If this repo's own documented rules are narrower than this gate, the gate wins, and say
so rather than silently overriding project docs.

## 5. Verify

Sentry is frequently a no-op in local development — gated init, unset DSN, or an
environment check. If Phase 0 found that, **verify by reading the code, not by
triggering it locally.** An un-exercised capture path looks identical to a working one.

Run the repo's lint and type-check. If capture is mocked in tests, confirm the mock
covers the method you called — a new capture in a tested module usually needs no test
change, but confirm rather than assume.

## Completion criterion

- [ ] Tags match this repo's existing convention and stay low-cardinality
- [ ] Context keys match this repo's existing convention
- [ ] No PII, and no ID that is really a bearer capability
- [ ] Every non-`Error` value is normalized before capture
- [ ] What the SDK attaches on its own was checked for each new capture path
- [ ] Lint and type-check pass

Report every change as `file:line` with its disposition (`auto-fix` / `report` /
`ask-user`). Anything touching a PII-bearing path is `ask-user`, never `auto-fix`.
