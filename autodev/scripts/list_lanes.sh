#!/usr/bin/env bash
# List existing task lanes.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
find "$ROOT/.autodev" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
