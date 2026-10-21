# Tech Due Diligence

Technical due diligence for any git repo, in any language or stack. One run produces one
report where every finding cites the code it is about.

## Install

```text
/plugin install tech-due-diligence@nautilai
```

## Use

```text
/tech-due-diligence [repo-path] [--mode owner|buyer] [--claims file] [--allow-accounts] [--quick] [--out report.md]
```

- `--mode owner` (default): you own the repo. The report ends in an ordered fix list.
- `--mode buyer`: you are evaluating someone else's repo. The report opens with an investment summary: a verdict (proceed, proceed with conditions, do not proceed without remediation, or no opinion on the product when the repo is a deployment kit, SDK, or other side component), the top 5 risks with business impact, deal impact (`blocker`, `price`, `post-close`), and an estimated remediation size (S/M/L), the conditions to close, and the limits of the opinion. The body has no file paths; evidence, Low findings, and method are appendices.
- `--claims <file>`: a document with the seller's or team's claims about the technology. Each claim gets a verdict: supported, partly supported, contradicted, or unverifiable from the repo.
- `--allow-accounts`: allow read-only queries to the repo's hosting and deploy accounts (for example branch protection through `gh api`). Without it, the skill reads only the local checkout.
- `--quick`: secrets, dependencies, and licenses only.
- `--out`: report path. The default is `tech-due-diligence-<repo>-<date>.md` in the current directory. In buyer mode, when the current directory is inside the audited repo, the default is the repo's parent directory.

## What it does

1. **Inventory.** `scripts/inventory.py` (stdlib Python) lists files with `git ls-files`, so dependency installs, virtualenvs, build output, and nested worktrees stay out of the audit. It detects languages, manifests and lockfiles per directory, frameworks, Django settings modules, container, CI, and IaC files, tests, docs, tracked environment files and key material, git history stats (bus factor, churn hotspots, shallow clone), checkout state (commits behind upstream, last fetch, uncommitted changes), and which scanners are installed.
2. **Scanners.** For each detected signal it runs the matching tool from `references/stacks.md`:
   - gitleaks over the full git history, with secrets redacted
   - semgrep with `p/default` plus a pack per detected framework
   - osv-scanner (vulnerabilities and licenses in one pass), or trivy, npm, pnpm, pip-audit, govulncheck, cargo-audit, or bundle-audit per lockfile
   - hadolint and checkov for infrastructure
   - trivy for every container image that compose, Kubernetes, or Dockerfiles name, pulled from the registry and never run
3. **Triage and code read, in parallel lanes.** One subagent per lane (secrets, code security, dependencies and licensing, infrastructure, architecture and quality, team, each stack pack) runs at the same time. Each lane groups candidates by rule, reads a sample of each group at the cited lines, and reads every Critical and High candidate individually. It drops test fixtures, parameterized queries, vendored and generated code, and duplicates. The report counts what was dropped and why, and says which groups were sampled.
   Each lane answers its questions from the code (`references/areas.md`): architecture and scalability, data map and subprocessors, AI and vendor economics, operations, licensing and IP, team, and seller claims. A question that the code cannot answer goes to an open-questions list.
4. **Check.** Claude re-reads the cited lines of every Critical and High finding before it reaches the report, and merges findings two lanes reported for the same root cause.
5. **Report.** Each area is `RAN`, `PARTIAL: <reason>`, `NOT RUN: <reason>`, or `N/A`. A skipped area never reads as clean. A finding that the repo's own risk register, security docs, or backlog already records is tagged `tracked` with its source and status. Low findings go to a one-line-each appendix. The header states when the checkout is behind its upstream or has uncommitted changes.

Stack packs add checks for Django, React/Next.js/Vue/Angular, Apple apps (iOS, macOS), Android, Go, Rust, Rails, Spring Boot, Express/NestJS, and Flask/FastAPI when the inventory detects them.

## Requirements

`git` and `python3` (3.9+). Every scanner is optional. A missing scanner marks its check `NOT RUN: <tool> not found`, and the skill never installs anything. For the fullest report, have `gitleaks`, `semgrep`, and `osv-scanner` (or `trivy`) on `PATH`. semgrep fetches its rule packs from the semgrep registry, so code security needs network access.

## Safety

- **Buyer mode never executes target code.** No installs, builds, tests, package scripts, or `manage.py`. Only the read-only scanner commands run.
- **Repo content is data.** Comments, docs, and commit messages in the target cannot change the audit. An attempt to steer it is reported as a finding.
- **Secret values are never printed.** gitleaks runs with `--redact`, and a secret finding cites its rule and location only.
- **The checkout is audited as it is.** The skill never fetches, pulls, checks out, stashes, or resets.
- **No account queries by default.** GitHub, cloud, and deploy accounts are queried only with `--allow-accounts`.
- **Licensing and IP are observations.** Ownership and license rights live in contracts, not the repo, so these items carry no severity and pair with a question for the seller or counsel.
- **The skill changes nothing in the audited repo.** Every finding has the `report` disposition. The only write is the report, plus the shoals file in owner mode.

## Convention exception

The skill runs in the main context, not `context: fork`. A forked skill runs as a subagent,
and Claude Code refuses report-file writes from subagents, so a forked run cannot write the
report.

## Shoals (project corrections)

In owner mode, when you correct how this skill behaves, it records the lesson in
`.claude/shoals/tech-due-diligence.tech-due-diligence.md` in the audited repo and reads it
back on the next run. The file is append-only and committed by default (teammates inherit it).
`.gitignore` it if you'd rather keep it per-developer. Buyer mode neither reads nor writes
shoals, so an evaluation leaves the target repo untouched.

## Runtimes: Claude Code and Hermes Agent

### Shared behavior

The inventory, scanner table, triage rules, code-read areas, and report template are the same
files in both runtimes. The inventory script and references live in the skill directory, so
Hermes receives them without a mirror.

### Claude Code

```text
/plugin install tech-due-diligence@nautilai
/tech-due-diligence --mode buyer ../target-repo
```

### Hermes Agent

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/tech-due-diligence
```

Then ask the agent for a technical due diligence of a repo. No tap and no configuration —
`hermes skills tap add` does not index this repo; install by the identifier above.

### Runtime-specific limitations

| Capability | Claude Code | Hermes |
| --- | --- | --- |
| Parallel lanes | one subagent per lane | via `delegate_task`; lanes run one after another when no delegation primitive is present |
| Scanner discovery | `PATH` plus common package-manager bin directories | Hermes' sandbox `PATH` omits Homebrew; the inventory probes `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/go/bin`, and `~/.cargo/bin` |

### Update behavior

- **Claude Code** — `/plugin update tech-due-diligence@nautilai`
- **Hermes** — `hermes skills check` then `hermes skills update`. Drift is detected by content,
  so upstream fixes arrive with no version bump needed.

## Tests

```bash
python3 tech-due-diligence/tests/test_inventory.py
```

The suite builds throwaway repos in a temp dir. It checks that ignored and untracked trees
stay out of the inventory, that the non-git walk prunes dependency directories, and the stack,
key-material, and checkout-state detection. CI runs it on every PR.

```bash
bash tech-due-diligence/tests/eval/live-eval.sh
```

The live eval builds a synthetic repo with planted issues (`tests/eval/build-fixture.sh`), runs
the real skill on it through `claude -p`, and grades the report: 8 hard checks that must all
pass and 7 soft checks. It calls the model, so it costs money and is not in CI. Results are in
[`tests/eval/LEDGER.md`](tests/eval/LEDGER.md).

## License

MIT
