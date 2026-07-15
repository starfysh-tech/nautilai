# phi-scan deterministic-scanner eval — ledger

## What this eval covers

Offline recall/precision eval for the **deterministic** PHI scanner
(`phi-scan/scripts/phi_check.py`). The AI-triage layer that sits on top of the
scanner (SKILL.md: "The deterministic PHI layer is the core") is **out of
scope** — no model is invoked. Everything runs against local fixtures with pure
`python3` + `bash`: no network, no API, no secrets.

- Fixtures: `fixtures/*.txt`, all clearly-SYNTHETIC planted data (fake SSN
  groups, RFC-2606 `@example.com` emails, 555-01xx fictional phones, RFC-5737
  documentation IPs, placeholder dates/ZIPs). Each file carries a header noting
  it is synthetic test data.
- Gold manifest: `gold.tsv` — expected findings per `(fixture, class)`, **derived
  by running the scanner** and recording observed output, not guessed.
- Grader: `recall-precision.sh` — scores RECALL (hard gate) and PRECISION
  (informational), emits a per-fixture PASS/FAIL line plus a hard gate (1/0) and
  a soft fraction. Exits nonzero when recall is below threshold.

Run it:

```bash
bash phi-scan/tests/eval/recall-precision.sh
```

## Classes the deterministic layer claims to detect

From `PATTERNS` in `phi_check.py`: `ssn`, `email`, `phone`, `ip_v4`, `date_us`,
`date_iso`, `zip_5` (with a `zip_5(restricted)` variant for the 17 HIPAA
restricted ZIP prefixes). Output format per finding:

```text
  {line}:{col} [PHI|TEST] {class}[(restricted)]: {value}
```

**Names and MRNs are deliberately NOT a scanner class.** SKILL.md is explicit
that free-text names and org-specific MRNs are invisible to regex and are the
triage step's job. `fixtures/expected_miss_names_mrn.txt` plants synthetic names
(`Patient: Jane Q. Doe`, `Dr. John Smith`) and MRNs (`MRN-0098472`,
`A12B34C56`); the scanner detects **nothing** in it (observed: 0 findings). That
fixture is labeled `expected-miss` and does **not** count against recall — the
grader only credits recall to the detectable classes above.

## Two scanner behaviors the grader has to work around

Both are documented so no one mistakes the workaround for a bug:

1. **`should_skip_file` skips any path containing `/tests/`.** The fixtures live
   under `phi-scan/tests/eval/fixtures/`, so scanning them in place returns "No
   files to scan". The grader copies each fixture to a neutral `mktemp -d` dir
   before scanning.
2. **`is_test_data` classifies anything under `/fixtures/` (and content markers
   like `@example.com`, `123-45-6789`, `mock`/`fake`) as test data**, which the
   default run filters out of the reported findings. The grader passes
   `--include-test-data` so it measures the **detection regex in isolation** from
   the downstream test-data filter. That filter correctly suppressing synthetic
   data is *its* job and is not what this eval grades — which is why, e.g., the
   `@example.com` emails show as `[TEST]` yet still count as detected.

## Run output (2026-07-14)

Commit baseline: `8ae3a64` (working tree). `python3` stdlib scanner, no model.

```text
# phi-scan deterministic scanner — recall / precision eval

fixture                          role           result
-------                          ----           ------
pos_direct_identifiers.txt       positive       PASS  [email=2/2 ip_v4=3/3 phone=3/3 ssn=2/2]
pos_dates_zips.txt               positive       PASS  [zip_5=1/1 date_iso=2/2 date_us=2/2 zip_5(restricted)=2/2]
pos_phone_formats.txt            positive       PASS  [phone=5/5]
neg_clean_prose.txt              negative       PASS  []
neg_phi_adjacent.txt             negative       PASS  [zip_5=5/5 ip_v4=1/1]
expected_miss_names_mrn.txt      expected-miss  PASS  []

## Recall (HARD GATE) — detectable-class planted items
detected 22/22 (100%), threshold 100%

## Precision (INFORMATIONAL — triage owns precision, not gated)
true positives 22, false positives on negative fixtures 6, precision 78%

## Aggregate
soft: 6/6 fixtures match recorded gold
hard: 1 (recall gate PASS)

GATE: PASS
```

- **Recall 22/22 (100%)** across the 8 detectable-class cells in the three
  positive fixtures. Recall is 100% by construction (gold is observed), so the
  gate's live value is **regression detection**: if a future change to
  `phi_check.py` stops detecting a class, recall drops and the gate fails.
- **Precision 78% is informational only** and is not gated — triage owns
  precision. The 6 false positives are all on `neg_phi_adjacent.txt` and are
  documented below.

## Vacuity proof (the grader can FAIL)

To prove the grader is not green-by-default, one planted SSN in
`pos_direct_identifiers.txt` was temporarily changed from `457-55-1234` to
`REDACTED-XX-XXXX` (no longer a valid SSN pattern) and the grader re-run:

```text
pos_direct_identifiers.txt  positive  FAIL  [email=2/2 ip_v4=3/3 phone=3/3 ssn=1/2]  (observed != gold)
## Recall (HARD GATE) ... detected 21/22 (95%), threshold 100%
hard: 0 (recall gate FAIL)
GATE: FAIL          (exit 1)
```

The fixture was then restored to `457-55-1234` and the grader returned to
`GATE: PASS` / exit 0 (22/22). The diff between observed and gold is real and
the hard gate reacts to it.

## Known scanner limitations found while building this eval

None of these are bugs the eval "fixes" — they are honest characterizations of
the deterministic layer, which is exactly why the triage step exists.

1. **Version strings parse as IPv4.** `1.2.3.4` (an app version) is flagged
   `ip_v4`. Any dotted quad with octets 0-255 matches; the scanner has no
   carve-out for private (RFC-1918) or reserved ranges either — `192.168.1.1`
   would flag too. (`neg_phi_adjacent.txt`, observed.)
2. **Any bare 5-digit number parses as a ZIP.** Build numbers (`19041`), invoice
   IDs (`84213`), quantities/thresholds (`50000`, `12345`) all flag `zip_5`.
   This is the dominant false-positive source (5 of the 6 FPs here) and is
   called out in SKILL.md's own "Gotchas". (`neg_phi_adjacent.txt`, observed.)
3. **Emails/SSNs matching a content marker are detected but classified
   `[TEST]`.** `@example.com`, `@example.org`, and literals like `123-45-6789`
   trip `is_test_data`, so a default run (without `--include-test-data`) hides
   them. Real PHI is unaffected; this only matters for synthetic fixtures, which
   is why this eval forces `--include-test-data`.
4. **MRNs are a clean miss here, but their numeric tail *can* incidentally hit
   `zip_5`.** `MRN-0098472` (7-digit tail) does not match (needs exactly 5 digits
   between word boundaries), so `expected_miss_names_mrn.txt` observes 0
   findings. An MRN whose numeric part is exactly 5 digits (e.g. `MRN-12345`)
   would flag as `zip_5` — an incidental match on the wrong class, not true MRN
   detection. Not planted here to keep the expected-miss fixture unambiguous.

## Maintenance

- Gold is derived from observed output. If `phi_check.py`'s patterns change
  intentionally, re-run the scanner over the fixtures, update `gold.tsv` to the
  new observed counts, and record a new dated run block above.
- Keep all fixture data synthetic. Never add realistic patient data — the
  scanner is the thing under test, not a data store.
