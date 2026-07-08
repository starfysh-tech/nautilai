# Contributing to nautilai

`nautilai` is a Claude Code plugin marketplace. Each plugin is one top-level
directory; there's no root build or test suite.

### Ask a question or discuss

→ [Discussions](https://github.com/starfysh-tech/nautilai/discussions). Issues are
for defects and plugin proposals — questions there get closed and redirected.

### Report a bug or propose a plugin

→ Use the [issue forms](https://github.com/starfysh-tech/nautilai/issues/new/choose).
They ask for the plugin, versions, and repro up front so triage doesn't need a round-trip.

### Add a plugin

- Run `/new-plugin <name>` — it scaffolds the directory, manifest, skill, the
  `marketplace.json` entry, and release-please wiring.
- A plugin's identity spans four surfaces that must stay consistent — `plugin.json`,
  the `marketplace.json` entry, the skill's `SKILL.md` description, and the docs page
  `docs/plugins/<name>.html`. CI enforces most of this.
- Validate before pushing:

  ```bash
  claude plugin validate ./<plugin> --strict
  bash <plugin>/tests/*.test.sh   # if the plugin ships a suite
  ```

- Read the house conventions in [`docs/conventions/`](docs/conventions/README.md)
  before authoring a review/audit skill.

### Commits

- Always go through CommitCraft (`/commitcraft commit`, `/commitcraft pr`) — never
  raw `git commit` / `gh pr create`.
- Conventional Commits, staged file-by-file, **never `--no-verify`**. Pre-commit
  hooks (gitleaks, commitlint) are hard stops, not bypasses.

### AI-assisted contributions

Most of this repo is agent-authored. That's fine. What isn't fine is unreviewed output.

- Run `claude plugin validate --strict` and the plugin's test suite before opening a PR.
- Install the plugin and actually invoke the skill. A skill that has never been run
  is not done.
- Be able to address review comments yourself.
- Keep to one AI-generated PR open at a time.

No disclosure required — we can't verify it and don't ban it. We verify the work instead.
