#!/usr/bin/env python3
"""Validate the hooks block of a Claude Code settings.json file.

Unknown event names are reported as WARNINGS (not errors) so the validator
never false-fails on events added in newer Claude Code versions. The error and
warning counts are surfaced via the `__ERRORS__:<n>` / `__WARNINGS__:<n>`
stdout sentinels for the shell wrapper to parse; this script exits 0 whenever
it ran to completion (regardless of how many errors it found) and only exits
nonzero if it crashed, so the shell can distinguish "validator ran, found
errors" from "validator crashed" without the exit code wrapping mod 256.
"""
import json
import re
import shutil
import sys
from typing import Any

file_path = sys.argv[1]
fix_mode = sys.argv[2] == "True"

# Hook events — last synced 2026-06-18 from
# https://code.claude.com/docs/en/hooks.md
# Matcher-based events accept a "matcher" field; matcher-less events do not.
MATCHER_EVENTS = {
    "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
    "PermissionDenied", "SessionStart", "Setup", "SessionEnd", "Notification",
    "SubagentStart", "SubagentStop", "PreCompact", "PostCompact", "ConfigChange",
    "FileChanged", "StopFailure", "InstructionsLoaded", "UserPromptExpansion",
    "Elicitation", "ElicitationResult",
}
EVENTS_WITHOUT_MATCHER = {
    "UserPromptSubmit", "PostToolBatch", "Stop", "TeammateIdle", "TaskCreated",
    "TaskCompleted", "WorktreeCreate", "WorktreeRemove", "CwdChanged",
    "MessageDisplay",
}
KNOWN_EVENTS = MATCHER_EVENTS | EVENTS_WITHOUT_MATCHER

# Hook handler types and their required string field(s) — synced 2026-06-18 from
# https://code.claude.com/docs/en/hooks.md. An unrecognized type is warned about
# (may be valid in a newer Claude Code), not errored, mirroring unknown events.
REQUIRED_FIELDS = {
    "command": ("command",),
    "http": ("url",),
    "mcp_tool": ("server", "tool"),
    "prompt": ("prompt",),
    "agent": ("prompt",),
}
VALID_HOOK_TYPES = set(REQUIRED_FIELDS)
SORTED_HOOK_TYPES = sorted(VALID_HOOK_TYPES)

errors = 0
warnings = 0
modified = False

with open(file_path, "r") as f:
    config: Any = json.load(f)

if not isinstance(config, dict):
    print("❌ ERROR: settings.json root must be a JSON object")
    errors += 1
    hooks: Any = {}
elif not isinstance(config.get("hooks", {}), dict):
    print("❌ ERROR: 'hooks' must be a JSON object")
    errors += 1
    hooks = {}
else:
    hooks = config.get("hooks", {})

if isinstance(config, dict) and isinstance(config.get("hooks", {}), dict) and not hooks:
    print("ℹ️  INFO: no `hooks` configured in this file")

for event_name, matchers in hooks.items():
    # Unknown event → warn, don't error (may be valid in a newer Claude Code).
    if event_name not in KNOWN_EVENTS:
        print(f"⚠️  WARNING: unrecognized hook event '{event_name}' — may be valid "
              f"in a newer Claude Code, or a typo. Verify against "
              f"https://code.claude.com/docs/en/hooks (known list synced 2026-06-18)")
        warnings += 1
        continue

    if not isinstance(matchers, list):
        print(f"❌ ERROR: '{event_name}' hooks must be an array")
        errors += 1
        continue

    for i, matcher_block in enumerate(matchers):
        if not isinstance(matcher_block, dict):
            print(f"❌ ERROR: '{event_name}[{i}]' must be an object")
            errors += 1
            continue

        block: dict[Any, Any] = matcher_block

        # Use .get() so static type checkers don't widen on `'k' in d` + d['k'].
        matcher = block.get("matcher")
        if matcher is not None:
            matcher_removed = False
            if event_name in EVENTS_WITHOUT_MATCHER and matcher:
                if fix_mode:
                    block.pop("matcher", None)
                    modified = True
                    matcher_removed = True
                    print(f"  ✓ Fixed: removed unused matcher from {event_name}[{i}]")
                else:
                    print(f"⚠️  WARNING: '{event_name}' doesn't use matchers, "
                          f"'matcher: \"{matcher}\"' will be ignored")
                    warnings += 1

            # A matcher removed above is gone from the block; don't validate a
            # value the user can no longer see.
            if matcher_removed:
                pass
            elif not isinstance(matcher, str):
                print(f"❌ ERROR: '{event_name}[{i}].matcher' must be a string")
                errors += 1
            elif matcher and matcher != "*":
                try:
                    re.compile(matcher)
                except re.error as e:
                    print(f"❌ ERROR: invalid regex in '{event_name}[{i}].matcher': {e}")
                    errors += 1
        elif event_name not in EVENTS_WITHOUT_MATCHER:
            print(f"⚠️  WARNING: '{event_name}[{i}]' missing 'matcher' field")
            warnings += 1

        block_hooks = block.get("hooks")
        if block_hooks is None:
            print(f"❌ ERROR: '{event_name}[{i}]' missing 'hooks' array")
            errors += 1
            continue

        if not isinstance(block_hooks, list):
            print(f"❌ ERROR: '{event_name}[{i}].hooks' must be an array")
            errors += 1
            continue

        for j, hook in enumerate(block_hooks):
            if not isinstance(hook, dict):
                print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}]' must be an object")
                errors += 1
                continue

            hook_obj: dict[Any, Any] = hook

            hook_type = hook_obj.get("type")
            if hook_type is None:
                # `command` is the only type with no other required field, so it's
                # a safe default to auto-add; we never rewrite an existing type.
                if fix_mode:
                    hook_obj["type"] = "command"
                    hook_type = "command"
                    modified = True
                    print(f"  ✓ Fixed: added type='command' to {event_name}[{i}].hooks[{j}]")
                else:
                    print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}]' missing 'type' field")
                    errors += 1
            elif not isinstance(hook_type, str) or not hook_type:
                # Present but not a non-empty string → malformed, not a future type.
                print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}].type' must be a "
                      f"non-empty string")
                errors += 1
                hook_type = None  # skip required-field checks
            elif hook_type not in VALID_HOOK_TYPES:
                # Warn, don't error — may be a type added in a newer Claude Code.
                print(f"⚠️  WARNING: '{event_name}[{i}].hooks[{j}].type' is '{hook_type}', "
                      f"not one of {SORTED_HOOK_TYPES} — may be valid in a newer "
                      f"Claude Code, or a typo")
                warnings += 1
                hook_type = None  # skip required-field checks for an unknown type

            # Each known type requires its own field(s) (command/url/server+tool/prompt).
            if hook_type:
                for field in REQUIRED_FIELDS.get(hook_type, ()):
                    value = hook_obj.get(field)
                    if value is None:
                        print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}]' (type '{hook_type}') "
                              f"missing '{field}' field")
                        errors += 1
                    elif not isinstance(value, str) or not value:
                        print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}].{field}' must be a "
                              f"non-empty string")
                        errors += 1

            timeout = hook_obj.get("timeout")
            if timeout is not None:
                if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
                    print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}].timeout' must be a positive number")
                    errors += 1

if fix_mode and modified:
    backup_path = file_path + ".bak"
    shutil.copy2(file_path, backup_path)
    with open(file_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"\n✅ Fixed issues in {file_path} (backup written to {backup_path})")

print(f"__ERRORS__:{errors}")
print(f"__WARNINGS__:{warnings}")
sys.exit(0)
