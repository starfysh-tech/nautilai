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
/commitcraft:commitcraft commit     # AI-generated conventional commit
/commitcraft:commitcraft push       # Commit + push with issue tracking
/commitcraft:commitcraft pr         # Create PR with AI-generated description
/commitcraft:commitcraft release    # Semantic version bump and release guidance
/commitcraft:commitcraft setup      # Interactive tooling configuration
/commitcraft:commitcraft check      # Validate current configuration
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

- **No `git add -A`** — each file is staged individually (`git add <file>`)
- **No emoji prefixes** in commit messages
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

**`gh` not authenticated**
Issue validation and PR creation require `gh auth login`. Issue steps are skipped and PR
creation fails with a clear error otherwise.

**Wrong subcommand**
Use lowercase: `commit`, `push`, `pr`, `release`, `setup`, `check`. An unrecognized
argument falls back to the `commit` workflow.
