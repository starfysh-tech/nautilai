---
name: commitcraft
description: "Generate conventional commits, validate linked issues, create PRs, and produce release notes for this project. Use when the user runs /commitcraft, says 'commit', 'commit my changes', 'open a PR', 'cut a release', 'write release notes', or has staged changes ready to land. Always use commitcraft for commits — never raw `git commit`. Subcommands: commit | push | pr | release | setup | check."
argument-hint: [commit|push|pr|release|setup|check]
allowed-tools: [Bash, Read, Write, Edit, ToolSearch, AskUserQuestion]
---

# CommitCraft

**MANDATORY FIRST STEP — DO NOT SKIP:**
You MUST call `ToolSearch` with query `select:AskUserQuestion` RIGHT NOW before reading any workflow file or doing anything else. AskUserQuestion is a deferred tool that will not exist until you load it. If you skip this step, you will be unable to ask the user questions interactively and will have to fall back to plain text.

1. Call `ToolSearch` with query `select:AskUserQuestion` — wait for it to return before continuing
2. Confirm AskUserQuestion is now available (it will appear in the results)
3. Proceed with the workflow

## Execution Policy

**Every git command runs in the foreground. One attempt per phase. No retries, no background tasks, no `--no-verify`.** Pre-commit hooks can take 60-90 seconds — wait for them.

Take the first whitespace-delimited token of `$ARGUMENTS` as the subcommand; any
remaining words are context to pass into the workflow, not part of the dispatch.

- If `$ARGUMENTS` is empty, read `${CLAUDE_PLUGIN_ROOT}/skills/commitcraft/workflows/commit.md`.
- If the first token is one of `commit|push|pr|release|setup|check`, read
  `${CLAUDE_PLUGIN_ROOT}/skills/commitcraft/workflows/<token>.md` and follow its
  instructions exactly, using the remaining words as context. Do not skip steps.
- Otherwise, do not default to commit — tell the user the subcommand wasn't
  recognized and list the valid ones: `commit, push, pr, release, setup, check`.

Run all commands from the repo root.

## Resource paths (runtime adapter)

Exactly one of these two lines is resolved to an absolute path by your runtime; the
other stays literal `${...}` text. **Use the line that resolved. Ignore the literal one.**

- **Claude Code** — workflows: `${CLAUDE_PLUGIN_ROOT}/skills/commitcraft/workflows/<token>.md`,
  scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`
- **Hermes** — workflows: `${HERMES_SKILL_DIR}/workflows/<token>.md`,
  scripts: `bash ${HERMES_SKILL_DIR}/scripts/<name>.sh`

**If you are in Hermes**, the workflow files you are about to read are written with
Claude Code paths. Translate as you go — everywhere a workflow says
`${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`, run `bash ${HERMES_SKILL_DIR}/scripts/<name>.sh`
instead. The scripts are identical; only the location and the `bash` prefix differ
(Hermes strips the executable bit on install, so scripts must be run via `bash`).

Never substitute a token yourself and never fall back to a relative path. If neither
line resolved, stop and tell the user.

### `setup` and `check` are Claude Code only

`commitcraft-setup.sh` is **not shipped to Hermes** and `${HERMES_SKILL_DIR}/scripts/`
does not contain it. It provisions repo tooling — `npm install` commitlint/husky,
`pip install` pre-commit, reading `~/.ssh/*.pub` to configure signing — which Hermes'
security scanner blocks (`Verdict: CAUTION`), and rightly so.

In Hermes, if the user asks for `setup` or `check`: **do not attempt the script, do not
improvise an equivalent, and do not install anything.** Say that both are Claude Code
only, and point them at the manual setup steps in the plugin's README
(`https://github.com/starfysh-tech/nautilai/tree/main/commitcraft#hermes-repo-setup`).

`commit`, `push`, `pr`, and `release` work normally in Hermes.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/commitcraft.commitcraft.md` from the
project root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — "don't do X / do Y instead" about how
CommitCraft commits, scopes, names branches, or writes messages — append a shoal
to that file (creating `.claude/shoals/` if needed) in this format:

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger** before appending. Capture only explicit
behavioral corrections, not passing preferences. Mention the capture in one line;
don't narrate it.
