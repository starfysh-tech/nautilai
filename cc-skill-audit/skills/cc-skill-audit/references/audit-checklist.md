# Audit Checklist

This is the working checklist. Apply every relevant check; skip ones that don't apply to the skill at hand.

> **Snapshot, not ground truth.** The frontmatter rules below (field names, character limits, name constraints) reflect Anthropic's docs as last verified 2026-06-18. Before failing a skill on one of them, confirm against the live docs — fetch `https://code.claude.com/docs/en/skills.md` (the parent SKILL.md's "Ground the audit against current docs first" step). If the live docs disagree, trust them and note the divergence.

For each finding, score severity:
- **Blocker**: skill is broken or unsafe
- **High**: skill will underperform
- **Medium**: improvement worth making but not urgent

---

## 1. Frontmatter

### 1.1 Required fields present
- [ ] `name` field present
- [ ] `description` field present
- [ ] Frontmatter opens with `---` and closes with `---` on its own line

**Severity if missing**: Blocker.

### 1.2 `name` field is valid
- [ ] Lowercase letters, numbers, and hyphens only
- [ ] No spaces, underscores, or capital letters
- [ ] Within the documented maximum length (verify the current limit in the live docs)
- [ ] Does not contain the reserved words "anthropic" or "claude"
- [ ] Does not contain XML tags

**Severity if invalid**: Blocker.

### 1.3 `name` field is well-chosen
- [ ] Specific enough to disambiguate from other skills (including publicly published skills that may share a name — a collision means two skills fight for the trigger)
- [ ] Ideally in gerund form (verb + -ing), per Anthropic's authoring best practices: `processing-pdfs`, `auditing-skills`, `writing-commit-messages`. (A house naming convention — e.g. a shared plugin prefix — can reasonably override the gerund preference; treat it as a style choice, not a defect.)
- [ ] Matches the directory name (the directory name is what becomes the command in Claude Code)

**Severity if non-gerund or vague**: Medium.

### 1.4 `description` field is valid
- [ ] Non-empty
- [ ] Within the documented maximum length (this is a hard limit; longer descriptions fail validation — verify the current limit in the live docs)
- [ ] No XML tags

**Severity if invalid**: Blocker.

### 1.5 Optional frontmatter fields
- [ ] If `allowed-tools` is set, it lists tools that actually exist (and only the ones the skill uses — see security check 9)
- [ ] If `disable-model-invocation: true` is set, the skill is meant to be user-invoked only (slash command style). Confirm this matches the user's intent.
- [ ] No unknown frontmatter keys (a typo in a field name will be silently ignored)

**Severity if misconfigured**: High.

### 1.6 Frontmatter fields beyond the core set
Anthropic's documented optional fields have grown over time (`allowed-tools`, `disable-model-invocation`, `license`, and more). Some community guides also recommend fields like `claude_code_only: true`. Rather than freezing a list here:

- [ ] Verify any non-core frontmatter field against the live docs (`https://code.claude.com/docs/en/skills.md`) before flagging it. A field that was "community-only" at this snapshot may now be official.
- [ ] If a field is genuinely undocumented, flag the user: it may be silently ignored by Claude. Recommend documenting platform restrictions in the description and body instead.

**Severity if relying on a genuinely undocumented field**: Medium.

---

## 2. Description

The description is the single most important field in the skill. Audit it harder than anything else.

### 2.1 Includes both what AND when
- [ ] Says what the skill does
- [ ] Says when Claude should use it (trigger phrases, contexts, file types)

A description that only says "what" almost always undertriggers. Per Anthropic's docs, the description must "include both what the Skill does and when to use it."

**Severity if "when" is missing**: High.

### 2.2 Is appropriately "pushy"
Per anthropics/skills (skill-creator/SKILL.md): "Claude has a tendency to undertrigger skills." Counteract this by:
- [ ] Explicitly using phrases like "Use when…" or "Trigger on…"
- [ ] Enumerating user phrases that should match
- [ ] Listing related contexts where Claude should still use the skill even if the user didn't say the exact magic word

**Severity if generic and passive**: High.

### 2.3 Is specific, not vague
Anti-patterns to flag:
- "Handles X" / "Provides Y functionality" / "Helps with Z": too vague
- Descriptions that could apply to ten different skills
- Descriptions written like a job listing rather than a stage direction
- Descriptions that try to cover too many unrelated things (sign of a monolith)

**Severity if vague**: High.

### 2.4 Doesn't promise everything
A description that spans security, performance, code review, deployment, and documentation will not trigger reliably for any of them. The skill should be doing one thing (which can have variants).

**Severity if monolith**: High. Recommend splitting.

### 2.5 Is honest about scope
- [ ] Doesn't claim capabilities the body doesn't deliver
- [ ] Doesn't reference files or scripts that don't exist in the skill folder

**Severity if mismatched**: High.

### 2.6 Passes a trigger test
Don't judge the description by eye alone — test it. Draft four short prompts and predict whether the skill should fire (see `description-patterns.md` for the method):
- [ ] A **direct** request (uses the skill's keywords) fires
- [ ] An **implicit** request (goal matches, no magic words) fires
- [ ] An **alternative phrasing** (synonym a real user types) fires
- [ ] A **should-NOT-fire** nearby request does *not* fire

Report the four prompts with the finding so the user can re-run them after editing.

**Severity if the first three wouldn't fire**: High (undertriggering). **If the fourth would fire**: High (overtriggering).

---

## 3. Body (SKILL.md content after frontmatter)

### 3.1 Length is appropriate
- [ ] Body is concise. Anthropic recommends keeping it short because every line is a recurring token cost once the skill loads.
- [ ] If the body is over ~500 lines, content should move to `references/`. This is a working ceiling from skill-creator, not a hard limit.

**Why it matters**: API users billed per token feel skill bloat directly on the invoice. Subscription users (Pro, Team, Max) feel it as faster rate-limit consumption and shorter sessions before hitting limits. Both audiences benefit from progressive disclosure; the incentive lands differently.

**Severity if bloated**: High if over 500 lines with no `references/`; Medium if over 200 lines with content that clearly belongs in references.

### 3.2 States what to do, not why
- [ ] Instructions are direct and actionable
- [ ] Minimal narration of reasoning, history, or motivation
- [ ] No restating of generic knowledge Claude already has (e.g., what JSON is, how REST works)

**Severity if narrative-heavy**: Medium.

### 3.3 Has clear structure
- [ ] Section headers for distinct phases or topics
- [ ] When to use this skill (if not fully captured in description)
- [ ] The workflow / steps Claude should follow
- [ ] Output format expectations (if applicable)

**Severity if unstructured**: Medium.

### 3.4 Points to bundled resources clearly
If the skill has `references/`, `scripts/`, or `assets/`:
- [ ] SKILL.md tells Claude what's in each bundled file
- [ ] SKILL.md tells Claude when to read each file (Claude will not read them on its own without guidance)
- [ ] File paths in SKILL.md match the actual paths in the folder

**Severity if pointers are missing or wrong**: High (bundled resources won't be used).

### 3.5 Includes a gotchas section (recommended, not required)
A short list of common failure modes Claude hits when running this skill. Anthropic's skill-creator and community guides both emphasize this as the highest-signal section. Write it from real failures, not theoretical ones.

**Severity if missing**: Medium. Recommend adding once the skill has been used enough to surface real failure modes.

### 3.6 Includes a version block (recommended, not required)
Three or four lines at the bottom tracking what changed and when. Useful for skills that get updated.

Example template:
```
## Version
- v1.2 (2026-04-15): Added Gotchas for Stripe API edge cases
- v1.1 (2026-02-03): Tightened description triggers
- v1.0 (2025-12-10): Initial release
```

Only bump versions for real post-release edits, not for build-time iterations during initial authoring.

**Severity if missing**: Medium for skills you maintain; skip for one-shot skills.

---

## 4. Bundled resources

Only apply this section if the skill has subfolders.

### 4.1 Folder structure follows convention
Anthropic's conventional layout (per Skills overview and skill-creator):
- `references/`: documentation Claude loads into context on demand
- `scripts/`: executable code Claude runs (output goes into context, not the script itself)
- `assets/`: files used in output (templates, icons, fonts)

- [ ] Folders use the conventional names
- [ ] Files are in the right folder for their purpose

**Severity if misnamed**: Medium.

### 4.2 Each bundled file has a purpose
- [ ] No orphan files that SKILL.md never references
- [ ] No duplicate content between SKILL.md and bundled files

**Severity if orphan files**: Medium.

### 4.3 Large reference files have a TOC
Per skill-creator: for reference files over ~300 lines, include a table of contents at the top so Claude can decide whether to load further.

**Severity if missing on large file**: Medium.

### 4.4 Scripts are executable and self-contained
- [ ] Scripts have appropriate shebang lines if they're meant to run directly
- [ ] Scripts don't depend on packages that won't be available in the execution environment
- [ ] Scripts use environment variables or relative paths, not hardcoded user-specific paths

**Severity if broken**: Blocker for the script's function; High for the overall skill.

---

## 5. Portability

See `portability-notes.md` for full details. Quick checks:

### 5.1 Works on the surfaces the user cares about
- [ ] If destined for Claude Code: filesystem writes and shell access are fine
- [ ] If destined for Claude.ai: no assumptions about local filesystem persistence beyond the sandbox
- [ ] If destined for Cowork: no shell commands the Cowork environment can't run

**Severity if surface-incompatible**: High for surfaces the user named; Medium otherwise.

### 5.2 No hardcoded user-specific paths
- [ ] No `/Users/<specificname>/` or `C:\Users\<specificname>\` paths
- [ ] Uses `${HOME}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PLUGIN_ROOT}` (for plugin-bundled scripts), or relative paths

**Severity if hardcoded**: High (will break for anyone but the author).

### 5.3 No assumptions about a specific machine
- [ ] Doesn't assume specific tools are installed beyond what's standard
- [ ] If it does require tools, the description or body says so

**Severity if implicit dependencies**: High.

---

## 6. Security

See `security-checks.md` for full details. Quick checks:

### 6.1 No credentials in the skill
- [ ] No API keys, tokens, passwords, or connection strings in SKILL.md or any bundled file
- [ ] References to credentials use environment variables, not literal values

**Severity if credentials present**: Blocker.

### 6.2 No silent safety overrides
- [ ] Skill doesn't disable permission prompts without telling the user
- [ ] Skill doesn't bypass code review or other safety gates
- [ ] If the skill changes safety behavior, it says so explicitly in the description and requires confirmation in the body

**Severity if silent override**: Blocker.

### 6.3 No commercial dependencies disguised as open source
- [ ] If the skill is meant to be shareable, it doesn't require a paid third-party API to function
- [ ] Or it accepts user-supplied keys and says so clearly

**Severity if hidden commercial dependency**: High.

### 6.4 External network access is declared
- [ ] If the skill instructs Claude to fetch from external sources, those sources are documented
- [ ] No instructions to fetch and execute remote code

**Severity if undeclared network calls**: High.
