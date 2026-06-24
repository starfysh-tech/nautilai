# CC Validate Hooks

Validate the local Claude Code hooks configuration in `settings.json` — report schema errors, invalid event names, malformed matchers, and bad hook fields, with an optional `--fix`.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install cc-validate-hooks@nautilai
```

Requires `python3` (or `python`) on your PATH.

## Use

```text
/cc-validate-hooks
/cc-validate-hooks --fix
```

## What it does

Validates the hooks configuration in your project and user `settings.json` files:

1. **JSON & schema** — parses each `settings.json` and checks the `hooks` block against the expected shape.
2. **Event names** — the known Claude Code hook event names are kept in sync from the docs; unknown events are flagged as warnings (not hard errors) so newly shipped events don't false-positive.
3. **Matchers** — checks each matcher's shape and that any regex compiles.
4. **Hook fields** — checks each hook's `type`, `command`, and `timeout` for valid values.

`--fix` repairs simple issues in place and writes a `.bak` backup before changing anything.

It complements `claude plugin validate` — that command validates plugin *manifests*, not your user hooks config.

## Shoals (project corrections)

This plugin deliberately does **not** use the shoals convention (auto-captured
project corrections). Hook validation is mechanical and deterministic — there are
no recurring judgment calls for a project to correct across runs.

## License

MIT
