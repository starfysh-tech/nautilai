#!/bin/bash

# CommitCraft Release Analyzer
# Analyzes repository for release readiness and version bumping

set -euo pipefail
# Some agent runtimes (notably Hermes) run tools in a sandbox whose PATH omits
# Homebrew, so a bare `gh` is unfindable even when it is installed. Add the
# well-known locations rather than threading an absolute path through every call
# site. No-op when `gh` is already on PATH, which is the normal case.
if ! command -v gh >/dev/null 2>&1; then
    for _d in /opt/homebrew/bin /usr/local/bin; do
        if [ -x "$_d/gh" ]; then
            PATH="$PATH:$_d"
        fi
    done
    unset _d
fi

echo "RELEASE_ANALYZE_START"
echo "=== CommitCraft Release Analysis ==="
echo ""

# Determine the default branch — releases must be cut from it.
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "")
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    echo "✗ Not on $DEFAULT_BRANCH branch"
    echo ""
    echo "Current branch: $CURRENT_BRANCH"
    echo "Releases must be created from the $DEFAULT_BRANCH branch"
    echo ""
    echo "Run: git checkout $DEFAULT_BRANCH"
    exit 1
fi

echo "✓ On $DEFAULT_BRANCH branch"

# Check for gh CLI — analysis is pure git; gh is only needed later to publish the
# release (gh release create). Warn but do not abort, so version analysis still works.
GH_AVAILABLE=true
if ! command -v gh &> /dev/null; then
    GH_AVAILABLE=false
    echo "⚠  GitHub CLI (gh) not found — analysis will proceed; publishing a release needs: brew install gh"
elif ! gh auth status &> /dev/null; then
    GH_AVAILABLE=false
    echo "⚠  GitHub CLI not authenticated — analysis will proceed; publishing needs: gh auth login"
fi

# A tag is commit-based: it points at HEAD, not at the working tree. The hard
# requirement is that HEAD matches origin/$DEFAULT_BRANCH, or we'd tag the wrong commit.
# Uncommitted/untracked files don't change the tagged commit — warn, don't block.
git fetch --quiet origin "$DEFAULT_BRANCH" 2>/dev/null || true
if git rev-parse --verify --quiet "origin/$DEFAULT_BRANCH" >/dev/null; then
    AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo 0)
    BEHIND=$(git rev-list --count HEAD.."origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
    if [ "$AHEAD" != "0" ] || [ "$BEHIND" != "0" ]; then
        echo "✗ Local $DEFAULT_BRANCH is out of sync with origin/$DEFAULT_BRANCH ($AHEAD ahead, $BEHIND behind)"
        echo ""
        echo "A tag points at HEAD — sync first so the release tags the right commit:"
        [ "$BEHIND" != "0" ] && echo "  git pull --ff-only"
        [ "$AHEAD" != "0" ] && echo "  git push"
        exit 1
    fi
    echo "✓ Local $DEFAULT_BRANCH is in sync with origin/$DEFAULT_BRANCH"
else
    echo "⚠  No origin/$DEFAULT_BRANCH to compare against — skipping the sync check"
fi

# Uncommitted/untracked files: warn only — a commit-based tag won't include them.
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠  Working tree has uncommitted/untracked changes — not included in the release (a tag is commit-based); proceeding"
else
    echo "✓ Working tree is clean"
fi
echo "GH_AVAILABLE: $GH_AVAILABLE"
echo ""

# Get latest v-prefixed semver tag (ignores bare numeric tags like 1.1.0)
LATEST_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [ -z "$LATEST_TAG" ]; then
    echo "⚠  No existing tags found"
    echo ""
    echo "Suggested first version: v1.0.0"
    echo "Commits in repository: $(git rev-list --count HEAD)"
    echo "CURRENT_VERSION: none"
    echo "NEW_VERSION: v1.0.0"
    echo "BUMP_TYPE: initial"
    echo "COMMIT_COUNT: $(git rev-list --count HEAD)"
    echo "RELEASE_ANALYZE_END"
    exit 0
fi

echo "Current version: ${LATEST_TAG}"

# Parse current version (assumes vMAJOR.MINOR.PATCH format)
if [[ ! $LATEST_TAG =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "✗ Tag format not recognized (expected vMAJOR.MINOR.PATCH)"
    echo "Found: $LATEST_TAG"
    exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

# Get commits since last tag (exclude merge commits to avoid double-counting)
COMMITS_SINCE=$(git log "${LATEST_TAG}..HEAD" --oneline --no-merges)
# grep -c already prints 0 on no match (and exits 1 under pipefail); `|| true`
# swallows that exit without echoing a second 0 — which would make the value
# "0\n0" and break the integer tests below ([: integer expected).
COMMIT_COUNT=$(echo "$COMMITS_SINCE" | grep -c . || true)

if [ "$COMMIT_COUNT" -eq 0 ]; then
    echo "⚠  No commits since ${LATEST_TAG}"
    echo ""
    echo "Nothing to release"
    echo "CURRENT_VERSION: ${LATEST_TAG}"
    echo "NEW_VERSION: ${LATEST_TAG}"
    echo "BUMP_TYPE: none"
    echo "COMMIT_COUNT: 0"
    echo "RELEASE_ANALYZE_END"
    exit 0
fi

echo "Commits since release: ${COMMIT_COUNT}"
echo ""

# Categorize commits
BREAKING_COUNT=0
FEAT_COUNT=0
FIX_COUNT=0
DOCS_COUNT=0
OTHER_COUNT=0

# Check for breaking changes in full commit bodies (single-pass). Capture git log
# separately so a real git failure still trips `set -e` — only grep's no-match exit
# should be swallowed. printf (not echo) is safe against bodies starting with `-`.
BREAKING_BODIES=$(git log "${LATEST_TAG}..HEAD" --no-merges --format=%B)
BREAKING_COUNT=$(printf '%s\n' "$BREAKING_BODIES" | grep -cE "BREAKING CHANGE|^[a-z]+!(\(|:)" || true)

# Count by commit type (single awk pass over oneline output)
read -r FEAT_COUNT FIX_COUNT DOCS_COUNT PERF_COUNT REVERT_COUNT <<< "$(echo "$COMMITS_SINCE" | awk '
  /^[a-f0-9]+ feat(!?\(|!?:)/   {f++}
  /^[a-f0-9]+ fix(!?\(|!?:)/    {x++}
  /^[a-f0-9]+ docs(!?\(|!?:)/   {d++}
  /^[a-f0-9]+ perf(!?\(|!?:)/   {p++}
  /^[a-f0-9]+ revert(!?\(|!?:)/ {r++}
  END {print f+0, x+0, d+0, p+0, r+0}
')"
OTHER_COUNT=$((COMMIT_COUNT - FEAT_COUNT - FIX_COUNT - DOCS_COUNT - PERF_COUNT - REVERT_COUNT))

# Display categorization
echo "Commit breakdown:"
if [ "$BREAKING_COUNT" -gt 0 ]; then
    echo "  Breaking changes: ${BREAKING_COUNT}"
fi
if [ "$FEAT_COUNT" -gt 0 ]; then
    echo "  Features: ${FEAT_COUNT}"
fi
if [ "$FIX_COUNT" -gt 0 ]; then
    echo "  Bug fixes: ${FIX_COUNT}"
fi
if [ "$DOCS_COUNT" -gt 0 ]; then
    echo "  Documentation: ${DOCS_COUNT}"
fi
if [ "$PERF_COUNT" -gt 0 ]; then
    echo "  Performance: ${PERF_COUNT}"
fi
if [ "$REVERT_COUNT" -gt 0 ]; then
    echo "  Reverts: ${REVERT_COUNT}"
fi
if [ "$OTHER_COUNT" -gt 0 ]; then
    echo "  Other: ${OTHER_COUNT}"
fi
echo ""

# Calculate version bump
if [ "$BREAKING_COUNT" -gt 0 ]; then
    BUMP_TYPE="major"
    NEW_MAJOR=$((MAJOR + 1))
    NEW_MINOR=0
    NEW_PATCH=0
elif [ "$FEAT_COUNT" -gt 0 ]; then
    BUMP_TYPE="minor"
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$((MINOR + 1))
    NEW_PATCH=0
else
    BUMP_TYPE="patch"
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$MINOR
    NEW_PATCH=$((PATCH + 1))
fi

NEW_VERSION="v${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"

echo "Suggested bump: ${BUMP_TYPE}"
echo "New version: ${NEW_VERSION}"
echo ""

# Show recent commits for context
echo "Recent commits:"
echo "$COMMITS_SINCE" | head -10
if [ "$COMMIT_COUNT" -gt 10 ]; then
    echo "... and $((COMMIT_COUNT - 10)) more"
fi
echo ""

echo "✓ Ready to create release"
echo ""

# Parseable output
echo "CURRENT_VERSION: ${LATEST_TAG}"
echo "NEW_VERSION: ${NEW_VERSION}"
echo "BUMP_TYPE: ${BUMP_TYPE}"
echo "COMMIT_COUNT: ${COMMIT_COUNT}"

# Structured commit output (unit separator \x1f delimited)
echo ""
echo "COMMITS_START"
git log "${LATEST_TAG}..HEAD" --format="%h$(printf '\x1f')%s" --no-merges
echo "COMMITS_END"

echo "RELEASE_ANALYZE_END"
