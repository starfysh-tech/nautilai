---
name: cc-validate-hooks
description: Validate the local Claude Code hooks configuration (`.claude/settings.json` and `~/.claude/settings.json`) and report JSON/schema errors, invalid or unrecognized event names, malformed matchers/regex, and bad hook fields (type/command/timeout). Use when the user runs /cc-validate-hooks, says 'check my hooks', 'why isn't my hook firing', 'validate settings.json', 'hooks broken', or after editing hook config. Pass --fix to auto-correct repairable issues.
context: fork
argument-hint: "[--fix]"
allowed-tools: [Read, "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-hooks.sh:*)"]
---

# Hooks Validator

Validates your Claude Code hooks configuration to catch errors that would
otherwise surface as UI failures or hooks that silently never fire.

## Usage

```bash
/cc-validate-hooks
/cc-validate-hooks --fix
```

## What It Checks

1. **JSON syntax** — the settings file parses as valid JSON.
2. **Hook structure** — each event maps to an array of matcher blocks, each
   block has a `hooks` array, and each hook is an object.
3. **Event names** — flagged against the known event list (see below).
4. **Matchers** — a `matcher` on a matcher-less event is warned about (it will
   be ignored); matcher regex patterns are compile-checked.
5. **Hook fields** — `type` must be one of `command`, `http`, `mcp_tool`,
   `prompt`, `agent` (an unrecognized type is warned about, not errored); each
   type's required field is present and a non-empty string (`command`→`command`,
   `http`→`url`, `mcp_tool`→`server`+`tool`, `prompt`/`agent`→`prompt`);
   `timeout`, if present, must be a positive number.

With `--fix`, repairable issues (unused matchers, missing `type` → `command`) are
corrected in place; an existing `type` is never rewritten. A `.bak` backup of the
original file is written first, and its path is printed in the output.

## Finding dispositions

The `--fix` flag is the **auto-fix** disposition (nautilai convention): only safe,
mechanical, intent-preserving repairs (missing `type`, unused matcher), always
behind a `.bak` backup. Everything else is **report** — passing checks and
warnings (unknown event/type, which may be valid in a newer Claude Code) are
surfaced, not changed. Malformed config that `--fix` deliberately won't touch
(e.g. a non-string `type`) is **ask-user** — reported as an error for you to
decide, never silently rewritten.

## Valid Hook Events

The known-events list is synced from the official docs
(https://code.claude.com/docs/en/hooks.md, last synced 2026-06-18). Rather than
freezing a list here, the validator treats an **unrecognized event name as a
warning, not an error** — it may be a typo, or it may be a valid event added in
a newer Claude Code. Recognized events are split into those that accept a
`matcher` field (e.g. `PreToolUse`, `PostToolUse`, `SessionStart`) and those
that do not (e.g. `UserPromptSubmit`, `Stop`, `PostToolBatch`).

### Matchers
- `*` or `""` — all tools
- Tool names: `Read`, `Write`, `Edit`, `Bash`, etc.
- Regex patterns: `Edit|Write`, `Notebook.*`

## Execution

Run the validation script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-hooks.sh ${ARGUMENTS:-}
```

Report results and suggest fixes if errors are found.
