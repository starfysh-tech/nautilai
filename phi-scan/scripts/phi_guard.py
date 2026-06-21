#!/usr/bin/env python3
"""PreToolUse guard: block Write/Edit/MultiEdit that would introduce PHI.

Reads the hook payload ({tool_name, tool_input}) from stdin, scans the content
about to be written with the bundled phi_check scanner, and on a real (non
test-data) finding writes a reason to stderr and exits 2 — which tells Claude
Code to cancel the tool call and feeds the reason back to the model.

Opt-in: does nothing unless PHI_SCAN_GUARD is set to a truthy value, so simply
enabling the plugin never silently blocks writes. Fails open (exit 0) on any
unexpected input or error — a guard bug must never wedge the session.
"""
import json
import os
import sys

TRUTHY = {"1", "true", "yes", "on"}

# Opt-in gate FIRST, before importing the scanner — importing phi_check compiles
# its regexes (~tens of ms). The guard ships default-off, so the common path must
# cost only python startup, not a full scanner load, on every Write/Edit.
if os.environ.get("PHI_SCAN_GUARD", "").lower() not in TRUTHY:
    sys.exit(0)

# Import the bundled scanner that ships alongside this file.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from phi_check import scan_content, should_scan_file, should_skip_file
except Exception:
    sys.exit(0)  # scanner unavailable → don't block


def content_for_tool(tool_name: str, tool_input: dict) -> str:
    """Extract the text a tool would write, by tool shape."""
    if tool_name == "Write":
        return tool_input.get("content") or ""
    if tool_name == "Edit":
        return tool_input.get("new_string") or ""
    if tool_name == "MultiEdit":
        edits = tool_input.get("edits") or []
        return "\n".join(e.get("new_string", "") for e in edits if isinstance(e, dict))
    return ""


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0

    file_path = tool_input.get("file_path") or ""
    if should_skip_file(file_path) or not should_scan_file(file_path):
        return 0

    content = content_for_tool(tool_name, tool_input)
    if not content:
        return 0

    findings = [f for f in scan_content(content, file_path) if not f.is_test_data]
    if not findings:
        return 0

    kinds = sorted({f.identifier_type for f in findings})
    print(
        f"BLOCKED: phi-scan detected possible PHI in {tool_name} to "
        f"{file_path or '(unknown file)'} — {len(findings)} finding(s): "
        f"{', '.join(kinds)}. Remove the PHI, mark intentional test data, or add "
        f"a `# phi-safe` suppression on the line. To disable this guard, unset "
        f"PHI_SCAN_GUARD.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
