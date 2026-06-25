# Convention: shoals (auto-captured corrections)

> Status: active · Applies to: any nautilai skill that runs repeatedly in a
> user's project and can be corrected mid-run

A **shoal** is a correction the user gave a skill — "no, don't do X / you should
have done Y" — captured so the skill doesn't run aground on the same hazard next
session. SKILL.md is the chart of where to sail; the shoals file marks the
hazards this particular project has already hit.

This is nautilai's take on the "pair every skill with a failure log" pattern. We
make it **automatic and project-local**: the skill captures and reads back its
own shoals with no command, no PR, and no human gate — the git diff is the only
visibility the user needs.

## Where shoals live

```
<user-project-root>/.claude/shoals/<plugin>.<skill>.md
```

- **In the user's project, never the installed plugin dir.** Skills install to a
  managed clone under `~/.claude/plugins/repos/...` that is re-pulled on
  `/plugin update`; writing there would be wiped and would leak one repo's
  hazards into every other repo. Project-local solves both — it persists across
  plugin updates and is scoped to the repo that earned the lesson.
- **One file per skill**, namespaced `<plugin>.<skill>` to avoid collisions
  (e.g. `commitcraft.commitcraft.md`, `review-plan.review-plan.md`).
- **Path is relative to the project root** (the user's CWD), resolved at runtime.
  A skill never hardcodes an absolute path.

## Committed by default

Shoals are **team-shared**: commit the file so a teammate's fresh clone inherits
the project's accumulated hazards. It shows in `git status` and PRs — that
visibility is the audit trail, not a leak. A user who wants per-developer,
invisible shoals may `.gitignore` the path; that's their call, not the default.

> This means "transparent" = the user doesn't *drive* it, not that it's *hidden*.
> A shoals write is always VCS-visible. Skills must never write outside
> `.claude/shoals/`, and installing a plugin that captures shoals is consent to
> the behavior — so the plugin's README must disclose it.

## The entry format

Append-only Markdown. Keep each entry short — a `## title` plus four fields
(trigger, wrong, correct, why):

```markdown
## <short title>
- **Trigger:** when this situation comes up
- **Wrong:** what the skill did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason, so a future run can tell if it's still true
```

## The rules

1. **Append-only.** Never edit or delete an existing entry — even one that looks
   solved. A shoal can resurface after a skill or codebase change. To retire one,
   append `- **Obsolete:** <date> — <reason>` under it; leave the entry.
2. **Dedup on trigger before appending.** If an entry with the same trigger
   exists, don't write a second. The file is a set of hazards, not a log.
3. **Capture only explicit behavioral corrections.** A shoal is "you did X, do Y
   instead" about the skill's *behavior*. It is **not** a passing preference, a
   one-off, or anything the user didn't actually flag. When unsure, don't
   capture — a noisy shoals file is worse than a thin one.
4. **Read back on invocation.** At the start of a run, the skill reads its own
   `.claude/shoals/<self>.md` if it exists and treats the entries as constraints.
   Most projects won't have one yet, so this is a cheap conditional read, not an
   eager load.

## Wiring it into a SKILL.md

Add a short block to the skill body (not the frontmatter):

```markdown
## Shoals (project corrections)

At the start of a run, read `.claude/shoals/<plugin>.<skill>.md` from the project
root if it exists, and honor every entry.

When the user corrects your behavior ("don't do X / do Y instead"), append a
shoal to that file (creating `.claude/shoals/` if needed) using this format.
Append-only; dedup on trigger; capture explicit behavioral corrections only.
See `docs/conventions/shoals.md`.
```

## Which skills should adopt this

- **Good fit:** skills that run repeatedly against the same project and make
  judgment calls a user corrects — `commitcraft`, `review-plan`, `phi-scan`,
  `pr-comment-review`, `pr-review-deep`.
- **Poor fit:** pure one-shot advisory skills with nothing to carry between runs.
  Adopting shoals there just adds an empty-file read. Note the skip in the
  plugin's README rather than shipping a dead convention.

## How this relates to the other conventions

- **#1 finding dispositions / #7 back up before mutating:** a shoal write is an
  automatic write to the user's tree, which would normally be `ask-user`. It's
  allowed without a gate **only** because it is append-only, confined to
  `.claude/shoals/`, and VCS-visible — recoverable by construction. Any write
  that doesn't meet all three is not a shoal write.
- **Findings-first (#2):** capturing a shoal is silent housekeeping — mention it
  in one line ("captured a shoal: …"), don't narrate it.
