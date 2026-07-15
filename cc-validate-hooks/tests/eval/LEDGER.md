# cc-validate-hooks core validator — eval ledger

Offline, deterministic eval for the **checking logic** of the `cc-validate-hooks`
plugin. The skill's *orchestration* is `model: haiku`, but the actual schema
checks live in `scripts/validate-hooks-core.py` (pure Python, no model). This
eval tests that Python core directly — no network, no model, no secrets.

## What the core checks (enumerated from `validate-hooks-core.py`)

Invocation: `validate-hooks-core.py <settings.json path> <fix_mode:"True"|"False">`.
It `json.load`s the file, walks `config["hooks"]`, and prints one `❌ ERROR` /
`⚠️ WARNING` / `ℹ️ INFO` line per finding, then two sentinel lines
`__ERRORS__:<n>` and `__WARNINGS__:<n>`. **It exits 0 whenever it ran to
completion** (any number of findings) and only exits nonzero if it *crashed*.
The shell wrapper (`validate-hooks.sh`) parses the sentinels to decide the CLI
exit code.

Checks, by branch:

| # | Condition | Verdict |
| --- | --- | --- |
| 1 | root is not a JSON object | ERROR `settings.json root must be a JSON object` |
| 2 | `hooks` value is not an object | ERROR `'hooks' must be a JSON object` |
| 3 | `hooks` empty / absent | INFO `no `hooks` configured` (not an error) |
| 4 | event name not in the known set | WARNING `unrecognized hook event` (block skipped) |
| 5 | event value is not an array | ERROR `'<event>' hooks must be an array` |
| 6 | a matcher block is not an object | ERROR `'<event>[i]' must be an object` |
| 7 | `matcher` present on a matcher-less event | WARNING `doesn't use matchers` (or auto-removed with `--fix`) |
| 8 | `matcher` present but not a string | ERROR `.matcher' must be a string` |
| 9 | `matcher` truthy, `!= "*"`, not a valid regex | ERROR `invalid regex in '…matcher'` |
| 10 | `matcher` absent on a matcher-based event | WARNING `missing 'matcher' field` |
| 11 | block has no `hooks` array | ERROR `missing 'hooks' array` |
| 12 | block `hooks` not an array | ERROR `.hooks' must be an array` |
| 13 | a hook entry is not an object | ERROR `hooks[j]' must be an object` |
| 14 | hook `type` absent | ERROR `missing 'type' field` (or `--fix` adds `command`) |
| 15 | hook `type` present but not a non-empty string | ERROR `.type' must be a non-empty string` |
| 16 | hook `type` unknown (string, not in the 5) | WARNING `not one of [...]` (field checks skipped) |
| 17 | a required field for the type is absent | ERROR `(type '<t>') missing '<field>' field` |
| 18 | a required field present but not a non-empty string | ERROR `.<field>' must be a non-empty string` |
| 19 | `timeout` present and (bool / non-number / `<= 0`) | ERROR `.timeout' must be a positive number` |

Known event sets and hook-type required fields are hardcoded in the core
(`KNOWN_EVENTS`, `REQUIRED_FIELDS`, synced 2026-06-18 from the Claude Code hooks
docs). Types: `command`→`command`, `http`→`url`, `mcp_tool`→`server`+`tool`,
`prompt`→`prompt`, `agent`→`prompt`.

## Fixtures & gold labels

32 fixtures under `fixtures/`, one condition each, mapped to expected verdicts in
`expected-verdicts.tsv` (columns: fixture, expected_errors, expected_warnings,
signature substring, description). **Every gold label was derived by RUNNING the
core on the fixture and recording actual output** — not guessed. The verdict is
the `(__ERRORS__, __WARNINGS__)` sentinel pair, plus a distinctive stdout
substring (the "signature") so a fixture must trigger the *right* finding, not
merely the right count. Coverage maps to the branch table above: 7 valid/clean,
2 root/container, 1 invalid-JSON, 1 unknown-event, 6 matcher, 3 hooks-array, 8
type/field, 3 timeout, 1 combined-count.

Derivation run (`python3 scripts/validate-hooks-core.py <fixture> False`):

```
block-hooks-not-array.json       => errors=1 warnings=0
block-missing-hooks.json         => errors=1 warnings=0
combined-errors.json             => errors=2 warnings=1
hook-command-empty.json          => errors=1 warnings=0
hook-command-not-string.json     => errors=1 warnings=0
hook-mcp-missing-fields.json     => errors=2 warnings=0
hook-missing-command.json        => errors=1 warnings=0
hook-missing-type.json           => errors=1 warnings=0
hook-not-object.json             => errors=1 warnings=0
hook-timeout-bool.json           => errors=1 warnings=0
hook-timeout-negative.json       => errors=1 warnings=0
hook-timeout-string.json         => errors=1 warnings=0
hook-type-empty.json             => errors=1 warnings=0
hook-type-not-string.json        => errors=1 warnings=0
hook-unknown-type.json           => errors=0 warnings=1
hooks-not-object.json            => errors=1 warnings=0
invalid-json.json                => errors=1 warnings=0 (invalid JSON)
matcher-bad-regex.json           => errors=1 warnings=0
matcher-block-not-object.json    => errors=1 warnings=0
matcher-missing.json             => errors=0 warnings=1
matcher-not-string.json          => errors=1 warnings=0
matcher-on-matcherless.json      => errors=0 warnings=1
matchers-not-array.json          => errors=1 warnings=0
root-not-object.json             => errors=1 warnings=0
unknown-event.json               => errors=0 warnings=1
valid-clean.json                 => errors=0 warnings=0
valid-empty-hooks.json           => errors=0 warnings=0
valid-http-hook.json             => errors=0 warnings=0
valid-matcherless-event.json     => errors=0 warnings=0
valid-no-hooks-key.json          => errors=0 warnings=0
valid-timeout.json               => errors=0 warnings=0
valid-wildcard-matcher.json      => errors=0 warnings=0
```

## Grader

`verdict-match.sh` runs the core on each fixture, compares `(errors, warnings)`
and the signature substring to the manifest, prints per-fixture PASS/FAIL, then:

- **hard gate**: `1` iff all fixtures pass, else `0` (all-must-pass).
- **soft fraction**: `passed/total`.
- exits nonzero when the fraction is below `THRESHOLD` (default `1.0`; override
  with the env var for a softer gate).

Run it:

```bash
bash cc-validate-hooks/tests/eval/verdict-match.sh
```

Latest run (2026-07-14): **32/32 PASS, hard gate 1, RESULT PASS, exit 0**.

## Vacuity proof (grader can FAIL)

To prove the grader is not vacuously green, two gold labels were temporarily
corrupted and the grader re-run:

1. `root-not-object.json` expected_errors `1` → `9` (wrong count).
2. `invalid-json.json` expected_errors `1` → `9` (wrong count).

Result: the corrupted line reported **FAIL** (`errors 1!=9`), `soft: 31/32
(0.9688)`, `hard: 0`, `RESULT: FAIL`, exit 1. The label was then restored and the
grader returned to 32/32 PASS, exit 0. So the grader genuinely diffs
observed-vs-expected and fails on divergence.

## Known limitations (honest notes, not silently encoded as "correct")

1. **Invalid JSON is handled in the core.** `validate-hooks-core.py` wraps
   `json.load` in a `try/except json.JSONDecodeError` and reports a clean
   `❌ ERROR: invalid JSON syntax` with the sentinel `__ERRORS__:1`, exit 0
   (fixture `invalid-json.json`). This is defense-in-depth: the **shell wrapper**
   (`validate-hooks.sh`, lines 44-48) also syntax-checks first, but the core no
   longer depends on that guard — a direct caller (this eval) invokes it
   standalone. This eval surfaced the original gap: before the guard, malformed
   JSON crashed the core with an uncaught traceback, masked only by the wrapper.

2. **The core does not distinguish settings-file *location*.** It takes a path
   argument and treats `.claude/settings.json`, `.claude/settings.local.json`,
   and `~/.claude/settings.json` identically — the three-location enumeration
   lives entirely in the shell wrapper. So there is no per-shape behavior to test
   at the core level; the fixtures deliberately don't duplicate a shape they'd
   validate identically.

3. **Boolean `timeout` is rejected as "not a positive number."** The core
   special-cases `isinstance(timeout, bool)` so `true`/`false` are errors, even
   though `True == 1` in Python. This is intended (a boolean timeout is a
   mistake) and is encoded as the expected verdict for `hook-timeout-bool.json`.

4. **Counts + one signature, not full message diff.** The grader matches the
   `(errors, warnings)` pair and a single distinctive substring per fixture, not
   the entire message text. A fixture engineered to emit the *same* counts and
   the *same* signature substring from a different code path could slip through.
   Each fixture isolates one condition to keep that risk low, but the grader is a
   verdict-shape check, not a byte-exact golden-output diff.

5. **Fix mode (`--fix`) is not exercised.** All fixtures run with `fix_mode =
   False`. The auto-fix branches (remove stray matcher, add default
   `type: command`, write `.bak`) are checked only in the plugin's own behavior,
   not here — this eval is scoped to the read-only validation verdicts.
