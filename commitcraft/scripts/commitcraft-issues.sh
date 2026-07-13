#!/usr/bin/env bash
# CommitCraft Issue Validation Script
#
# Validates GitHub issue status before committing.
# Output format: KEY: VALUE (one per line, parseable by command)
#
# STATUS values:
#   OK         - Issue found, all checks passed
#   INCOMPLETE - Issue has unchecked acceptance criteria
#   BLOCKED    - Issue has blocking label
#   NOT_FOUND  - Issue number extracted but doesn't exist
#   NO_ISSUE   - No issue number in branch name
#   ERROR      - Prerequisites not met (gh CLI)

set -euo pipefail
# Some agent runtimes (notably Hermes) run tools in a sandbox whose PATH omits
# Homebrew, so a bare `gh` is unfindable even when it is installed. Add the
# well-known locations rather than threading an absolute path through every call
# site. No-op when `gh` is already on PATH, which is the normal case.
if ! command -v gh >/dev/null 2>&1; then
    for _d in /opt/homebrew/bin /usr/local/bin; do
        [ -x "$_d/gh" ] && PATH="$PATH:$_d"
    done
    unset _d
fi

# --ref-only: skip gh validation (labels/acceptance criteria) and just emit a
# footer reference from the branch. Used on the push hot path — no network call.
REF_ONLY=false
if [ "${1:-}" = "--ref-only" ]; then
    REF_ONLY=true
fi

# Determine which tracker this repo uses (recorded by `commitcraft setup`).
# Default to github so existing repos behave exactly as before.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
TRACKER=$(jq -r '.ticket_tool // "github"' "$REPO_ROOT/.commitcraft.json" 2>/dev/null || echo "github")
BRANCH=$(git branch --show-current 2>/dev/null || echo "")

# Ticket tracking disabled — nothing to validate or link.
if [ "$TRACKER" = "none" ]; then
    echo "STATUS: NO_ISSUE"
    echo "BRANCH: $BRANCH"
    echo "INFO: ticket tracking disabled (ticket_tool: none)"
    exit 0
fi

# Linear / Jira: extract a KEY-123 reference from the branch. There is no
# GitHub-style API validation here — emit a reference the commit footer can use.
if [ "$TRACKER" = "linear" ] || [ "$TRACKER" = "jira" ]; then
    KEY=$(echo "$BRANCH" | grep -oiE '[A-Z]+-[0-9]+' | head -1 || echo "")
    if [ -n "$KEY" ]; then
        KEY=$(echo "$KEY" | tr '[:lower:]' '[:upper:]')
        echo "STATUS: REFERENCE"
        echo "ISSUE: $KEY"
        echo "REF: Refs $KEY"
        echo "TRACKER: $TRACKER"
    else
        echo "STATUS: NO_ISSUE"
        echo "BRANCH: $BRANCH"
        echo "INFO: no $TRACKER key (e.g. ABC-123) in branch name"
    fi
    exit 0
fi

# GitHub ref-only: pull the issue number from the branch, emit a footer ref,
# and skip the gh validation entirely (no network).
if [ "$REF_ONLY" = "true" ]; then
    ISSUE_NUM=$(echo "$BRANCH" | grep -oE -- '-[0-9]+$' | tr -d '-' || echo "")
    if [ -n "$ISSUE_NUM" ]; then
        echo "STATUS: REFERENCE"
        echo "ISSUE: $ISSUE_NUM"
        echo "REF: Refs #$ISSUE_NUM"
    else
        echo "STATUS: NO_ISSUE"
        echo "BRANCH: $BRANCH"
    fi
    exit 0
fi

# Default tracker: GitHub Issues (requires gh and jq).
# Guarded here, after the linear/jira/none early exits, so the dependency is
# scoped to the GitHub path only — those trackers need neither.
if ! command -v gh &>/dev/null; then
    echo "STATUS: ERROR"
    echo "ERROR: gh CLI not installed"
    echo "FIX: brew install gh"
    exit 0
fi

# Without this, `set -euo pipefail` aborts on the unguarded jq calls below and
# the caller gets no STATUS: line at all — a silent failure, not a degradation.
if ! command -v jq &>/dev/null; then
    echo "STATUS: ERROR"
    echo "ERROR: jq not installed"
    echo "FIX: brew install jq"
    exit 0
fi

if ! gh auth status &>/dev/null 2>&1; then
    echo "STATUS: ERROR"
    echo "ERROR: gh CLI not authenticated"
    echo "FIX: gh auth login"
    exit 0
fi

# Extract issue number from branch name. Only a trailing -<num> suffix
# counts (the convention commitcraft itself creates, e.g. fix/thing-305) —
# no fallback to "any number in the branch", which false-positives on
# branches like fix/upgrade-node-18.
ISSUE_NUM=$(echo "$BRANCH" | grep -oE -- '-[0-9]+$' | tr -d '-' || echo "")

if [ -z "$ISSUE_NUM" ]; then
    echo "STATUS: NO_ISSUE"
    echo "BRANCH: $BRANCH"
    echo "INFO: Epic/feature branch - issue tracking per commit"
    exit 0
fi

# Single API call for issue data
ISSUE_JSON=$(gh issue view "$ISSUE_NUM" --json number,title,state,labels,body 2>/dev/null || echo "")

if [ -z "$ISSUE_JSON" ]; then
    echo "STATUS: NOT_FOUND"
    echo "ISSUE: $ISSUE_NUM"
    exit 0
fi

# Parse issue data
TITLE=$(echo "$ISSUE_JSON" | jq -r '.title // "Unknown"')
STATE=$(echo "$ISSUE_JSON" | jq -r '.state // "unknown"')
LABELS=$(echo "$ISSUE_JSON" | jq -r '[.labels[].name] | join(",")' 2>/dev/null || echo "")
BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')

# Check for blocking labels
if echo "$LABELS" | grep -qiE "blocked|on-hold|needs-discussion"; then
    echo "STATUS: BLOCKED"
    echo "ISSUE: $ISSUE_NUM"
    echo "TITLE: $TITLE"
    echo "LABELS: $LABELS"
    echo "REASON: Issue has blocking label"
    exit 0
fi

# Check acceptance criteria (count + items for context)
# Note: grep -c outputs 0 on no matches but exits with 1, so we use || true
CHECKED=$(echo "$BODY" | grep -cE '^\s*-\s*\[x\]' || true)
UNCHECKED=$(echo "$BODY" | grep -cE '^\s*-\s*\[\s*\]' || true)
# Handle empty output (shouldn't happen but be safe)
CHECKED=${CHECKED:-0}
UNCHECKED=${UNCHECKED:-0}

if [ "$UNCHECKED" -gt 0 ]; then
    echo "STATUS: INCOMPLETE"
    echo "ISSUE: $ISSUE_NUM"
    echo "TITLE: $TITLE"
    echo "CHECKED: $CHECKED"
    echo "UNCHECKED: $UNCHECKED"
    echo "ITEMS:"
    echo "$BODY" | grep -E '^\s*-\s*\[\s*\]' | head -5 | sed 's/^/  /'
    exit 0
fi

# All checks passed
echo "STATUS: OK"
echo "ISSUE: $ISSUE_NUM"
echo "TITLE: $TITLE"
echo "STATE: $STATE"
echo "REF: Refs #$ISSUE_NUM"
exit 0
