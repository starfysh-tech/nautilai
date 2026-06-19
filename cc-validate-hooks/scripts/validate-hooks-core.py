#!/usr/bin/env python3
"""Validate the hooks block of a Claude Code settings.json file.

Unknown event names are reported as WARNINGS (not errors) so the validator
never false-fails on events added in newer Claude Code versions. Exits with
the number of errors found; warnings are surfaced via the `__WARNINGS__:<n>`
stdout sentinel for the shell wrapper to parse.
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

errors = 0
warnings = 0
modified = False

with open(file_path, "r") as f:
    config: Any = json.load(f)

hooks: Any = config.get("hooks", {})

if not hooks:
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
            if event_name in EVENTS_WITHOUT_MATCHER and matcher:
                if fix_mode:
                    block.pop("matcher", None)
                    modified = True
                    print(f"  ✓ Fixed: removed unused matcher from {event_name}[{i}]")
                else:
                    print(f"⚠️  WARNING: '{event_name}' doesn't use matchers, "
                          f"'matcher: \"{matcher}\"' will be ignored")
                    warnings += 1

            if isinstance(matcher, str) and matcher and matcher != "*":
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
                if fix_mode:
                    hook_obj["type"] = "command"
                    modified = True
                    print(f"  ✓ Fixed: added type='command' to {event_name}[{i}].hooks[{j}]")
                else:
                    print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}]' missing 'type' field")
                    errors += 1
            elif hook_type != "command":
                if fix_mode:
                    hook_obj["type"] = "command"
                    modified = True
                    print(f"  ✓ Fixed: changed type to 'command' in {event_name}[{i}].hooks[{j}]")
                else:
                    print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}].type' must be 'command', "
                          f"got '{hook_type}'")
                    errors += 1

            command = hook_obj.get("command")
            if command is None:
                print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}]' missing 'command' field")
                errors += 1
            elif not command or not isinstance(command, str):
                print(f"❌ ERROR: '{event_name}[{i}].hooks[{j}].command' must be a non-empty string")
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

print(f"__WARNINGS__:{warnings}")
sys.exit(errors)
