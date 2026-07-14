#!/usr/bin/env python3
"""
PHI scan - Scan files for potential Protected Health Information (PHI).

Deterministic, stdlib-only pattern matching for HIPAA Safe Harbor identifiers.
Works three ways:

    # staged files (default) — useful as a git pre-commit hook
    python3 phi_check.py

    # a specific path or files
    python3 phi_check.py path/to/dir file.py

    # the whole working tree
    python3 phi_check.py --all --verbose

Exit codes:
    0: No high-confidence PHI found
    1: High-confidence PHI detected (non-test) — blocks a commit when used as a hook
"""

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

# ============================================================================
# CONSTANTS
# ============================================================================

# HIPAA Safe Harbor: ZIP prefixes for areas with population < 20,000 must be
# replaced with "000". Verbatim from HHS de-identification guidance.
RESTRICTED_ZIP_PREFIXES = frozenset([
    "036", "059", "063", "102", "203", "556", "692", "790",
    "821", "823", "830", "831", "878", "879", "884", "890", "893"
])

# Markers that indicate a finding is synthetic/test data rather than real PHI.
# NOTE: deliberately excludes bare "test"/"sample" — they're common clinical
# words ("lab test", "blood sample") and matching them line-wide would silently
# suppress real PHI. Software test files are filtered by path instead (see
# SKIP_PATTERNS and is_test_data's path check).
TEST_DATA_MARKERS = (
    r"\bmock\b",
    r"\bfake\b",
    r"\bexample\b",
    r"\bdummy\b",
    r"\bplaceholder\b",
    r"\bNOTE:",
    r"\bchangelog\b",
    r"000-00-0000",
    r"123-45-6789",
    r"555-?\d{3}-?\d{4}",
    r"\+1555",
    r"@example\.com",
    r"@example\.org",
    r"@test\.com",
    r"@localhost",
    r"127\.0\.0\.1",
    r"0\.0\.0\.0",
)

SCANNABLE_EXTENSIONS = frozenset([
    ".py", ".js", ".ts", ".tsx", ".jsx",
    ".java", ".cs", ".go", ".rb", ".php",
    ".json", ".yaml", ".yml", ".xml",
    ".sql", ".csv", ".txt", ".md",
    ".html", ".htm", ".env", ".config",
])

SKIP_PATTERNS = (
    r"node_modules",
    r"\.git",
    r"__pycache__",
    r"\.venv",
    r"venv",
    r"dist",
    r"build",
    r"\.egg-info",
    r"/tests/",
    r"_test\.py$",
    r"\.test\.ts$",
    r"\.test\.tsx$",
    r"conftest\.py$",
    r"factories\.py$",
    r"package-lock\.json$",
    r"yarn\.lock$",
    r"poetry\.lock$",
)


# ============================================================================
# PATTERNS
# ============================================================================

PATTERNS = {
    # SSN with invalid ranges excluded
    "ssn": re.compile(r"\b(?!000|666|9\d\d)\d{3}-(?!00)\d{2}-(?!0000)\d{4}\b"),

    # Email
    "email": re.compile(
        r"(?<![a-z0-9._%+-])[a-z0-9._%+-]{1,64}@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}(?![a-z0-9])",
        re.IGNORECASE
    ),

    # US phone with parentheses support
    "phone": re.compile(
        r"(?:^|(?<=\s)|(?<=[^0-9]))(?:\+1[-.\s]?)?(?:\(\d{3}\)[-.\s]?|\d{3}[-.\s]?)\d{3}[-.\s]?\d{4}(?=\s|$|[^0-9])"
    ),

    # IPv4 with valid octets
    "ip_v4": re.compile(
        r"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"
    ),

    # US date format
    "date_us": re.compile(r"\b(0?[1-9]|1[0-2])[/-](0?[1-9]|[12]\d|3[01])[/-](\d{2}|\d{4})\b"),

    # ISO date
    "date_iso": re.compile(r"\b\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])\b"),

    # 5-digit ZIP
    "zip_5": re.compile(r"\b\d{5}\b"),
}


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class Finding:
    """A potential PHI finding."""
    file_path: str
    line_number: int
    column: int
    identifier_type: str
    value: str
    line_content: str
    is_test_data: bool = False
    restricted: bool = False


# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

def is_test_data(line: str, value: str, file_path: str = "") -> bool:
    """Check if finding appears to be test/mock data."""
    combined = f"{line} {value}".lower()
    for marker in TEST_DATA_MARKERS:
        if re.search(marker, combined, re.IGNORECASE):
            return True
    # Files in test/fixture directories are inherently test data
    if re.search(r"(/tests/|/fixtures/|conftest\.py|factories\.py|/test_)", file_path):
        return True
    return False


def should_skip_file(file_path: str) -> bool:
    """Check if file should be skipped."""
    return any(re.search(pattern, file_path) for pattern in SKIP_PATTERNS)


def should_scan_file(file_path: str) -> bool:
    """Check if file should be scanned based on extension."""
    return Path(file_path).suffix.lower() in SCANNABLE_EXTENSIONS


def scan_line(line: str, line_number: int, file_path: str) -> Iterator[Finding]:
    """Scan a single line for PHI patterns."""
    # Inline suppression: skip lines marked as safe
    if re.search(r"#\s*phi-safe|//\s*phi-safe|--\s*phi-safe|<!--\s*phi-safe\s*-->|/\*\s*phi-safe\s*\*/", line):
        return

    for identifier_type, pattern in PATTERNS.items():
        for match in pattern.finditer(line):
            value = match.group(0)

            # Special handling for ZIP codes: HIPAA Safe Harbor requires the
            # 17 restricted prefixes (population < 20,000) to be flagged as
            # higher priority than an ordinary 5-digit ZIP.
            restricted = identifier_type == "zip_5" and value[:3] in RESTRICTED_ZIP_PREFIXES

            yield Finding(
                file_path=file_path,
                line_number=line_number,
                column=match.start() + 1,
                identifier_type=identifier_type,
                value=value,
                line_content=line.rstrip(),
                is_test_data=is_test_data(line, value, file_path),
                restricted=restricted,
            )


def scan_content(content: str, file_path: str) -> list[Finding]:
    """Scan file content for PHI."""
    findings = []
    for line_num, line in enumerate(content.splitlines(), start=1):
        for finding in scan_line(line, line_num, file_path):
            findings.append(finding)
    return findings


# ============================================================================
# GIT INTEGRATION
# ============================================================================

def get_staged_files() -> list[str]:
    """Get list of staged files from git."""
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
            capture_output=True,
            text=True,
            check=True
        )
        return [f.strip() for f in result.stdout.splitlines() if f.strip()]
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []


def get_staged_content(file_path: str) -> str | None:
    """Get staged content of a file."""
    try:
        result = subprocess.run(
            ["git", "show", f":{file_path}"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


# Directory names pruned during the walk so we never descend into them.
PRUNE_DIRS = frozenset([
    "node_modules", ".git", "__pycache__", ".venv", "venv",
    "dist", "build",
])


def get_all_files(directory: str = ".") -> list[str]:
    """Get all scannable files in directory.

    Prunes large/irrelevant directories in-place so they're never traversed
    (much faster than walking everything and filtering after the fact).
    """
    files = []
    for root, dirs, filenames in os.walk(directory):
        dirs[:] = [d for d in dirs if d not in PRUNE_DIRS]
        for filename in filenames:
            str_path = os.path.join(root, filename)
            if not should_skip_file(str_path) and should_scan_file(str_path):
                files.append(str_path)
    return files


# ============================================================================
# OUTPUT
# ============================================================================

def format_findings(findings: list[Finding], verbose: bool = False) -> str:
    """Format findings for output."""
    if not findings:
        return ""

    lines = []

    # Group by file
    by_file: dict[str, list[Finding]] = {}
    for f in findings:
        by_file.setdefault(f.file_path, []).append(f)

    for file_path, file_findings in sorted(by_file.items()):
        lines.append(f"\n{file_path}:")
        for f in sorted(file_findings, key=lambda x: x.line_number):
            marker = "[TEST]" if f.is_test_data else "[PHI]"
            identifier_label = f"{f.identifier_type}(restricted)" if f.restricted else f.identifier_type
            lines.append(f"  {f.line_number}:{f.column} {marker} {identifier_label}: {f.value}")
            if verbose:
                lines.append(f"    > {f.line_content[:80]}")

    return "\n".join(lines)


# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Scan files for potential PHI before commit."
    )
    parser.add_argument(
        "--all", "-a",
        action="store_true",
        help="Scan all files, not just staged files"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show line content for each finding"
    )
    parser.add_argument(
        "--include-test-data",
        action="store_true",
        help="Include findings that appear to be test data"
    )
    parser.add_argument(
        "files",
        nargs="*",
        help="Specific files to scan (default: staged files)"
    )

    args = parser.parse_args()

    # Determine files to scan
    if args.files:
        files = args.files
    elif args.all:
        files = get_all_files()
    else:
        files = get_staged_files()

    if not files:
        print("No files to scan.")
        sys.exit(0)

    # Scan files
    all_findings: list[Finding] = []
    scanned = 0

    for file_path in files:
        if should_skip_file(file_path):
            continue
        if not should_scan_file(file_path):
            continue

        # Get content
        if args.all or args.files:
            try:
                content = Path(file_path).read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
        else:
            content = get_staged_content(file_path)
            if content is None:
                continue

        findings = scan_content(content, file_path)
        all_findings.extend(findings)
        scanned += 1

    # Filter test data unless included
    if not args.include_test_data:
        real_findings = [f for f in all_findings if not f.is_test_data]
    else:
        real_findings = all_findings

    # Output
    print("PHI Scan")
    print(f"Files scanned: {scanned}")
    print(f"Findings: {len(real_findings)} (total: {len(all_findings)})")

    if real_findings:
        print(format_findings(real_findings, verbose=args.verbose))
        print()
        print("Potential PHI detected.")
        print("Review findings and remove PHI before committing.")
        print()
        print("Use --include-test-data to see test data findings.")
        sys.exit(1)
    else:
        print("No PHI detected.")
        sys.exit(0)


if __name__ == "__main__":
    main()
