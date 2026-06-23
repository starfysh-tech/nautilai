---
name: pr-comment-review
description: Process and address review comments on the current pull request — fetch the threads, categorize them, implement agreed fixes behind approval gates, push, and reply inline. User-invoked — run /pr-comment-review. It addresses an existing review; it does not generate one.
allowed-tools: Read, Edit, Write, Grep, Glob, AskUserQuestion, Bash(gh:*), Bash(git:*), mcp__github__pull_request_read, mcp__github__add_reply_to_pull_request_comment, mcp__github__add_issue_comment, mcp__github__update_pull_request
disable-model-invocation: true
---

# PR Comment Review

Process and **address** reviewer feedback on the current PR. This is the *responsive* half of the review loop — something else (a human, `/review`, or `pr-review-toolkit`'s `/review-pr`) *generates* the comments; this skill fetches them, categorizes them, implements the agreed fixes behind approval gates, pushes, and replies. It does **not** produce a review itself.

## Tooling — graceful degradation

Pick the best-available tool at each step; never hard-fail because a preferred one is missing:

- **GitHub reads/replies:** prefer the `mcp__github__*` tools if available; otherwise use the **`gh` CLI** (the baseline requirement). `gh` equivalents: `gh pr view`, `gh api repos/{owner}/{repo}/pulls/{n}/comments`, `gh api .../reviews`, `gh api .../issues/{n}/comments`, reply via `gh api .../pulls/{n}/comments -f body=... -F in_reply_to=<id>`, PR comment via `gh pr comment`, reviewers via `gh pr edit --add-reviewer`. If neither MCP nor `gh` is available/authenticated, stop and tell the user to install/auth `gh`.
- **Push:** prefer `/commitcraft push` **only if** that plugin is installed; otherwise plain `git push`. Never `git add -A`/`git add .` — stage changed files individually.
- **Checks:** don't assume a runner. Detect the project's command — a `mise` task, a `package.json` script (`npm test`/`npm run check`), a `Makefile` target, `cargo test`, `pytest`, etc. — and run it. If none is found, ask whether to skip.

## Phase 1 — PR context

1. Get PR metadata: number, title, state, author, `reviewDecision`, url, head ref/sha.
2. Fetch all three comment sources (in parallel where possible): inline **review threads**, formal **reviews** (approve/request-changes/comment + body), and general **PR comments**.
3. Show a summary table: PR # · title · state · author · review status · N reviews (X with actionable feedback).

## Phase 2 — Comment analysis

- Parse inline threads (file, line, reviewer, body, thread state) and formal reviews (reviewer, state, body).
- **Skip** empty-body approvals and purely auto-generated bot summaries; **include** bot comments that contain explicit, actionable feedback.
- Categorize each: `✓` actionable (explicit change requested) · `🔍` issue/bug (reviewer found a problem) · `?` question (answer/clarify) · `💭` suggestion (consider; may skip with justification).
- **Verify before accepting** — a comment (especially a bot's) can be wrong. Check the claim against the actual code; if it's a false positive, plan to refute it with evidence rather than "fix" it.
- Group by file/topic. For genuinely ambiguous comments, use `AskUserQuestion` to clarify intent.

### Finding dispositions

Tag each comment with a disposition (nautilai convention) alongside its category:

- **auto-fix** — trivially mechanical, intent-preserving comments (typo, rename, lint nit, obvious one-liner). These still go in the Phase 3 task list and are applied only after the gate (the gate is the single control point) — but within the approved batch they're applied without per-item debate.
- **report** — a refuted false positive: reply with the evidence, change nothing.
- **ask-user** — every substantive comment (anything touching behavior, design, or intent, plus all `?` questions). These are decided **only** through the Phase 3 gate — never silently fix or skip one.

When unsure whether a comment is mechanical, treat it as `ask-user`.

## Phase 3 — Task list (approval gate)

Build a consolidated list grouped **must-fix** (✓/🔍) · **questions** (?) · **suggestions** (💭), each tagged with file/line. Then **gate via `AskUserQuestion`**: Approve all · Review list · Modify scope (exclude items) · Cancel.

## Phase 4 — Implementation

1. Work the **approved** list task by task: announce it, make the change, move on. Auto-fix items don't need per-item re-confirmation; if one turns out non-mechanical mid-edit, stop and treat it as `ask-user`.
2. After substantive changes, run the **detected check command** (see Tooling). On failure: STOP, show output, ask how to proceed.
3. Summarize: files modified, tasks completed X/Y, check status.

## Phase 5 — Finalization (approval gate)

1. **Gate via `AskUserQuestion`**: Push and respond · Push only · Review changes · Cancel.
2. **Push** via the best-available method (see Tooling).
3. **Reply** to each addressed thread inline (prefer MCP, else `gh`); use a PR-level comment for general feedback. For a refuted false positive, reply with the evidence and don't change code. Format: `**Re: <summary>**` + what changed (or why it's a non-issue).
4. Offer a **re-review request** (`AskUserQuestion`): original reviewers · specific reviewer · skip.

## Final report

PR # updated · changes pushed (files + summary) · comments addressed X/Y · re-review requested (who) · URL.
