# nautilai

> **nau·ti·lai** — a [Starfysh](https://starfysh.net) marketplace of Claude Code plugins:
> AI coding agents, skills, and commands.

## The name

*nautilai* layers a few meanings, on purpose:

- **nautilus + AI** — the spiral-shelled cephalopod with intelligence woven in; the
  navigator of the deep, here to navigate your codebase.
- **"many nautiluses"** — a playful (and gleefully incorrect) faux-Latin plural, the way
  *nautilus → nautili* might tempt you to say it out loud. This repo is a *collection*, so
  the plural fits: one shell per plugin.
- **nautical + lai** — a sea shanty for shipping software; tools that ride the
  [starfysh](https://github.com/starfysh-tech) tide.

Say it however feels right. They all point at the same thing: a growing reef of
well-crafted tools.

## Install a plugin

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install <plugin>@nautilai
```

After installing, reload plugins if prompted, then invoke the plugin's skill.

## Plugins

| Plugin | Description | Install | Docs |
|---|---|---|---|
| **commitcraft** | AI git workflow toolkit — conventional commits, issue validation, PR creation, and release guidance. | `/plugin install commitcraft@nautilai` | [commitcraft/](./commitcraft/README.md) |
| **relay** | Session continuity for Claude Code: transcript-grounded handoff documents that a fresh session picks up automatically. Ships the handoff skill. | `/plugin install relay@nautilai` | [relay/](./relay/README.md) |
| **cc-adoption-audit** | Audit your Claude Code setup against available features — surface what you're not using but should, setup gaps, and recently shipped features you haven't adopted. | `/plugin install cc-adoption-audit@nautilai` | [cc-adoption-audit/](./cc-adoption-audit/README.md) |
| **pr-comment-review** | Process and address review comments on the current PR — fetch threads, categorize, implement fixes behind approval gates, push, and reply inline. | `/plugin install pr-comment-review@nautilai` | [pr-comment-review/](./pr-comment-review/README.md) |
| **cc-validate-hooks** | Validate the local Claude Code hooks configuration in settings.json and settings.local.json (project and user) — report schema errors, invalid event names, malformed matchers, and bad hook fields, with an optional `--fix`. | `/plugin install cc-validate-hooks@nautilai` | [cc-validate-hooks/](./cc-validate-hooks/README.md) |
| **cc-skill-audit** | Audit existing Claude Code skills against Anthropic's authoring guidance — diagnose under/over-triggering, tighten descriptions, de-bloat bodies, and sweep a skills directory (including installed plugins) for issues. | `/plugin install cc-skill-audit@nautilai` | [cc-skill-audit/](./cc-skill-audit/README.md) |
| **phi-scan** | Scan a repo for Protected Health Information (PHI under HIPAA Safe Harbor) — SSNs, emails, phones, IPs, dates, restricted ZIPs — then AI-triage findings to filter false positives. Optional Django/React OWASP grep pass when that stack is detected. | `/plugin install phi-scan@nautilai` | [phi-scan/](./phi-scan/README.md) |
| **review-plan** | Adversarially validate an implementation plan against the actual codebase before building — surface risks, breaking changes, gaps, and simplifications, then write findings back into the plan. Built-in agents by default; taps review/Codex plugins when installed. | `/plugin install review-plan@nautilai` | [review-plan/](./review-plan/README.md) |
| **pr-review-deep** | Rigorous, evidence-based code-quality review of a branch or PR — abstraction design, type/boundary contracts, and behavior-preserving structural simplification. Proposes high-leverage restructurings with cited evidence; never performs them or expands scope. | `/plugin install pr-review-deep@nautilai` | [pr-review-deep/](./pr-review-deep/README.md) |
| **rbac-django** | Audit a Django/DRF + React codebase for RBAC gaps (missing permission classes, tenant-isolation leaks, IDOR, write-side gaps), threat-model the findings into ranked attacker abuse cases, then generate prioritized remediation playbooks and GitHub issues. | `/plugin install rbac-django@nautilai` | [rbac-django/](./rbac-django/README.md) |
| **frontend-review** | Audit a React + Tailwind frontend for architecture and design-token health — component size, prop drilling, duplicate-primitive reuse, folder organization, and Tailwind token violations. Auto-detects the source root; findings cite file:line. | `/plugin install frontend-review@nautilai` | [frontend-review/](./frontend-review/README.md) |
| **wireframe** | Create low-fidelity wireframes for UI planning — ASCII layouts, wiremd interactive prototypes, or Mermaid diagrams for tickets. Use before writing components to sketch structure, flows, and states. | `/plugin install wireframe@nautilai` | [wireframe/](./wireframe/README.md) |
| **dep-review** | Evaluate Dependabot PRs with AUTO-MERGE / MERGE / SKIP / INVESTIGATE verdicts grounded in the PR diff and codebase usage. Low-risk patch / minor-dev-dep bumps that pass CI auto-merge; other merges and closes gate behind approval. | `/plugin install dep-review@nautilai` | [dep-review/](./dep-review/README.md) |
| **github-issue-auditor** | Audit a GitHub repo's issues for cleanup — fuzzy-matched duplicates, orphaned sub-issues, unlabeled or stale items, and inconsistent labels against the repo's own auto-detected taxonomy. Read-only by default; any mutation is opt-in behind an approval gate. | `/plugin install github-issue-auditor@nautilai` | [github-issue-auditor/](./github-issue-auditor/README.md) |
| **autodev** | Bounded autonomous development loop — scripted worktree lanes, fast worker subagents, objective script-based verification, and a hard 3-failure escalation to the user. | `/plugin install autodev@nautilai` | [autodev/](./autodev/README.md) |
| **sentry-hygiene** | Audit a repo's Sentry setup against official SDK docs and instrument capture behind a hard PII boundary — including what the SDK attaches on its own. Complements the official Sentry plugin, which owns SDK setup and issue-fixing. | `/plugin install sentry-hygiene@nautilai` | [sentry-hygiene/](./sentry-hygiene/README.md) |

_More plugins will surface here over time._

## Repository layout

```text
nautilai/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace catalog (lists every plugin)
├── commitcraft/              # One plugin = one top-level directory
│   ├── .claude-plugin/plugin.json
│   ├── skills/ scripts/ templates/
│   └── README.md
├── relay/                    # Each plugin is self-contained
│   ├── .claude-plugin/plugin.json
│   ├── skills/handoff/SKILL.md
│   └── README.md
├── cc-adoption-audit/        # Reframed adoption audit
│   ├── .claude-plugin/plugin.json
│   ├── skills/cc-adoption-audit/SKILL.md
│   └── README.md
├── pr-comment-review/        # Addresses PR review comments
│   ├── .claude-plugin/plugin.json
│   ├── skills/pr-comment-review/SKILL.md
│   └── README.md
├── cc-validate-hooks/        # Validates local hooks config
│   ├── .claude-plugin/plugin.json
│   ├── skills/cc-validate-hooks/SKILL.md
│   └── README.md
├── cc-skill-audit/           # Audits skills against authoring guidance
│   ├── .claude-plugin/plugin.json
│   ├── skills/cc-skill-audit/SKILL.md + references/
│   └── README.md
├── phi-scan/                 # Scans for PHI (HIPAA) + optional OWASP
│   ├── .claude-plugin/plugin.json
│   ├── skills/phi-scan/SKILL.md + references/
│   ├── scripts/phi_check.py
│   └── README.md
├── review-plan/              # Validates a plan against the codebase
│   ├── .claude-plugin/plugin.json
│   ├── skills/review-plan/SKILL.md + references/
│   └── README.md
└── README.md                 # You are here
```

Each plugin is self-contained in its own directory with a `.claude-plugin/plugin.json`
manifest. The marketplace catalog at `.claude-plugin/marketplace.json` points at each one
by relative path.

## Contributing a plugin

1. Create a top-level directory named for the plugin (kebab-case).
2. Add `.claude-plugin/plugin.json` and the plugin's components (`skills/`, `commands/`,
   `agents/`, `hooks/`, etc.) at the plugin root.
3. Reference any bundled scripts, binaries, or config with `${CLAUDE_PLUGIN_ROOT}` — never
   a hardcoded path, since the install cache path changes on every update.
4. Register the plugin in `.claude-plugin/marketplace.json`.
5. Validate before pushing: `claude plugin validate ./<plugin> --strict`.
6. Follow the house [conventions](docs/conventions/README.md) — including the
   [finding-dispositions](docs/conventions/finding-dispositions.md) standard for
   review/audit skills — or note a deliberate exception in the plugin's README.

## License

MIT — see [LICENSE](./LICENSE).
