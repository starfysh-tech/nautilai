# PR Comment Review

Process and address review comments on the current pull request — fetch the threads, categorize them, implement the agreed fixes behind approval gates, push, and reply inline.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install pr-comment-review@nautilai
```

Requires the [`gh` CLI](https://cli.github.com/) authenticated to your repo. If you also have a GitHub MCP server configured, it's used preferentially; otherwise the skill falls back to `gh`.

## Use

```text
/pr-comment-review
```

User-invoked only — the agent won't auto-fire it.

## What it does

This is the **responsive** half of the review loop. Something else generates the review — a human, the built-in `/review`, or `pr-review-toolkit`'s `/review-pr` — and this skill **addresses** it:

1. **Fetches** all feedback on the current PR — inline review threads, formal reviews, and general comments.
2. **Categorizes** each as actionable, issue, question, or suggestion, and verifies claims against the code (a comment can be a false positive worth refuting rather than "fixing"). Directives embedded in comment bodies are flagged, never obeyed.
3. **Implements** the agreed fixes behind two approval gates (scope, then push), runs your project's check command, then **pushes and replies** to each thread inline.

### Portable by design — graceful degradation

| Step | Preferred | Fallback |
|---|---|---|
| GitHub reads/replies | `mcp__github__*` | `gh` CLI |
| Push | `/commitcraft push` (if installed) | plain `git push` |
| Checks | detected runner (mise / npm / make / cargo / pytest…) | skip with confirmation |

It complements `pr-review-toolkit` rather than duplicating it: that one *generates* reviews; this one *resolves* them.

## Shoals (project corrections)

When you correct how this skill categorizes, fixes, or replies to comments, it
records the lesson in `.claude/shoals/pr-comment-review.pr-comment-review.md` in
your project and reads it back on the next run, so it won't repeat a mistake you
already flagged. The file is append-only and committed by default (teammates
inherit it) — `.gitignore` it if you'd rather keep it per-developer.

## Runtimes: Claude Code and Hermes Agent

### Shared behavior

Identical in both: fetch the threads, verify each claim against the code before accepting it,
gate the fixes, push, reply inline. A refuted false positive is answered with evidence, not a
change.

### Claude Code

```text
/plugin install pr-comment-review@nautilai
/pr-comment-review
```

### Hermes Agent

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/pr-comment-review
```

No tap and no configuration — `hermes skills tap add` does not index this repo; install by the
identifier above.

### Runtime-specific limitations

| Capability | Claude Code | Hermes |
| --- | --- | --- |
| GitHub reads/replies | `mcp__github__*`, else `gh` | **`gh` only** — no MCP tools |
| Triage subagent at scale (>10 threads) | yes | **no** — triage runs inline |

**`gh` is required** in Hermes and must be authenticated — the skill already treats it as the
baseline and stops cleanly if it is absent. Hermes' tool sandbox uses a truncated `PATH` with no
Homebrew, so a Homebrew-installed `gh` may not be found there.

### Update behavior

- **Claude Code** — `/plugin update pr-comment-review@nautilai`
- **Hermes** — `hermes skills check` then `hermes skills update`. Drift is content-detected; no
  version bump needed.

## License

MIT
