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
│   ├── commitcraft-release-detect-rp.sh # Is release-please FUNCTIONAL / DISABLED / ABSENT?
│   └── commitcraft-release-analyze.sh# Semantic version analysis (fallback release)
├── tests/                            # bash tests (e.g. detect-rp.test.sh) + gh stub
└── templates/                        # commitlint, gitleaks, pre-commit, release-please configs
```

The `release` workflow defers to release-please **only when it is actually
functional**. `commitcraft-release-detect-rp.sh` distinguishes a working
release-please from one that is present-but-neutered (skip flags, no `contents:
write`, or never advanced past `0.0.0`); a disabled release-please falls back to
the manual tag/release path with a one-line reason, rather than dead-ending on a
release PR that will never arrive. Run the detection tests with
`bash commitcraft/tests/detect-rp.test.sh`.

On the manual path, the release notes are **grouped by the repo's own
`release-please-config.json` `changelog-sections`** when that file exists (either
the `.packages["."]` manifest layout or a root-level config), falling back to a
built-in section table otherwise. So a repo declares its changelog categories once
and gets the same sectioned notes whether release-please automates the release or
commitcraft cuts it by hand — honoring the config never requires running
release-please.

`SKILL.md` reads `skills/commitcraft/workflows/<argument>.md` and follows it. Workflows
shell out to the bundled scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/…`, so paths resolve
correctly regardless of where the plugin cache lives.

## Behavioral conventions

- **Conventional commits** — `<type>(<scope>): <subject>`; subject ≤72 chars, lowercase, no emoji; body lines ≤72 chars. Enforced by the commitlint hook locally **and** in CI (see `.commitlintrc.yml`)
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

## Runtimes: Claude Code and Hermes Agent

CommitCraft runs in both. One source, one skill, no fork.

### Shared behavior

The commit workflows and the Conventional Commit policy are identical in both runtimes —
same 72-char subject cap, same `git add <file>` staging, same "never `--no-verify`", same
hard stops on hook failure, same derived default branch.

### Claude Code

Unchanged from what it has always been. **All six workflows**, including `setup` and `check`:

```
/plugin marketplace add starfysh-tech/nautilai
/plugin install commitcraft@nautilai
/commitcraft commit
```

Scripts resolve from `${CLAUDE_PLUGIN_ROOT}/scripts/`.

### Hermes Agent

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/commitcraft
```

Then ask the agent to commit, open a PR, or cut a release. **Four of the six workflows ship:
`commit`, `push`, `pr`, `release`.**

Hermes ships the *skill directory* and nothing else, so the scripts are mirrored into it
(generated by `hermes/sync-resources.sh`, CI-gated against drift). They resolve from
`${HERMES_SKILL_DIR}/scripts/` and are invoked via `bash` — Hermes strips the executable bit
on install.

> **Do not use `hermes skills tap add`.** On Hermes v0.18.2 it registers the tap but indexes
> nothing — the `github` source is skipped and no skill ever surfaces. Skills resolve through
> **skills.sh**, which auto-indexes this public repo; the identifier above works with no tap
> and no configuration.

### Runtime-specific limitations

| | Claude Code | Hermes |
| --- | --- | --- |
| `commit` · `push` · `pr` · `release` | yes | yes |
| **`setup` · `check`** | yes | **no** — see below |
| Subagents / parallel review fan-out | yes | **no** — Hermes has no subagent primitive |
| Script invocation | direct (`./script.sh`) | via `bash` (exec bit stripped on install) |
| Discovery via `search` / `browse` | marketplace | **unreliable** — install by identifier instead |

**`setup` and `check` are Claude Code only.** `commitcraft-setup.sh` is deliberately not
shipped to Hermes: it provisions repo tooling (`npm install` commitlint/husky, `pip install`
pre-commit, reading `~/.ssh/*.pub` to configure commit signing), which Hermes' security
scanner flags as HIGH `exfiltration` + MEDIUM `supply_chain` and blocks with
`Verdict: CAUTION`. That is the scanner working correctly — provisioning tooling *is*
installing packages — so we ship a bundle that passes rather than telling anyone to
`--force` past a security gate. Configure the repo once by hand instead (below), or run
`/commitcraft setup` from Claude Code on the same repo; the resulting config is what both
runtimes read.

<a name="hermes-repo-setup"></a>

### Hermes: repo setup (the `setup` equivalent)

Do this once per repo. CommitCraft in Hermes then behaves exactly as it does in Claude Code.
Every file below is a template this plugin ships — copy the ones you want:

```bash
BASE=https://raw.githubusercontent.com/starfysh-tech/nautilai/main/commitcraft/templates

# 1. Conventional Commits policy — the SAME file local hooks and CI both read
curl -fsSL "$BASE/.commitlintrc.yml"        -o .commitlintrc.yml

# 2. Pre-commit hooks (runs commitlint + gitleaks on every commit)
curl -fsSL "$BASE/.pre-commit-config.yaml"  -o .pre-commit-config.yaml
curl -fsSL "$BASE/.gitleaks.toml"           -o .gitleaks.toml
pipx install pre-commit || pip install pre-commit
pre-commit install --hook-type commit-msg --hook-type pre-commit

# 3. CI — same commitlint policy, enforced on the server
mkdir -p .github/workflows
curl -fsSL "$BASE/commitlint-ci.yml"        -o .github/workflows/commitlint.yml
curl -fsSL "$BASE/gitleaks.yml"             -o .github/workflows/gitleaks.yml

# 4. Optional: Release Please
curl -fsSL "$BASE/release-please-config.json" -o release-please-config.json
curl -fsSL "$BASE/release-please.yml"         -o .github/workflows/release-please.yml
echo '{".":"0.0.0"}' > .release-please-manifest.json

# 5. Optional: disable issue tracking entirely
echo '{"ticket_tool":"none"}' > .commitcraft.json

# 6. Optional: commit signing (do this yourself — we will not touch your keys)
#    git config gpg.format ssh
#    git config user.signingkey ~/.ssh/<your-key>.pub
#    git config commit.gpgsign true
```

Local hooks and CI read the **same** `.commitlintrc.yml`, so enforcement can't drift between
them. Requires `git`; `gh` only for the `pr` workflow.

**If `skills.template_vars: false` is set in `~/.hermes/config.yaml`**, Hermes stops substituting
`${HERMES_SKILL_DIR}`, bundled-script paths arrive literal, and CommitCraft's script calls break.
This is a user-side setting a skill cannot detect or override. Claude Code is unaffected.

`autodev` is **Claude-only** and is deliberately not published for Hermes.

### Update behavior

- **Claude Code** — `/plugin update commitcraft@nautilai`
- **Hermes** — `hermes skills check` then `hermes skills update`.

Hermes detects drift by **content**, not by version — verified: the skill carries no `version:`
field and `inspect` reports no hash, yet a changed upstream bundle is picked up and re-scanned on
update. Upstream fixes therefore reach installed users with no version bump and no re-porting.

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
