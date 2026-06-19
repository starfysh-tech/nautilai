# Description Patterns

Read this when fixing a description, when designing a trigger test, when the user asks why a skill is undertriggering, or when scoring description severity in the audit.

## How Claude reads descriptions

At session start, Claude loads only the `name` and `description` of every installed skill into its system prompt. The body of SKILL.md is not loaded until Claude decides the skill is relevant. This means:

- A skill with great instructions and a bad description will not fire
- A skill with a great description fires reliably, then loads the body when it does
- The description is the entire first-pass triggering mechanism

Anthropic's own authoring guide (Skill authoring best practices) makes this point explicit: "The description is critical for skill selection: Claude uses it to choose the right Skill from potentially 100+ available Skills."

## Why skills undertrigger

Per anthropics/skills (skill-creator/SKILL.md): "Claude has a tendency to undertrigger skills -- to not use them when they'd be useful." The skill-creator skill explicitly tells you to write descriptions that are "a little bit pushy" to counteract this.

Common reasons a skill undertriggers:

1. **The description only says what the skill does, not when to use it.** Claude has no signal that a particular user request should activate the skill.

2. **The description uses passive framing.** "A skill for X" or "Handles Y" doesn't tell Claude that a user request matches; it just describes a category.

3. **The description is too narrow.** Listing only one trigger phrase ("use when the user says 'audit my skills'") misses related phrases ("review this SKILL.md", "is this skill any good").

4. **The description is too broad.** A description that covers ten domains will not match any specific request well enough to fire.

5. **The skill duplicates a capability Claude already has.** For simple one-step queries Claude can handle on its own, it may skip the skill regardless of description quality. The skill needs to offer something Claude wouldn't do as well by default.

## Why skills overtrigger

Less common but worth checking:

1. **The description claims broad applicability.** A skill description that says "use whenever the user mentions code" will fire for nearly every request.

2. **Reserved words leak in.** A description that includes "claude" or "anthropic" (which are forbidden in the `name` field but not the `description`) can match unrelated requests.

3. **The skill is one of several overlapping skills.** Two skills with overlapping descriptions will fight for the trigger; the one with the more specific match wins.

## The pattern that works

Per Anthropic's authoring guide, the effective description structure is:

> **[What the skill does in one sentence].** **Use when [specific contexts, phrases, or file types].** **[Optional: explicit trigger list].**

Examples from Anthropic's documentation:

**PDF processing skill:**
> "Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction."

**Excel analysis skill:**
> "Analyze Excel spreadsheets, create pivot tables, generate charts. Use when analyzing Excel files, spreadsheets, tabular data, or .xlsx files."

**Git commit helper:**
> "Generate descriptive commit messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes."

Note the pattern: a sentence describing the action, followed by an explicit "Use when…" clause that enumerates the contexts.

## Pushy descriptions

For skills that consistently undertrigger, follow the skill-creator's pushiness pattern. The example from anthropics/skills:

Weak:
> "How to build a simple fast dashboard to display internal Anthropic data."

Pushy:
> "How to build a simple fast dashboard to display internal Anthropic data. Make sure to use this skill whenever the user mentions dashboards, data visualization, internal metrics, or wants to display any kind of company data, even if they don't explicitly ask for a 'dashboard.'"

The pushy version adds:
- "Make sure to use this skill" (explicit instruction to Claude)
- Enumerated trigger contexts ("dashboards, data visualization, internal metrics")
- A broadening clause ("even if they don't explicitly ask for")

This isn't always necessary. Reserve the pushy style for skills that are demonstrably undertriggering.

## Testing a description (the 4-prompt trigger test)

Don't audit a description by eye alone. The description is the trigger, so test it the way a user would exercise it. Write four short prompts and predict whether the skill *should* fire:

1. **Direct** — a request that uses the skill's own keywords. (Should fire. If it wouldn't, the description is broken.)
2. **Implicit** — the user's goal clearly matches, but they don't use the magic words. (Should fire. If it wouldn't, the description is too literal / too narrow.)
3. **Alternative phrasing** — a synonym or paraphrase a real user might type instead. (Should fire. If it wouldn't, enumerate more trigger contexts.)
4. **Should-NOT-fire** — a nearby request in the same domain that this skill must ignore. (Should *not* fire. If it would, the description is too broad / overtriggering.)

How to use the results:

- Run the four prompts as a thought experiment against the *description text only* (that's all Claude sees at selection time). If you have a live session, you can also test empirically.
- A miss on prompts 1–3 → **undertriggering** finding. Fix by adding the missed phrasing/context to the "Use when…" clause.
- A hit on prompt 4 → **overtriggering** finding. Fix by narrowing the description or adding a "Do not use when…" note to the body.
- Include the four prompts in the audit report so the user can re-run them after editing and confirm the fix.

Example, for a skill that generates conventional-commit messages:

- Direct: "write me a commit message" → fire
- Implicit: "I staged my changes, what should I call this commit?" → fire
- Alternative: "summarize my diff for git" → fire
- Should-NOT-fire: "explain what this commit did" (reading history, not authoring) → do not fire

## Rewriting a description: a small checklist

When rewriting:
1. State the action in one short sentence
2. Add "Use when…" or "Trigger on…" followed by 2-4 specific contexts
3. If the skill covers variants, list them (e.g., "Python, JavaScript, or TypeScript codebases")
4. If the skill should fire on related phrases the user might not use exactly, add a broadening clause
5. Verify total length is under the documented character limit (confirm the current limit in the live docs)
6. Verify no XML tags
7. Run the 4-prompt trigger test above
8. Read it aloud. If it sounds like a job listing, rewrite. If it sounds like a stage direction, ship it.

**Verbs that work well at the start of a description**: run, write, debug, audit, refactor, generate, validate, deploy, review, fix, analyze, extract, build, create, format, organize. These are the verbs Claude hears in user requests, so descriptions that lead with them match request patterns directly. Avoid passive nouns ("A skill for X", "Toolkit for Y", "Resources to help with Z") as the first word.

## Anti-patterns to flag in the audit

- "A skill for X" / "Handles X" / "Provides X functionality": passive, no trigger
- "Helps with X": vague, doesn't tell Claude when
- Descriptions that list domains the skill claims to cover with no specific triggers
- Descriptions that are longer than they need to be; verbosity dilutes the signal
- Descriptions that restate the skill name without adding information
- Descriptions that promise outcomes Claude can already deliver without the skill
