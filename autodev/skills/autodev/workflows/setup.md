# Setup — write the TDD profile

Writes `.claude/autodev.md` at the repo root. The user commits it; lanes freeze
a copy when they start.

## 1. Detect

For each key, find a value and the file it came from. Never guess: no
evidence → `unknown`.

| Key | Where to look |
|---|---|
| `test_file` | command that runs one test file, with `{file}` — `pytest.ini` / `pyproject.toml` (`pytest -q {file}`, or `uv run pytest -q {file}` when `uv.lock` exists), `vitest.config.*` (`npx vitest run {file}`), jest config (`npx jest {file}`), `go.mod` (`go test ./{file}`), task runners (`Makefile`, `mise.toml`, `justfile`, `package.json` scripts) |
| `full_suite` | the same sources; `package.json` `scripts.test`; CI workflows under `.github/workflows/` |
| `lint` | ruff / eslint / golangci-lint config, task runners, pre-commit or husky hooks; use `{files}` for the changed-file list |
| `format` | the formatter that writes files (`ruff format {files}`, `prettier --write {files}`) |
| `format_check` | the same formatter in check mode (`ruff format --check {files}`, `prettier --check {files}`) |
| `coverage` | coverage config or scripts (`pytest --cov`, `vitest --coverage`) |
| `db_isolation` | how the suite picks its test DB (`DB_NAME`, `DATABASE_URL`, settings files); write it as `VAR=value_{slug}` |
| `test_config` | files that can skip or deselect tests: `conftest.py`, `pytest.ini`, `vitest.config.*`, `jest.config.*` — comma-separated |
| `stack` | comma list from: `pytest`, `factory_boy`, `vitest`, `rtl` (sections of `${CLAUDE_PLUGIN_ROOT}/skills/autodev/references/tdd.md` to include) |

Also read the pre-commit hooks (`.pre-commit-config.yaml`, `.husky/`,
`lint-staged` config) and note whether any hook runs tests.

Prose for the body, each with its source: factory or fixture conventions,
the mocking convention, where tests live, whether hooks run tests, and anything
in `CLAUDE.md` about testing.

## 2. Confirm

Show every value with its source file and ask the user with
`AskUserQuestion`. The advisor never answers setup. With no user to answer,
write the draft (section 3 format) to `.autodev/profile-draft.md`, report
`awaiting_setup` with
`mkdir -p .claude && cp .autodev/profile-draft.md .claude/autodev.md`, and stop.
Apply the user's fixes.

## 3. Write

```markdown
---
test_file: <value>
full_suite: <value>
lint: <value>
format: <value>
format_check: <value>
coverage: <value>
db_isolation: <value>
test_config: <value>
stack: <value>
---
<prose, one bullet per convention, each naming its source>
```

Quote a value that starts with a quote character or contains ` #`. Use
`unknown` for a value with no evidence; never leave a value empty.

Check it parses:

```bash
for k in test_file full_suite lint format format_check coverage db_isolation test_config stack; do
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/profile.py get .claude/autodev.md "$k" >/dev/null; echo "$k: $?"
done
```

Exit 0 = value, 3 = skipped (`unknown`), 2 = error to fix. Tell the user to
commit `.claude/autodev.md`.
