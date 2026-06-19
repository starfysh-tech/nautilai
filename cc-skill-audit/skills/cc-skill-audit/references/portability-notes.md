# Portability Notes

Read this when auditing a skill that will run across surfaces, or when the user mentions Cowork or Claude.ai.

The same SKILL.md format works across Claude Code, Cowork, and Claude.ai. But the execution environments differ in ways that quietly break skills. This file is the working knowledge of where things diverge. Surface behavior changes over time — when a portability claim here is load-bearing for a finding, confirm it against the live docs (`https://code.claude.com/docs/en/skills.md`) before reporting it as fact.

## Surface summary

| Surface | Skill location | Filesystem | Shell access | Notes |
|:--------|:---------------|:-----------|:-------------|:------|
| Claude Code (user) | `~/.claude/skills/<name>/` | Full | Yes | Available across all projects |
| Claude Code (project) | `.claude/skills/<name>/` | Full | Yes | Scoped to the project; committed to repo |
| Claude Code (plugin) | `~/.claude/plugins/<plugin>/skills/<name>/` | Full | Yes | Installed via `/plugin install`; use `${CLAUDE_PLUGIN_ROOT}` for bundled-script paths |
| Cowork | `~/.claude/skills/<name>/` (same as Claude Code) | Sandbox | Limited | Uses the same path as Claude Code |
| Claude.ai (uploaded) | Uploaded via Customize → Skills as a zip | Sandbox | None | Code execution must be enabled |

Sources: Claude Code docs (code.claude.com/docs/en/skills), Claude Help Center (Use Skills in Claude), Anthropic Skills overview.

## Same SKILL.md, different execution

Anthropic's marketing claim is that the same skill works across surfaces. The format does. The execution doesn't always. Things that work in Claude Code but break elsewhere:

1. **Shell commands.** Claude Code can shell out freely. Cowork's environment is more restricted. Claude.ai's code execution runs in a Python sandbox with no general shell access.

2. **Filesystem writes outside the working directory.** Claude Code writes to your real filesystem. Cowork and Claude.ai work in sandboxes; written files are downloadable but don't persist on the user's machine.

3. **Local CLI invocations.** A skill that runs `git`, `npm`, or `aws` works in Claude Code if those tools are installed locally. Claude.ai has no such tools available.

4. **Dynamic context injection.** Claude Code supports `!` `command` `` in SKILL.md to run a command and inject its output. This is a Claude Code feature; don't assume it works elsewhere.

5. **Network access.** The Anthropic API code-execution environment has no general network access. List required packages explicitly; don't assume `pip install` works at runtime.

## Writing portable skills

If the skill is supposed to work on more than one surface:

- Avoid shell commands. Use Python or built-in tools instead.
- **For Python scripts, prefer stdlib only.** External pip dependencies don't install at runtime in the Anthropic code-execution environment, and they make the skill brittle across surfaces. If you need a dependency, document it explicitly in SKILL.md and verify it's available in the target environment's documented package list.
- Avoid hardcoded paths. Use `${HOME}`, `${CLAUDE_SKILL_DIR}` (resolves correctly whether the skill is at personal, project, or plugin level), or `${CLAUDE_PLUGIN_ROOT}` (for scripts bundled inside a plugin).
- **Document outputs as "returns content" rather than "writes file" when the skill might run in a sandbox.** In Claude Code, writing to disk works; in Cowork and Claude.ai, the file is created in the sandbox and the user downloads it. A skill that promises "writes RELEASES.md to your repo" misleads users on sandbox surfaces. Instead, write "returns the formatted release notes; in Claude Code, also writes RELEASES.md to the current directory."
- For skills that need filesystem access in some environments and not others, include a conditional branch in the body: "If the environment supports filesystem writes, write to X; otherwise, return the formatted content for the user."

## Claude.ai specifics

- Skills are uploaded as a zip file of the skill folder via Customize → Skills → "+ Create skill"
- The zip should contain exactly one top-level folder; that folder contains SKILL.md
- Code execution must be enabled (Settings → Capabilities for free/Pro/Max, or organization owner for Team/Enterprise)
- Custom uploaded skills are private to the individual account by default
- Team/Enterprise plans support sharing skills org-wide, but sharing is off by default and requires owner activation

## Cowork specifics

- Cowork reads skills from the same `~/.claude/skills/` path as Claude Code
- There's a reported issue where Cowork's UI does not always rescan `~/.claude/skills/` on startup. Skills copied into the directory via rsync or file copy may not appear in Customize → Skills even though they have valid frontmatter. The workaround is to add them via the Cowork UI. This is not an authoring problem; flag it as a known issue if the user reports it.
- **Observed but undocumented: Cowork ZIP upload may flatten nested subdirectories.** During testing, a skill packaged with files in a `references/` subfolder was installed with those files at the top level of the skill directory, breaking SKILL.md path references like `references/audit-checklist.md`. Root cause uncertain: could be a Cowork-specific upload behavior, an artifact of how the ZIP was packaged, or environment-specific. **Mitigation**: after any UI upload, verify the installed structure matches what SKILL.md expects. If reference paths break, the workaround is either (a) install via direct filesystem copy to `~/.claude/skills/` instead of UI upload, or (b) rewrite SKILL.md to use top-level paths and accept the flat structure. Note that Anthropic's Claude Code docs explicitly support nested subdirectories within a skill (e.g., `skill/examples/sample.md`, `skill/scripts/validate.sh`), so this flattening is unexpected behavior, not a design constraint.
- Cowork supports skill sharing within Team/Enterprise organizations
- Cowork shares the `~/.claude/skills/` directory with Claude Code, so a skill installed for one is installed for both
- Skills in Cowork operate on documents and shape autonomous work, which raises the stakes for description accuracy: a misfiring skill can govern every file Claude creates in a session
- `<available_skills>` in the Cowork session prompt is a subset of what's mounted at `/mnt/skills/`. When auditing in a Cowork session, trust the filesystem at `/mnt/skills/public/`, `/mnt/skills/examples/`, and `/mnt/skills/user/` over the system prompt's `<available_skills>` listing.

## Claude Code specifics

- Personal skills: `~/.claude/skills/<name>/SKILL.md`
- Project skills: `.claude/skills/<name>/SKILL.md` (commit to the repo)
- Plugin skills: `~/.claude/plugins/<plugin>/skills/<name>/SKILL.md` (installed via `/plugin install`; the same skill name can exist both as a local dev copy and an installed-plugin copy — they compete for the trigger)
- The `--add-dir` flag will pick up `.claude/skills/` from added directories
- Slash commands at `.claude/commands/<name>.md` still work; new functionality should be authored as skills
- Skills support `disable-model-invocation: true` to make them user-invoked only (slash command behavior)
- Live change detection: edits to SKILL.md are picked up during a session

## Common portability bugs to flag in the audit

- A skill that writes to a specific path on disk and assumes the file persists. Flag if Claude.ai or Cowork is in scope.
- A skill that runs a local CLI. Flag if Claude.ai is in scope.
- A skill that requires a Python package not in the standard library. Flag with severity High and recommend either listing the requirement explicitly or rewriting with stdlib-only code.
- A skill that uses `~/.claude/skills/<exact-name>` paths internally. The skill should use `${CLAUDE_SKILL_DIR}` (or `${CLAUDE_PLUGIN_ROOT}` for plugin-bundled scripts) so it works regardless of install location.
- A skill that assumes a specific OS. Flag and recommend OS-agnostic alternatives.
