# CommitCraft

AI-powered git workflow toolkit for Claude Code. Handles conventional commits, issue validation, PR creation, and release guidance — through a single skill with six workflows.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install commitcraft@nautilai
```

Then, in any git repo, invoke a workflow:

```text
/commitcraft commit     # AI-generated conventional commit
/commitcraft push       # commit + push with issue tracking
/commitcraft pr         # PR with an AI-generated description
/commitcraft release    # semantic version bump + release notes
/commitcraft setup      # configure tooling (runs in chat)
/commitcraft check      # validate configuration
```

CommitCraft also triggers from natural language — "commit my changes", "open a PR",
"cut a release" — without the explicit slash form.

## Workflows

| Workflow | Description |
|---|---|
| `commit` | Stages files individually, generates a conventional commit message, handles pre-commit hooks |
| `push` | Full commit + push with issue validation, branch tracking, and post-push issue comments |
| `pr` | Creates a PR with AI-generated description, issue linking, draft support |
| `release` | Guides semantic versioning via release-please (if configured) or manual tag workflow |
| `setup` | Interactive 8-component tooling setup (commitlint, gitleaks, pre-commit, signing, release-please, CI, issue tracker, branch protection — the last can be provisioned via the GitHub API so CI checks actually gate merges) |
| `check` | Validates installed tooling and reports configuration status |

> **`setup` runs in chat** — Claude gathers your choices via prompts and applies them with
> non-interactive flags, so there's no drop-out to a shell: `--yes` (accept defaults),
> `--ticket <github\|linear\|jira\|none>`, `--apply-branch-protection`, `--pr-reviews <N>`
> (`0` = no required reviews, for solo repos), and `--no-enforce-admins`. The script is
> still fully interactive when you run it directly.

## Architecture

```text
commitcraft/                          # ${CLAUDE_PLUGIN_ROOT}
├── .claude-plugin/plugin.json        # Plugin manifest
├── skills/commitcraft/
│   ├── SKILL.md                      # Routes <argument> to the matching workflow
│   └── workflows/                    # commit, push, pr, release, setup, check
├── scripts/
│   ├── commitcraft-setup.sh          # Interactive tooling setup + --check mode
│   ├── commitcraft-issues.sh         # Branch-based issue validation (GitHub/Linear/Jira/none)
│   └── commitcraft-release-analyze.sh# Semantic version analysis (fallback release)
└── templates/                        # commitlint, gitleaks, pre-commit, release-please configs
```

`SKILL.md` reads `skills/commitcraft/workflows/<argument>.md` and follows it. Workflows
shell out to the bundled scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/…`, so paths resolve
correctly regardless of where the plugin cache lives.

## Behavioral conventions

- **Conventional commits** — `<type>(<scope>): <subject>`; subject ≤50 chars, lowercase, no emoji; body lines ≤72 chars. Enforced by the commitlint hook locally **and** in CI (see `.commitlintrc.yml`)
- **No `git add -A`** — each file is staged individually (`git add <file>`)
- **No attribution footers** (no `Co-Authored-By` or similar)
- **Never `--no-verify`** — hook failures are hard stops, not bypasses
- **Branch from main** — the commit workflow auto-creates feature branches when on `main`

## Requirements

- Claude Code with plugin support
- `git`
- `gh` (authenticated via `gh auth login`) for GitHub-Issues validation, PR creation, and
  optional branch-protection provisioning — workflows degrade gracefully when it is absent
  (a missing `gh` warns and continues rather than blocking commit/push/analysis)
- The issue tracker is configurable via `setup` (`github` | `linear` | `jira` | `none`);
  Linear/Jira reference keys from the branch name (e.g. `Refs ENG-123`) and need no `gh`
- Optional per-repo tooling (commitlint, gitleaks, pre-commit, release-please),
  configured by the `setup` workflow

## Troubleshooting

**`setup --check` reports missing tools**
Some tools are optional. Workflows continue without full tooling — missing checks are skipped.

**`gh` not authenticated or absent**
`commit` and `push` degrade gracefully — issue validation is skipped with a warning and the
workflow continues (no hard stop). `pr` creation and GitHub-Issues linking still need
`gh auth login`; the `linear`/`jira`/`none` trackers don't use `gh` at all.

**Wrong subcommand**
Use lowercase: `commit`, `push`, `pr`, `release`, `setup`, `check`. An unrecognized
argument falls back to the `commit` workflow.

## Shoals (project corrections)

When you correct how CommitCraft commits, scopes, names branches, or writes
messages, it records the lesson in `.claude/shoals/commitcraft.commitcraft.md` in
your project and reads it back on the next run, so it won't repeat a mistake you
already flagged. The file is append-only and committed by default (teammates
inherit it) — `.gitignore` it if you'd rather keep it per-developer.
