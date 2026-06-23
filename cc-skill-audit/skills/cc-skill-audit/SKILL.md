---
name: cc-skill-audit
description: Audit existing Claude Code skills against Anthropic's authoring guidance. Use when reviewing a SKILL.md's quality, diagnosing why a skill under- or over-triggers, tightening a description for better trigger reliability, restructuring a bloated SKILL.md, checking a skill for cross-surface portability or security before sharing, or sweeping a skills directory (including installed plugins) for skills that need work.
argument-hint: "[skill-name-or-path]"
allowed-tools: [Read, Edit, Glob, Grep, Bash(python3:*), Bash(grep:*), Bash(ls:*), Bash(git:*), WebFetch]
---

# Auditing Skills

Review existing skills against Anthropic's official authoring guidance. Optimized for the audit case: a SKILL.md file (or a directory of them) already exists and the user wants to know what's working, what's broken, and what to change.

This skill assumes Anthropic's official guidance as the ground truth (Skills overview, Skill authoring best practices, skill-creator). It also incorporates community patterns where they don't conflict with official guidance. Where community claims go beyond the official docs, this skill calls them out so the user can decide.

## Ground the audit against current docs first

This skill's embedded guidance is a **snapshot** (see `## Version`), not live ground truth. Claude Code's skill model changes; frontmatter fields, limits, and surfaces get added or renamed. Before reporting findings that hinge on a documented detail (frontmatter fields, the description character limit, supported surfaces), fetch the canonical docs index and verify:

- Fetch `https://code.claude.com/docs/llms.txt` (the self-updating docs index) and, when a specific claim is at stake, the linked Skills page (`https://code.claude.com/docs/en/skills.md`).
- If a check in `references/` contradicts the live docs (e.g. a field this skill calls "undocumented" is now documented), **trust the live docs** and note the divergence in the report. Don't fail a skill on a stale rule.
- If the fetch is unavailable (offline, sandboxed surface), proceed with the snapshot but say so: "guidance anchored to this skill's 2026-06-18 snapshot; could not verify against live docs."

## Scope

In scope:

- Claude Code project skills (`.claude/skills/<name>/SKILL.md`)
- Claude Code user skills (`~/.claude/skills/<name>/SKILL.md`)
- Claude Code plugin skills (`~/.claude/plugins/*/skills/<name>/SKILL.md` and a project's plugin dirs)
- Cowork personal skills (same `~/.claude/skills/` path as Claude Code)
- Claude.ai uploaded skills (same SKILL.md format, packaged as a zip)

Out of scope:

- Authoring a brand new skill from scratch (use skill-creator instead)
- Slash commands in `.claude/commands/` (they still work, but skills are the path forward)
- MCP server authoring

## When to use this skill

Trigger this skill when the user wants to:

- Audit one or more existing skills against current Anthropic guidance
- Diagnose why a skill is not triggering when expected, or is triggering when it shouldn't
- Tighten or rewrite a description for better trigger reliability
- Restructure a SKILL.md that has grown bloated, including moving content into `references/`
- Check a skill for portability across Claude Code, Cowork, and Claude.ai
- Sweep a `~/.claude/skills/`, `.claude/skills/`, or installed-plugin skills directory for skills that need work

## The audit workflow

Run the audit in this order. Stop after any step where the user wants to discuss findings before continuing.

1. **Determine the target.**
   - **No argument passed**: sweep mode. Audit every available skill. Sources:
     - In Claude Code: read every `SKILL.md` under `~/.claude/skills/`, (if in a project) `.claude/skills/`, and installed plugins at `~/.claude/plugins/*/skills/` plus any project-level plugin skill dirs. When the same skill name appears both as a local dev copy and an installed-plugin copy, note the duplicate (they'll compete for the trigger) rather than auditing each in isolation.
     - In Cowork or Claude.ai: read every `SKILL.md` listed in the session's `<available_skills>` block. Mount paths are typically `/mnt/skills/public/`, `/mnt/skills/examples/`, and `/mnt/skills/user/`.
     - Skip Anthropic-shipped skills under `/mnt/skills/public/` by default; they're maintained by Anthropic and unlikely to need user fixes. Include them only if the user explicitly asks ("audit all skills including built-ins").
   - **Argument passed**: single-skill mode. The argument is a skill name (e.g., `cc-skill-audit`) or a path (e.g., `~/.claude/skills/cc-skill-audit/SKILL.md`). Resolve the name to a path by checking the standard locations. If the argument doesn't match a known skill, ask before proceeding.

2. **Read the SKILL.md(s).** Always read the file before commenting on it. Do not audit from memory. For sweeps, read all files first, then audit; do not interleave reads and reports.

3. **Run the checks** in `references/audit-checklist.md`. The checklist is grouped by category (frontmatter, description, body, bundled resources, portability, security). Apply every check that's relevant; skip ones that don't apply (for example, the bundled-resources checks if there are no bundled files).

4. **Test the triggers.** The description is the trigger, so don't just judge it by eye — test it. For each audited skill, draft 4 short prompts and predict whether the skill *should* fire:
   - one **direct** request (uses the skill's own keywords),
   - one **implicit** request (the user's goal matches, but they don't use the magic words),
   - one **alternative phrasing** (a synonym a real user might type),
   - one **should-NOT-fire** case (a nearby request the skill must ignore).
   If the description wouldn't plausibly fire on the first three, that's an under-triggering finding; if it would fire on the fourth, that's an over-triggering finding. Report the test prompts alongside the description finding so the user can re-run them. See `references/description-patterns.md`.

5. **Score severity.** Use three levels:
   - **Blocker**: the skill is broken or unsafe (invalid YAML, hardcoded secrets, name collision with reserved words, missing required fields)
   - **High**: the skill will underperform (vague description, undertriggering pattern, bloated body, no clear trigger conditions)
   - **Medium**: improvements that matter but aren't urgent (gerund naming, version block, missing gotchas section)

6. **Report findings** using the format in "Output format" below. Show the user the problems, the reasoning, and the recommended fix. Do not rewrite the skill yet.

7. **Confirm direction with the user.** Some fixes are mechanical (fix YAML, add a missing field). Others involve judgment (rewriting a description, splitting a monolith). Ask before doing the judgment ones. For sweeps, ask which skill the user wants to address first; don't bulk-edit.

8. **Apply fixes.** Edit the SKILL.md in place if the user confirms. For larger restructuring (splitting into references/, splitting a monolith into multiple skills), present a plan before changing files.

9. **Verify after editing.** Re-read the file. Confirm the YAML still parses. Confirm the description still fits within the documented frontmatter character limit.

## Finding dispositions

Severity (above) is *how bad*; disposition is *what you may do about it* (nautilai
convention). Each finding is one of: **auto-fix** — mechanical SKILL.md fixes (YAML,
a missing field) applied in place; **report** — clean skills and the findings list;
**ask-user** — judgment calls (description rewrites, monolith splits, anything in
step 7). Never apply an `ask-user` fix on your own — surface it and wait (step 7).

## Output format

Default to **findings-first** reporting. Show only what's wrong and what to do about it. Do not list categories that have no findings.

### Clean skill (zero findings)

Single line:

```
✓ skill-name: no findings. <body line count> lines, <description char count>/<limit> chars. Ready to use.
```

That's the entire audit output. Do not pad with category headers, principle restatements, or "I checked X and Y" narration.

### Skill with findings

Lead with a one-line verdict, then list findings grouped by severity (Blocker first, then High, then Medium). Each finding gets one line: severity, what's wrong, the fix.

```
skill-name: <N> blocker(s), <N> high, <N> medium

Blockers:
- <what's wrong>. Fix: <action>.

High:
- <what's wrong>. Fix: <action>.

Medium:
- <what's wrong>. Fix: <action>.

Recommended order:
1. <fix>
2. <fix>
```

Omit any severity section that has zero findings. If the user asks "what did you check?", then show the categories. Default is don't pre-emptively justify.

### Directory sweep

Summary table first. One row per skill. Columns: name, blockers, high, medium, verdict (Ready / Fix / Rewrite / Remove). Then drill into each skill with findings, in the single-skill format above. Skills with zero findings get one line each in the table and no further treatment.

### What not to do

- Do not write "No issues" for every clean category. The absence of a finding is the absence of output.
- Do not restate principles from the checklist in the report. The user knows what the checklist contains.
- Do not narrate the audit process ("I read the file, then I checked X…"). Show the result.
- Do not pad with validation commentary ("the skill held up well", "structure is clean"). If there are no findings, say so in one line and stop.

## Key principles to enforce

These are the principles the audit checklist operationalizes. Keep them in mind when judging severity and writing recommendations.

**The description is the trigger.** Per Anthropic's authoring guide, Claude pre-loads only the `name` and `description` from every installed skill into the system prompt. The body of SKILL.md is read only when a skill becomes relevant. A skill with a perfect body and a vague description will not fire. Audit the description harder than anything else, and test it (workflow step 4).

**Skills tend to undertrigger.** Anthropic's own skill-creator skill notes that Claude has a tendency to undertrigger skills. Descriptions should be a little "pushy": explicitly say "use this skill when…" and enumerate the user phrases or contexts that should trigger it. A description that reads like a job listing rarely fires; one that reads like a stage direction does.

**Conciseness in the body matters.** Once the body loads, every line is a recurring token cost. Anthropic recommends keeping the body concise; ~500 lines is the working ceiling. Long reference material belongs in `references/` and should be loaded on demand. State what to do, not why.

**Don't restate what Claude already knows.** A skill that re-teaches generic syntax or generic patterns is dead weight. The skill is a senior practitioner whispering "watch out for this in our codebase / our domain / this specific workflow."

**Progressive disclosure is real architecture.** A skill folder should match this shape when bundled resources exist:

```
skill-name/
├── SKILL.md            (required)
├── references/         (loaded by Claude on demand)
├── scripts/            (executed; not loaded into context unless Claude reads them)
└── assets/             (templates, fonts, images used in output)
```

If the body of SKILL.md is reproducing content that should be in `references/`, flag it.

**Portability across surfaces.** Claude Code, Cowork, and Claude.ai all read the same SKILL.md format, but the execution environments differ. See `references/portability-notes.md`. Flag anything that breaks one surface.

**Security comes first.** No hardcoded credentials, no skills that override safety defaults silently, no commercial APIs disguised as open source. See `references/security-checks.md`.

## What to read when

- `references/audit-checklist.md`: read this every time. It is the working checklist for the audit.
- `references/description-patterns.md`: read when fixing a description, designing trigger tests, or when the user asks why a skill is undertriggering.
- `references/portability-notes.md`: read when auditing a skill that will run across surfaces, or when the user mentions Cowork or Claude.ai.
- `references/security-checks.md`: read when auditing a skill from an external source, or when the user mentions sharing the skill.
- `references/common-failure-modes.md`: read when a finding doesn't fit the checklist cleanly, or when the user describes a symptom rather than a problem.

## Gotchas

- **Verify documented-field claims against live docs.** The frontmatter rules in `references/audit-checklist.md` are a snapshot. Before flagging a field as "undocumented" or citing the description character limit, confirm against `https://code.claude.com/docs/en/skills.md` (see "Ground the audit against current docs first"). Don't fail a skill on a rule this skill has outgrown.
- **Reserved words in the name field.** The `name` must not contain "anthropic" or "claude". Hyphens and lowercase only; check the current max-length limit in the live docs.
- **When installed as a plugin, sweep mode can find this skill twice.** This skill ships inside the `cc-skill-audit` plugin (`~/.claude/plugins/*/skills/cc-skill-audit/`). If the user also keeps a standalone `~/.claude/skills/cc-skill-audit/`, sweep mode will discover both and may report a self-collision. That's expected — note it as a duplicate and don't audit the two copies as if they were unrelated skills.
- **Cowork ZIP upload may flatten nested subdirectories (observed, not documented).** During testing in 2026, a skill packaged with files in `references/` was installed with those files at the top level. Anthropic's Claude Code docs explicitly support nested subdirectories within a skill, so this is unexpected behavior, not a design constraint. After any UI upload, verify the installed structure matches SKILL.md's path references. See `references/portability-notes.md` for mitigations.
- **Cowork doesn't always rescan `~/.claude/skills/` on startup.** There's a reported issue where Cowork loads only previously registered skills, not every skill in the directory. If the user reports a skill missing from Cowork's UI but present in Claude Code, that's the cause. The fix is on Anthropic's side; the workaround is to re-add via the Cowork UI. Do not treat this as a skill authoring problem.
- **`<available_skills>` in Cowork is a subset of disk.** When sweeping in a Cowork session, audit from `/mnt/skills/public/`, `/mnt/skills/examples/`, and `/mnt/skills/user/` on disk rather than from the system prompt's `<available_skills>` listing. The two don't always match.
- **Claude.ai uploads are zip files of the skill folder.** If the user is heading to Claude.ai, the deliverable is a zip, not a folder. Validate that the zip contains exactly one top-level folder containing SKILL.md.
- **A "monolith" skill that tries to do everything won't trigger reliably for any one thing.** If the description spans multiple unrelated domains, recommend splitting.
- **Don't audit from memory.** Always read the file before commenting. The file is the ground truth, not what the user said about the file.
- **Don't rewrite without confirmation for judgment calls.** Fixing invalid YAML is mechanical. Rewriting a description is a judgment call. Confirm the direction first.

## Version

- v1.1 (2026-06-18): Packaged as the `cc-skill-audit` plugin (renamed from the personal `audit-skills` skill to avoid a public name collision). Added a runtime docs-anchor step (fetch `llms.txt` instead of trusting frozen snapshots), trigger-testing in the audit workflow, and installed-plugin skill discovery in sweep mode. Generalized security examples (removed private project context).
- v1.0 (2026-05-12): Initial release. Grounded in Anthropic's Skills overview, Skill authoring best practices, and skill-creator (anthropics/skills repo). Community patterns from external authoring guides incorporated where they don't conflict with official guidance, and flagged where they go beyond official docs.
