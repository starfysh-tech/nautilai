---
name: cc-skill-audit
description: Audit existing Claude Code skills against Anthropic's authoring guidance. Use when reviewing a SKILL.md's quality, diagnosing why a skill under- or over-triggers, tightening a description for better trigger reliability, restructuring a bloated SKILL.md, checking a skill for cross-surface portability or security before sharing, or sweeping a skills directory (including installed plugins) for skills that need work — including a scored sweep that ranks every installed skill worst-to-best and writes skill-audit-report.md.
argument-hint: "[skill-name-or-path]"
context: fork
allowed-tools: [Read, Write, Edit, Glob, Grep, Task, Bash(python3:*), Bash(grep:*), Bash(ls:*), Bash(git:*), WebFetch]
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
   - **No argument passed**: sweep mode. Ask scope first, then run the scored sweep (see "Sweep mode" below).
   - **Argument passed**: single-skill mode. The argument is a skill name (e.g., `cc-skill-audit`) or a path (e.g., `~/.claude/skills/cc-skill-audit/SKILL.md`). Resolve the name to a path by checking the standard locations. If the argument doesn't match a known skill, ask before proceeding.

2. **Read the SKILL.md(s).** Always read the file before commenting on it. Do not audit from memory. For sweeps, gather the full skill list and names first — duplicate-name detection needs only names, no file reads.

3. **Run the checks** in `references/audit-checklist.md`. The checklist is grouped by category (frontmatter, description, body, bundled resources, portability, security). Apply every check that's relevant; skip ones that don't apply (for example, the bundled-resources checks if there are no bundled files). Single-skill mode runs this inline.

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

## Sweep mode

Sweep mode runs a scored, ranked audit across every installed skill via a multi-agent Workflow (Haiku scorers → Sonnet fact-checkers → one ranking agent), then offers a deep single-skill audit (the workflow above) on the weakest results.

1. **Ask scope.** Workflow scripts cannot prompt the user, so ask before launching. Use AskUserQuestion:
   - Question: "Which skills should the audit cover?"
   - Options:
     1. **Both (Recommended)** — global `~/.claude/skills/` + project `.claude/skills/`
     2. **Global only** — `~/.claude/skills/`
     3. **Project only** — `<cwd>/.claude/skills/`
     4. **Including installed plugin skills** — extends whichever of the above is chosen with `~/.claude/plugins/*/skills/` and any project-level plugin skill dirs
   - Skip the question only if the user already stated the scope in their request.
   - In Cowork or Claude.ai (no Workflow tool / no local `~/.claude/skills/`): read every `SKILL.md` listed in the session's `<available_skills>` block instead (mount paths typically `/mnt/skills/public/`, `/mnt/skills/examples/`, `/mnt/skills/user/`) and fall back to the batched Task fan-out below — skip Anthropic-shipped skills under `/mnt/skills/public/` by default (include only if the user explicitly asks for built-ins).

2. **Discover SKILL.md files.** Build the file list in-process (adjust roots to the chosen scope; extend with plugin dirs if that option was picked, applying the same skip-Anthropic-built-ins default and duplicate-name note as single-skill sweep discovery):

   ```bash
   python3 -c "
   import os, json, glob
   res=[]
   roots = [('global', os.path.expanduser('~/.claude/skills')), ('project', os.path.join(os.getcwd(), '.claude/skills'))]
   for label, root in roots:
       if not os.path.isdir(root): continue
       for dirpath, dirs, files in os.walk(root):
           if 'SKILL.md' in files:
               res.append({'scope': label, 'path': os.path.join(dirpath, 'SKILL.md')})
   plugin_globs = [os.path.expanduser('~/.claude/plugins/*/skills/*/SKILL.md'),
                   os.path.join(os.getcwd(), '*/skills/*/SKILL.md')]
   for pat in plugin_globs:
       for p in glob.glob(pat):
           res.append({'scope': 'plugin', 'path': p})
   print(json.dumps(res))
   "
   ```

   Trim the `roots` / `plugin_globs` lists to the chosen scope before running
   (e.g. drop `plugin_globs` unless the plugin option was picked; the
   `<cwd>/*/skills/` glob only applies when the project itself is a plugin
   repo). Dedup paths that appear under more than one root.

   If the list is empty for the chosen scope, report that and stop — do not launch the workflow.

3. **Ground against current docs first.** Reuse the "Ground the audit against current docs first" fetch above (one fetch here, never per-agent) and distill it into a short `docs_rules` block: the frontmatter/description rules relevant to scoring (required fields, `name` constraints, the description character limit), in plain text. If the fetch is unavailable, pass an empty string and note the snapshot caveat in the report, matching that section's wording.

4. **Launch the workflow.**

   ```
   Workflow({
     scriptPath: "${CLAUDE_PLUGIN_ROOT}/skills/cc-skill-audit/scripts/workflow.js",
     args: { skills: [ {"scope": "global", "path": "..."}, ... ], docs_rules: "..." }
   })
   ```

   The script tolerates `args` arriving as a JSON string (it parses defensively), but pass a real object. Never hardcode a path in place of `${CLAUDE_PLUGIN_ROOT}` — the install cache path changes on every plugin update.

5. **Deliver the report.** (Workflow path; on the fallback below, the parent assembles the same report from the subagent returns instead.) When the workflow completes, its return value is `{ report, results }`:
   - Read the full result from the task output file referenced in the completion notification (the notification summary is truncated). It is a JSON object; the report markdown is at `.result.report`.
   - Write `report` verbatim to `skill-audit-report.md` in the current working directory (ask before overwriting if the file exists and wasn't produced by this skill).
   - Summarize for the user: average scores, frontmatter failure count, the 3-5 weakest skills, and the cross-set patterns.
   - Offer to run this skill's deep single-skill audit workflow (steps 1-9 above) on the bottom 3-5 skills.

6. **Fallback — no Workflow tool.** If the Workflow tool is unavailable in this environment, fall back to a batched Task fan-out that preserves the scored deliverable: spawn parallel subagents (Task, `general-purpose`, model: haiku) in batches of ~5 skills each. Each subagent reads its batch's SKILL.md files, applies the mechanical checklist from `references/audit-checklist.md` (with the `docs_rules` block from step 3 pasted into its prompt), and returns per skill: clarity 1-5, frontmatter pass/fail, trigger quality 1-5, the single top fix, and severity-tagged findings — with disk evidence for every factual claim. The parent then does the judgment synthesis (trigger-overlap analysis, description rewrites, duplicate-name detection), spot-checks each batch's factual claims against disk (this replaces the workflow's Sonnet verify phase — do not skip it), ranks worst-to-best, and writes `skill-audit-report.md` per step 5, marking it: "fallback run — scores are self-reported by cheap scorers without independent verification; treat as an upper bound." Cheap scorers grade leniently (a uniform 4/4 trigger column across a whole set is a calibration smell, not a clean bill).

### Notes

- Three phases inside the workflow: Haiku scorers (cheap) → Sonnet fact-checkers (one per skill, verify every factual claim against `ls -laR` of the skill dir) → one ranking agent on the session model. The Sonnet verify phase catches hallucinated missing-file claims from cheap scorers — do not remove it.
- Typical run: ~30 skills ≈ 61 agents, several minutes wall clock.
- The journal (`<transcriptDir>/journal.jsonl`) flushes lazily — if the output file looks empty right at completion, wait a few seconds and re-read.

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

These are the principles the audit checklist operationalizes; `references/audit-checklist.md` and `references/description-patterns.md` operationalize the rest. Keep them in mind when judging severity and writing recommendations.

- **The description is the trigger.** Claude pre-loads only `name` and `description` into the system prompt; the body loads only once the skill becomes relevant. Audit the description harder than anything else, and test it (workflow step 4).
- **Skills tend to undertrigger** — bias descriptions to be explicit and "pushy" ("use this skill when…") rather than reading like a job listing.
- **Conciseness in the body matters** — the body is a recurring token cost loaded whole on every trigger; ~500 lines is the working ceiling, long material belongs in `references/`.

## What to read when

- `references/audit-checklist.md`: read this every time. It is the working checklist for the audit.
- `references/description-patterns.md`: read when fixing a description, designing trigger tests, or when the user asks why a skill is undertriggering.
- `references/portability-notes.md`: read when auditing a skill that will run across surfaces, or when the user mentions Cowork or Claude.ai.
- `references/security-checks.md`: read when auditing a skill from an external source, or when the user mentions sharing the skill.
- `references/common-failure-modes.md`: read when a finding doesn't fit the checklist cleanly, or when the user describes a symptom rather than a problem.

## Gotchas

- **Verify documented-field claims against live docs.** The frontmatter rules in `references/audit-checklist.md` are a snapshot. Before flagging a field as "undocumented" or citing the description character limit, confirm against `https://code.claude.com/docs/en/skills.md` (see "Ground the audit against current docs first"). Don't fail a skill on a rule this skill has outgrown.
- **Reserved words in the name field.** "anthropic"/"claude" in a `name` is a claude.ai/Agent-Skills packaging rule; Claude Code's own frontmatter table documents no name constraints (`name` is optional and defaults to the directory name). Flag it for cross-surface skills, downgrade to Medium for Claude Code-only ones; check the live docs for current limits.
- **When installed as a plugin, sweep mode can find this skill twice.** This skill ships inside the `cc-skill-audit` plugin (`~/.claude/plugins/*/skills/cc-skill-audit/`). If the user also keeps a standalone `~/.claude/skills/cc-skill-audit/`, sweep mode will discover both and may report a self-collision. That's expected — note it as a duplicate and don't audit the two copies as if they were unrelated skills.
- **Cowork and Claude.ai surface gotchas** (ZIP upload flattening, Cowork's rescan behavior, `<available_skills>` being a disk subset, Claude.ai's zip packaging requirement) live in `references/portability-notes.md` — read it before auditing a skill that targets either surface.
- **A "monolith" skill that tries to do everything won't trigger reliably for any one thing.** If the description spans multiple unrelated domains, recommend splitting.
- **Don't audit from memory.** Always read the file before commenting. The file is the ground truth, not what the user said about the file.
- **Don't rewrite without confirmation for judgment calls.** Fixing invalid YAML is mechanical. Rewriting a description is a judgment call. Confirm the direction first.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/cc-skill-audit.cc-skill-audit.md` from
the project root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — what you flag (e.g. a house naming
convention you shouldn't treat as a defect), or how you score severity — append a
shoal to that file (creating `.claude/shoals/` if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger**. Capture only explicit behavioral
corrections, not passing preferences. Mention the capture in one line; don't
narrate it.

## Version

- v1.2 (2026-07-08): Merged the personal `skill-audit` scorecard tool into sweep mode as a scored, ranked Workflow (Haiku score → Sonnet verify → rank), grounded against live docs, writing `skill-audit-report.md`; batched Task fan-out kept as the fallback when the Workflow tool is unavailable. Post-validation fixes from a clean-agent run: plugin-scope discovery is real code (was a comment), the fallback now produces the scored report with a scores-are-an-upper-bound caveat and a mandatory parent fact-check pass, and the frontmatter snapshot re-verified against live docs (name optional, description recommended, 1,536-char listing cap; reserved-word rule scoped to cross-surface packaging).
- v1.1 (2026-06-18): Packaged as the `cc-skill-audit` plugin (renamed from the personal `audit-skills` skill to avoid a public name collision). Added a runtime docs-anchor step (fetch `llms.txt` instead of trusting frozen snapshots), trigger-testing in the audit workflow, and installed-plugin skill discovery in sweep mode. Generalized security examples (removed private project context).
- v1.0 (2026-05-12): Initial release. Grounded in Anthropic's Skills overview, Skill authoring best practices, and skill-creator (anthropics/skills repo). Community patterns from external authoring guides incorporated where they don't conflict with official guidance, and flagged where they go beyond official docs.
