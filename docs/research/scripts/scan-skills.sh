#!/usr/bin/env bash
# Reproduce the SkillSpector evaluation recorded in ../skillspector-evaluation.md.
#
# Scans every skill in this repo with SkillSpector (static mode) and writes a
# findings digest comparable to docs/research/data/skillspector-2.3.11-findings.csv.
#
#   bash docs/research/scripts/scan-skills.sh [output-dir]
#
# Defaults to a temp dir. Diff the resulting CSV against the committed one to see
# what changed between tool versions:
#
#   diff <(tail -n +2 docs/research/data/skillspector-2.3.11-findings.csv | cut -d, -f2,5) \
#        <(tail -n +2 "$OUT/findings.csv" | cut -d, -f2,5)
#
# Notes:
#   - SkillSpector publishes no tags and no releases, so the pin below is a raw
#     commit SHA. Bump it deliberately; do not float to main.
#   - --no-llm is static-only but NOT offline: the supply-chain analyzer performs
#     live api.osv.dev lookups. Use `docker run --network=none` if that matters.
#   - Scanning must target each <plugin>/skills/<name>/ directly. Scanning the repo
#     root or <plugin>/skills/ silently degrades to a single aggregate score,
#     because multi-skill detection needs >=2 immediate subdirs each holding a
#     SKILL.md (src/skillspector/multi_skill.py:51-91).

set -euo pipefail

SKILLSPECTOR_PIN="c2d09df019e358d3dc12d980b82c798b87cb9f56"  # v2.3.11, 2026-07-07
PYTHON="${PYTHON:-python3.13}"  # SkillSpector requires >=3.12,<3.15

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT/scans"

command -v "$PYTHON" >/dev/null || { echo "need $PYTHON (>=3.12,<3.15); set PYTHON=" >&2; exit 1; }

echo "repo:        $REPO_ROOT @ $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
echo "skillspector: $SKILLSPECTOR_PIN"
echo "output:      $OUT"

if [ ! -x "$OUT/venv/bin/skillspector" ]; then
  "$PYTHON" -m venv "$OUT/venv"
  "$OUT/venv/bin/pip" install -q "git+https://github.com/NVIDIA/SkillSpector@${SKILLSPECTOR_PIN}"
fi
SS="$OUT/venv/bin/skillspector"
echo "version:     $("$SS" --version)"
echo

cd "$REPO_ROOT"
# maxdepth 2 under */skills matches <plugin>/skills/<name>/SKILL.md
find ./*/skills -maxdepth 2 -name SKILL.md | sort | while read -r f; do
  dir="$(dirname "$f")"
  dir="${dir#./}"   # find ./*/skills prefixes results; slug/skill column must not carry it
  slug="${dir//\//_}"
  # Non-zero exit means risk_score > 50; that is data, not an error.
  "$SS" scan "$REPO_ROOT/$dir" --no-llm --format json -o "$OUT/scans/$slug.json" >/dev/null 2>&1 || true
  printf '  scanned %s\n' "$dir"
done

"$PYTHON" - "$OUT" <<'PY'
import csv, glob, json, os, re, sys

out = sys.argv[1]
rows = []
snip = lambda s: re.sub(r"\s+", " ", (s or "")).strip()[:80]

for p in sorted(glob.glob(f"{out}/scans/*.json")):
    d = json.load(open(p))
    ra = d["risk_assessment"]
    skill = os.path.basename(p)[:-5].replace("_", "/")
    base = dict(corpus="nautilai", skill=skill, score=ra["score"], recommendation=ra["recommendation"])
    if not d["issues"]:
        rows.append({**base, "rule_id": "", "severity": "", "confidence": "", "file": "", "line": "", "matched": ""})
    for i in d["issues"]:
        loc = i["location"]
        rows.append({**base, "rule_id": i["id"], "severity": i["severity"], "confidence": i["confidence"],
                     "file": loc["file"] or "", "line": loc["start_line"] or "", "matched": snip(i.get("finding"))})

cols = ["corpus", "skill", "score", "recommendation", "rule_id", "severity", "confidence", "file", "line", "matched"]
with open(f"{out}/findings.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(rows)

findings = sum(1 for r in rows if r["rule_id"])
blocked = sorted({r["skill"] for r in rows if r["recommendation"] == "DO_NOT_INSTALL"})
print(f"\nskills: {len({r['skill'] for r in rows})}  findings: {findings}  DO_NOT_INSTALL: {len(blocked)}")
for b in blocked:
    print(f"  {b}")
print(f"\ndigest: {out}/findings.csv")
PY
