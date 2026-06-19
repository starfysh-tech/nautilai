# Common Failure Modes

Read this when a finding doesn't fit the checklist cleanly, or when the user describes a symptom rather than a problem.

Each cause is paired with an executable fix. If you can't act on a cause from this file, the file has failed and needs editing.

## Symptom: "My skill doesn't fire when I expect it to"

Likely causes, in order of frequency:

1. **The description doesn't include "when".**
   Fix: open SKILL.md, append "Use when [specific trigger phrases or contexts]" to the description. See `description-patterns.md` for the patterns Anthropic recommends, then run the 4-prompt trigger test to confirm.

2. **The description is passive ("A skill for X" / "Toolkit for Y" / "Helps with Z").**
   Fix: rewrite the first sentence to start with an action verb (audit, generate, validate, refactor, deploy, etc.). Keep the result under the documented character limit.

3. **The user's prompt is too simple to need a skill.**
   Fix: not actionable on the skill itself. The skill is working as designed; the prompt class is too simple to trigger any skill. Confirm by testing with a substantive multi-step prompt that matches the description. If it fires there, the skill is fine.

4. **Another skill is winning the trigger.**
   Fix: run a directory sweep (use this skill's sweep mode), identify the competing skill, then either (a) tighten this skill's description to exclude the overlap, (b) tighten the other skill's description, or (c) merge them if they're doing the same thing. Note that an installed-plugin copy and a local dev copy of the *same* skill name will collide this way — dedupe before assuming two unrelated skills are fighting.

5. **The skill isn't registered.**
   Fix: open Customize → Skills in the UI. If missing, re-add via the UI. If present but disabled, toggle on. See the Cowork rescan issue in `portability-notes.md`.

6. **Frontmatter validation failed silently.**
   Fix: run `python3 -c "import yaml,re; m=re.match(r'^---\n(.*?)\n---', open('SKILL.md').read(), re.DOTALL); yaml.safe_load(m.group(1))"` on the file. Check: YAML parses, name is lowercase/hyphens/numbers only, name has no "anthropic"/"claude", description is under the documented character limit.

## Symptom: "My skill fires when I don't want it to"

1. **The description is too broad.**
   Fix: in SKILL.md, replace generic trigger phrases ("for anything code-related") with specific ones ("for Python pytest failures in CI logs"). Remove broadening clauses like "even if they don't explicitly ask".

2. **Trigger phrases match too many contexts.**
   Fix: list every recent false-positive context, then add an "Do not use when [false-positive contexts]" line to the description body (not the frontmatter description).

3. **You meant this skill to be user-invoked only.**
   Fix: add `disable-model-invocation: true` to the frontmatter. The skill will then only fire when explicitly invoked via slash command or `/skill-name` syntax.

## Symptom: "My skill triggers but produces bad output"

1. **The body is bloated (over 500 lines).**
   Fix: move sections that aren't always needed into `references/<topic>.md` files. In SKILL.md, replace the moved content with a one-line pointer: "For [topic], see `references/<topic>.md`. Read it when [specific condition]."

2. **The body restates generic knowledge.**
   Fix: delete every paragraph that teaches something Claude already knows (language syntax, common frameworks, standard patterns). Keep only domain-specific or codebase-specific information. Re-test the skill after each deletion to confirm output quality didn't drop.

3. **The body has no structure.**
   Fix: add H2 headers for each phase of the workflow ("When to use this skill", "Workflow", "Output format", "Gotchas"). Number the steps within each section. Re-test.

4. **The skill references bundled files that don't exist.**
   Fix: run `for f in $(grep -oE 'references/[^[:space:]]+\.md' SKILL.md); do [ -f "$f" ] || echo "MISSING: $f"; done` from the skill directory. Create any missing files or remove the references.

5. **The skill bundles files SKILL.md doesn't reference.**
   Fix: run `ls references/ scripts/ assets/ 2>/dev/null | while read f; do grep -q "$f" SKILL.md || echo "ORPHAN: $f"; done`. Either add pointers to the orphans in SKILL.md (with when-to-read guidance) or delete them.

## Symptom: "My skill works in Claude Code but not Cowork / Claude.ai"

1. **Shell commands.**
   Fix: replace each shell invocation in SKILL.md or bundled scripts with a Python stdlib equivalent. If a shell command is unavoidable, add a conditional: "In Claude Code, run X. Otherwise, return [content] for the user to run manually."

2. **Filesystem persistence assumed.**
   Fix: change "writes [file] to your directory" to "returns [content]; in Claude Code, also writes to [file]". Sandbox surfaces will download the file; Claude Code will write it.

3. **Local CLI tools assumed (git, npm, aws).**
   Fix: gate every CLI invocation behind a capability check or document the dependency in SKILL.md frontmatter or body. For cross-surface skills, provide a fallback path that doesn't require the CLI.

4. **Dynamic context injection used.**
   Fix: `!command` syntax is Claude Code-specific. Replace with explicit instructions to Claude to run the command via the available tools.

## Symptom: "My skill folder is getting too big"

1. **The body is doing the job of `references/`.**
   Fix: identify sections in SKILL.md that are only needed for specific cases (one variant, one workflow path, one edge case). Move each to `references/<case-name>.md`. In SKILL.md, replace with a one-line pointer and the condition under which to read it.

2. **The skill is actually multiple skills.**
   Fix: list the distinct domains the description covers. For each, draft a one-sentence description. If you have three or more, split. Create new skill folders, move relevant body content, write new descriptions. Archive the monolith.

3. **Examples are inline that should be in `assets/`.**
   Fix: move long example outputs, templates, and sample data to `assets/<name>.<ext>`. In SKILL.md, reference by path and tell Claude when to read or use them.

## Symptom: "My skill worked last month and stopped working"

1. **Model behavior shifted.**
   Fix: run a quick eval. Pick 3-5 prompts that previously triggered the skill, send them to the current model, check trigger rate. If under 80%, rewrite the description per `description-patterns.md`.

2. **Description drift.**
   Fix: run `git log -p SKILL.md` (or check the version block) for recent description edits. Revert to the version that worked, or compare to identify which change broke the trigger.

3. **Another skill was installed that now wins the trigger.**
   Fix: run a directory sweep. Find any skill installed since the last working date with an overlapping description. Disambiguate by making one description more specific.

4. **The skill body references files that have moved or been renamed.**
   Fix: run the same "MISSING:" check from "bad output" §4. Restore files or update paths.

## Symptom: "I have a directory of skills and don't know which ones are still good"

This is the directory-sweep case. Fix: invoke this skill with no argument. It runs the full checklist against every installed skill — including installed-plugin skills under `~/.claude/plugins/*/skills/` — and produces a summary table with severity counts per skill. Address blockers first, then high-severity findings. Skills with no findings stay; skills with multiple high findings without an obvious fix should be archived (move to `~/.claude/skills/.archive/`).

## Symptom: "I have so many skills I forget what's in there"

Discoverability collapses around 30 skills (community estimate from authors maintaining 200+ skill corpora). At that scale, descriptions become the index.

Fix: run a directory sweep. For each skill, score the description on searchability: would the words in the description match the phrases you'd use when looking for this skill? If not, rewrite the description to include the search terms you'd actually use.

## Symptom: "Skills that worked six months ago are firing inconsistently now"

Skill rot is real. Community estimates (alirezarezvani/claude-skills, 235-skill corpus) suggest roughly a quarter of a large corpus becomes stale within six months of authoring, even without edits.

Fix: schedule a quarterly directory sweep on the calendar. After every Claude model release, spot-check 3-5 skills used regularly. Tag stale skills for review (add a comment in SKILL.md, e.g., `<!-- review needed: trigger rate dropped after model update -->`). When deleting, archive to `~/.claude/skills/.archive/` rather than removing outright.
