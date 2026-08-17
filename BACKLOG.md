# Backlog

Tracked, non-urgent work for the nautilai marketplace and its plugins.

## Repo & docs

Doc surfaces went stale twice in one day — `docs/plugins/wireframe.html` after the
wireframe Mermaid work, then four surfaces (including `docs/conventions/diagrams.md`
itself) after rbac-django's route exposure. Both were caught only because the
maintainer asked "docs updated?", not by any check. The two items below are the
cheap fix and the enforced fix; do them in that order.

- **Couple the plugin changelog to the capability surfaces (CLAUDE.md line).**
  Add to `CLAUDE.md`'s "Plugin changelog" section: *when you add an entry here,
  check `docs/llms.txt` and `docs/plugins/<name>.html` in the same PR — a
  changelog entry means the change is user-visible, which is exactly when those
  go stale.*
  - **Why:** `docs/plugin-changelog.md` is already the human-judgment filter for
    "is this worth a human skim", so touching it is the author declaring the
    change user-visible. That is the moment the other surfaces matter, and no
    such coupling is written down anywhere today — the diagrams convention's
    rule 4 covers diagrams only.
  - **Cost / risk:** one sentence, no machinery. Risk is that prose alone doesn't
    hold, which is what the next item exists for.

- **`check-docs-sync.sh` — CI gate on the same coupling.** A ~10-line script in
  `.github/scripts/`, wired into `validate.yml`: if `docs/plugin-changelog.md`
  changed, require `docs/llms.txt` or a `docs/plugins/*.html` to have changed
  too. Escape hatch: `[docs-ok]` in any commit message on the branch.
  - **Why:** measured against the last 80 commits on `main`, this is the only
    candidate rule with a usable signal. Path-based alternatives are pure noise
    here: *plugin changed → its page changed* fired on 2/2 sampled commits, and
    *`feat`/`fix` touching a plugin → page or `llms.txt`* fired on 4/4 — all
    false positives (bash-4 compat, error-reporting fixes). The changelog-coupled
    rule scored **8 satisfied / 5 flagged**, and the real miss (`e1b8198`) is in
    the flagged set. Several of those five are arguably true positives too.
  - **Cost / risk:** at a ~38% flag rate it must ship with the escape hatch or it
    becomes the check everyone bypasses — the same failure as the DeepSource
    JavaScript analyzer we disabled. Don't build it until the CLAUDE.md line has
    had a chance to fail; one more stale-doc incident is cheap evidence and
    tells us whether enforcement is actually needed.

## CommitCraft

- **Restructure dispatch from one arg-driven skill to plugin commands.**
  Today CommitCraft is a single skill named `commitcraft`, so it surfaces as the doubled
  id `commitcraft:commitcraft` and subcommands ride in as an argument
  (`/commitcraft commit`). Splitting the workflows into plugin commands
  (`commands/commit.md`, `commands/pr.md`, …) would invoke as `/commitcraft:commit`,
  `/commitcraft:pr`, etc. — one namespace level, no name repeat, subcommands mapped to real
  files.
  - **Why:** cleaner invocation and discoverability; removes the cosmetic `:commitcraft`
    repeat.
  - **Cost / risk:** a real refactor of how CommitCraft routes subcommands; the shared
    `AskUserQuestion`-first preamble and execution policy would need to live in each command
    or a shared include. Not worth doing on its own — fold into the next substantive
    CommitCraft change.

## AutoDev

- **Installed-plugin dogfood run.** Run `/autodev` on a low-stakes task from a
  fresh session with autodev installed (v2.9.0+, user scope) — the first
  exercise of the native path every validation run bypassed: skill triggering
  from its description, harness-expanded `${CLAUDE_PLUGIN_ROOT}`,
  `haiku-worker`/`review-gate` agent-type resolution, direct worker completion
  signals in the main session, and the first live review-gate `pass` producing
  `DONE.md`. Findings go into [autodev/tests/SCENARIOS.md](autodev/tests/SCENARIOS.md) as the dogfood-run
  entry, same improve→confirm loop as runs 1–5.
  - **Why:** top-ranked readiness gap (see the [autodev/README.md](autodev/README.md#backlog) backlog) — the
    documented primary path is the one path never validated.
  - **Cost / risk:** one session, one small task; failures are visible, not
    silent (worst case is first-run friction, which is itself the data).

## sentry-hygiene

- **Narrowed to complement the official Sentry plugin, not compete.** After Sentry's
  first-party `sentry` plugin landed, `sentry-hygiene` dropped `triage` and `investigate`
  (subsumed by that plugin's `sentry-fix-issues`, which also bundles the MCP) and now
  ships two repo-only workflows: `audit` and `instrument`. The five originally-deferred
  candidates are **not on our roadmap** — every one is squarely the official plugin's
  territory:
  - alert-rule / monitor review → its `sentry-create-alert`
  - release-health and adoption analysis → its MCP-backed workflows
  - quota / sampling cost tuning → org-level Sentry settings, its domain
  - performance-trace investigation → part of its `sentry-fix-issues`
  - cron monitor setup → its per-SDK setup skills
  - **Why:** building these would re-compete with a first-party plugin that does them
    better. `sentry-hygiene`'s durable value is the two gaps it leaves — auditing an
    existing setup, and the inbound-PII gate. Keep the scope there.
