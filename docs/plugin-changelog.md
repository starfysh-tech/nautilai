# Plugin changelog

Curated, human-written log of **major** changes to nautilai's plugins —
new plugins, new skills/subcommands, conventions adopted, behavior changes a user
would notice. Reverse-chronological.

> **Not the release changelog.** Per-release, per-commit notes are auto-generated
> by release-please in the root [`CHANGELOG.md`](../CHANGELOG.md) from Conventional
> Commits. That file is machine-owned and grouped by commit type across the whole
> linked repo. *This* file is the opposite: hand-curated, organized by plugin, and
> only the changes worth a human skim. Do not hand-edit the root `CHANGELOG.md`.

See [`CLAUDE.md`](../CLAUDE.md) → "Plugin changelog" for when and how to update this.

---

## 2026-06-24

- **Convention: shoals** ([`docs/conventions/shoals.md`](conventions/shoals.md), #11).
  Skills now auto-capture explicit user corrections to a project-local,
  append-only `.claude/shoals/<plugin>.<skill>.md` (committed by default) and read
  them back on the next run.
- **Adopted by:** commitcraft, review-plan, phi-scan, pr-comment-review,
  cc-skill-audit, handoff. **Deliberately skipped:** cc-validate-hooks,
  cc-adoption-audit (one-shot/mechanical — noted in their READMEs).
- **cc-skill-audit:** added checklist item 3.7 (persists user corrections across
  runs) so the pattern is auditable.
