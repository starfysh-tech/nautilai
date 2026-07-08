#!/usr/bin/env bash
# CommitCraft PR-template detection.
#
# Emits the repo's PR template location so `workflows/pr.md` fills the template the
# repo already has instead of steamrolling it with a generic body. Mechanical only:
# this script FINDS templates and reports them. It never reads, fills, or chooses
# between them semantically — that's the skill's job (it has the diff and the title).
#
# Output format: KEY: VALUE (one per line, parseable).
#
# STATUS values:
#   FOUND     - exactly one template applies; PATH is it
#   MULTIPLE  - a PULL_REQUEST_TEMPLATE/ dir of choices; one PATH line per candidate
#   NONE      - no template; skill uses its generic fallback
#
# Resolution mirrors GitHub: a single-file template may live in .github/, the repo
# root, or docs/ (case-insensitive name), with .github/ taking precedence. A
# PULL_REQUEST_TEMPLATE/ subdirectory in any of those holds multiple named templates
# that GitHub only applies via ?template= — so we surface them as choices, never
# silently pick one.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$REPO_ROOT"

shopt -s nocaseglob nullglob

# 1. A PULL_REQUEST_TEMPLATE/ dir is a deliberate multi-choice set — highest signal
#    of author intent. Check it first, in GitHub's location precedence.
multi=()
for dir in .github/PULL_REQUEST_TEMPLATE docs/PULL_REQUEST_TEMPLATE PULL_REQUEST_TEMPLATE; do
    if [ -d "$dir" ]; then
        for f in "$dir"/*.md; do
            multi+=("$f")
        done
        # Stop at the first dir that exists — GitHub doesn't merge across locations.
        [ ${#multi[@]} -gt 0 ] && break
    fi
done

if [ ${#multi[@]} -gt 1 ]; then
    echo "STATUS: MULTIPLE"
    printf 'PATH: %s\n' "${multi[@]}"
    exit 0
fi

# 2. Single-file template, in precedence order: .github/ > root > docs/. GitHub
#    matches the filename case-insensitively, so scan each dir's entries rather than
#    stat a fixed-case literal (a literal path bypasses nullglob and would always
#    look present).
for dir in .github . docs; do
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        if [ "$(basename "$f" | tr '[:upper:]' '[:lower:]')" = "pull_request_template.md" ]; then
            echo "STATUS: FOUND"
            echo "PATH: ${f#./}"   # strip the ./ the root-dir glob prepends
            exit 0
        fi
    done
done

# 3. A dir with exactly one template degrades to a single template.
if [ ${#multi[@]} -eq 1 ]; then
    echo "STATUS: FOUND"
    echo "PATH: ${multi[0]}"
    exit 0
fi

echo "STATUS: NONE"
