# CC Skill Audit

Audit existing Claude Code skills against Anthropic's authoring guidance — diagnose under/over-triggering, tighten descriptions, de-bloat bodies, check portability and security, and sweep a skills directory (including installed plugins) for issues.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install cc-skill-audit@nautilai
```

## Use

```text
/cc-skill-audit                       # sweep every installed skill
/cc-skill-audit <skill-name-or-path>  # audit one skill
```

## What it does

Reviews a SKILL.md (or a whole directory of them) against Anthropic's official skill-authoring guidance, then reports findings-first with Blocker / High / Medium severity:

1. **Frontmatter & description** — required fields, name/description validity, and trigger reliability. The description is the trigger, so it's audited hardest — and *tested*: the audit drafts direct / implicit / alternative-phrasing / should-not-fire prompts to catch under- and over-triggering.
2. **Body** — conciseness, structure, progressive disclosure into `references/`, and a gotchas/version block.
3. **Bundled resources** — folder conventions, orphan/missing files, TOCs on large references, script self-containment.
4. **Portability** — across Claude Code, Cowork, and Claude.ai (sandbox vs. full filesystem, shell access, hardcoded paths).
5. **Security** — no hardcoded credentials, no silent safety overrides, no commercial deps disguised as open source, declared network access.

It grounds itself against the live docs at runtime (fetches `code.claude.com/docs/llms.txt`) rather than trusting a frozen snapshot, so it won't fail a skill on a rule that's since changed. In sweep mode it discovers user, project, **and installed-plugin** skills.

This audits *your skills' content*. It complements `claude plugin validate`, which validates plugin *manifests*.

## Shoals (project corrections)

When you correct what this skill flags or how it scores severity, it records the
lesson in `.claude/shoals/cc-skill-audit.cc-skill-audit.md` in your project and
reads it back on the next run — handy for house conventions it shouldn't treat as
defects. The file is append-only and committed by default (teammates inherit it)
— `.gitignore` it if you'd rather keep it per-developer.

## License

MIT
