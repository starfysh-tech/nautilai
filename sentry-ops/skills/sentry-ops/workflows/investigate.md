# Investigate

One issue → the line of code that raised it. Ends with a diagnosis, not a patch.

**Requires the Sentry MCP server.** If it is absent, say so and stop.

Complete Phase 0 in `SKILL.md` first. Step 2 below branches entirely on what it found.

## 1. Fetch the issue

Take the issue ID or Sentry URL from `$ARGUMENTS`. If none was given, ask for one — do
not guess at the top issue.

Fetch the issue and at least one full event. You need: the exception type and value,
the stack trace, tags, context, breadcrumbs, and the environment/release.

Do not run Seer yet.

## 2. Locate the code — branch on sourcemap state

**If Phase 0 found sourcemaps uploaded and the build is de-minified**, read the stack
trace directly. Top in-app frame first.

**If Phase 0 found no sourcemap upload and a minified production build**, the stack
trace is not an index into the codebase. Frames will read as hashed chunk names and
single-letter functions. **Do not try to locate code from the trace, and do not pattern-
match a minified identifier to a source symbol** — that guess is wrong more often than
it is right, and it produces a confident bad diagnosis.

Navigate by tags and context instead: the repo's own tagging convention, discovered in
Phase 0, is the index. Add "sourcemaps are not uploaded" to your report as a finding —
it is the single biggest reason this investigation is harder than it should be.

## 3. Recognize a mis-captured error

A title that is a short meaningless token, or an exception value that is `[object
Object]`, `Non-Error exception captured`, or similar, means **a non-`Error` value was
passed to capture**. The real message is inside the serialized context payload, not the
title, and there is no useful stack because the value never had one.

Two consequences, both worth stating:

- Read the serialized context for the actual error. Do not diagnose from the title.
- The capture site itself is defective. Note it for `instrument`.

Clients that return `{ data, error }` where `error` is a plain parsed-JSON object are a
common source of this. So is `catch (e)` re-throwing a string, and rejected promises
carrying a response body.

## 4. Read the capture site before forming a theory

Open the file the tags pointed you at. Read the surrounding code — the call that failed,
what it was passed, what the caller does with the result.

**If you catch yourself proposing a fix before you have read that code, stop.** Phase 0
and the tags told you exactly where to look, so guessing is never justified here.

Check whether the same failure mode exists in sibling callers. The root-cause fix is
usually one guard in the shared function, not a guard at the one call site the issue
happened to name.

## 5. Seer — only if the code does not explain it

If, after reading the capture site and its callers, the cause is genuinely not visible,
you may run Seer analysis. Say why you are escalating before you do, and warn that it
takes minutes.

Treat Seer's output as a hypothesis to verify against the code, not as a conclusion. It
does not know Phase 0's facts about this repo.

## 6. Report

- **What fails**: the operation, in domain terms.
- **Where**: `file:line` of the raising code and of the capture site, if they differ.
- **Why**: the actual mechanism, traced through the code you read.
- **How far it spreads**: which sibling callers share the defect.
- **Instrumentation defects found along the way**: mis-captured non-`Error` values,
  missing tags, absent sourcemaps, silent catch blocks.
- **Confidence**, stated plainly. If you navigated by tags because the trace was
  unreadable, say the diagnosis rests on that.

**Completion criterion** — you can point at the file and line that raised it. If you
cannot, report that you could not localize it and what is blocking you. Do not ship a
plausible-sounding guess.

Do not edit code here. Offer `instrument` for capture-site fixes, or hand the diagnosis
to the user for the functional fix.
