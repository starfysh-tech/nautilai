"""
Duplicate pattern detection module.
Identifies reusable UI patterns that should be extracted as primitives.
"""

import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List


@dataclass
class DuplicatePattern:
    """Duplicate UI pattern found across components."""
    pattern_name: str
    pattern_type: str
    occurrences: int
    files: List[str]
    code_snippet: str
    suggested_primitive: str


class DuplicatePatternFinder:
    """Find duplicate UI patterns that should be extracted as primitives."""

    def __init__(self, source_dir: str, min_occurrences: int = 3):
        """
        Initialize duplicate pattern finder.

        Args:
            source_dir: Path to source directory
            min_occurrences: Minimum occurrences to consider as duplicate
        """
        self.source_dir = Path(source_dir)
        self.min_occurrences = min_occurrences
        self.patterns: List[DuplicatePattern] = []

    def _normalize_snippet(self, snippet: str) -> str:
        """Normalize whitespace for comparison, then truncate."""
        normalized = re.sub(r'\s+', ' ', snippet.strip())
        return normalized[:200]

    def analyze_directory(self) -> List[DuplicatePattern]:
        """
        Analyze directory for duplicate patterns.

        Returns:
            List of duplicate patterns found
        """
        tsx_files = list(self.source_dir.rglob("*.tsx"))

        # Skip test files and node_modules
        tsx_files = [f for f in tsx_files if not any(
            x in str(f) for x in ['node_modules', 'dist', '.next', '__tests__', '.test.', '.spec.']
        )]

        # Detect common patterns
        self._detect_button_patterns(tsx_files)
        self._detect_input_patterns(tsx_files)
        self._detect_card_patterns(tsx_files)
        self._detect_badge_patterns(tsx_files)
        self._detect_spinner_patterns(tsx_files)
        self._detect_error_message_patterns(tsx_files)
        self._detect_modal_patterns(tsx_files)
        self._detect_form_patterns(tsx_files)

        return self.patterns

    def _detect_button_patterns(self, files: List[Path]) -> None:
        """Detect duplicate button patterns."""
        button_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for button-like patterns
            button_patterns = [
                r'<button[^>]*className="[^"]*(?:bg-\w+-\d+|btn|primary|secondary)[^"]*"[^>]*>.*?</button>',
                r'<Button[^>]*(?:variant|color|type)=',
                r'<button[^>]*type="submit"[^>]*>',
                r'<button[^>]*disabled=\{.*?\}[^>]*>',
                r'<button[^>]*onClick=\{.*?\}[^>]*>'
            ]

            for pattern in button_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    button_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        # Find duplicates
        for snippet, files_list in button_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Button Pattern",
                    pattern_type="button",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<Button variant='primary' | 'secondary' | 'ghost' onClick={...} />"
                ))

    def _detect_input_patterns(self, files: List[Path]) -> None:
        """Detect duplicate input patterns."""
        input_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for input patterns
            input_patterns = [
                r'<input[^>]*type="(?:text|email|password)"[^>]*className="[^"]*"[^>]*/>',
                r'<Input[^>]*type=',
                r'<input[^>]*placeholder="[^"]*"[^>]*/>',
                r'<label[^>]*>.*?<input[^>]*>.*?</label>'
            ]

            for pattern in input_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    input_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in input_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Input Pattern",
                    pattern_type="input",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<Input type='text' | 'email' | 'password' placeholder={...} error={...} />"
                ))

    def _detect_card_patterns(self, files: List[Path]) -> None:
        """Detect duplicate card/container patterns."""
        card_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for card-like containers
            card_patterns = [
                r'<div[^>]*className="[^"]*(?:card|rounded|shadow|border)[^"]*"[^>]*>',
                r'<Card[^>]*>',
                r'<div[^>]*className="[^"]*p-\d+[^"]*"[^>]*>.*?</div>'
            ]

            for pattern in card_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    card_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in card_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Card Pattern",
                    pattern_type="card",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<Card variant='default' | 'bordered' | 'elevated'>{children}</Card>"
                ))

    def _detect_badge_patterns(self, files: List[Path]) -> None:
        """Detect duplicate badge/tag patterns."""
        badge_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for badge patterns
            badge_patterns = [
                r'<span[^>]*className="[^"]*(?:badge|tag|pill|status)[^"]*"[^>]*>',
                r'<Badge[^>]*>',
                r'<div[^>]*className="[^"]*(?:inline-flex|rounded-full)[^"]*"[^>]*>.*?</div>'
            ]

            for pattern in badge_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    badge_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in badge_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Badge Pattern",
                    pattern_type="badge",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<Badge variant='success' | 'warning' | 'error' | 'info'>{text}</Badge>"
                ))

    def _detect_spinner_patterns(self, files: List[Path]) -> None:
        """Detect duplicate loading spinner patterns."""
        spinner_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for spinner/loading patterns
            spinner_patterns = [
                r'<div[^>]*className="[^"]*(?:spinner|loading|animate-spin)[^"]*"[^>]*>',
                r'<Spinner[^>]*/>',
                r'{(?:loading|isLoading)\s*&&\s*<div[^>]*>',
                r'loading\s*\?\s*<div[^>]*>'
            ]

            for pattern in spinner_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    spinner_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in spinner_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Loading Spinner",
                    pattern_type="spinner",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<Spinner size='sm' | 'md' | 'lg' color='primary' />"
                ))

    def _detect_error_message_patterns(self, files: List[Path]) -> None:
        """Detect duplicate error message patterns."""
        error_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for error message patterns
            error_patterns = [
                r'{error\s*&&\s*<(?:div|p|span)[^>]*>',
                r'<(?:div|p|span)[^>]*className="[^"]*(?:error|text-red)[^"]*"[^>]*>',
                r'<ErrorMessage[^>]*>',
                r'error\s*\?\s*<(?:div|p|span)[^>]*>'
            ]

            for pattern in error_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    error_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in error_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Error Message",
                    pattern_type="error",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<ErrorMessage error={error} dismissible={true} />"
                ))

    def _detect_modal_patterns(self, files: List[Path]) -> None:
        """Detect duplicate modal/dialog patterns."""
        modal_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for modal patterns
            modal_patterns = [
                r'{(?:isOpen|open|showModal)\s*&&\s*<div[^>]*>',
                r'<(?:Modal|Dialog)[^>]*>',
                r'<div[^>]*className="[^"]*(?:modal|dialog|overlay|backdrop)[^"]*"[^>]*>'
            ]

            for pattern in modal_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    modal_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in modal_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Modal/Dialog",
                    pattern_type="modal",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<Dialog open={isOpen} onClose={handleClose}>{children}</Dialog>"
                ))

    def _detect_form_patterns(self, files: List[Path]) -> None:
        """Detect duplicate form patterns."""
        form_files: Dict[str, List[str]] = defaultdict(list)

        for file_path in files:
            try:
                content = file_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue

            # Look for form submit button patterns
            form_patterns = [
                r'<button[^>]*type="submit"[^>]*>(?:Submit|Save|Create|Update|Login|Sign\s*(?:in|up))',
                r'<Button[^>]*type="submit"[^>]*>',
                r'{(?:loading|isSubmitting)\s*\?\s*["\']Loading',
                r'disabled=\{(?:loading|isSubmitting)\}'
            ]

            for pattern in form_patterns:
                matches = re.finditer(pattern, content, re.DOTALL)
                for match in matches:
                    snippet = self._normalize_snippet(match.group(0))
                    form_files[snippet].append(str(file_path.relative_to(self.source_dir)))

        for snippet, files_list in form_files.items():
            if len(files_list) >= self.min_occurrences:
                self.patterns.append(DuplicatePattern(
                    pattern_name="Form Submit Button",
                    pattern_type="form_submit",
                    occurrences=len(files_list),
                    files=files_list,
                    code_snippet=snippet,
                    suggested_primitive="<SubmitButton loading={isSubmitting} loadingText='Saving...'>{text}</SubmitButton>"
                ))

    def generate_report(self) -> str:
        """
        Generate markdown report of duplicate patterns.

        Returns:
            Markdown formatted report
        """
        if not self.patterns:
            return "✓ No duplicate patterns found (or below threshold)\n"

        # Sort by occurrences (most duplicated first)
        sorted_patterns = sorted(self.patterns, key=lambda p: p.occurrences, reverse=True)

        report = f"✓ Duplicate Patterns Found ({len(sorted_patterns)} patterns)\n"
        report += "=" * 50 + "\n\n"

        for i, pattern in enumerate(sorted_patterns, 1):
            report += f"{i}. {pattern.pattern_name} ({pattern.occurrences} occurrences)\n"
            report += f"   Type: {pattern.pattern_type}\n"
            report += f"   Files: {', '.join(pattern.files[:3])}"
            if len(pattern.files) > 3:
                report += f" (+{len(pattern.files) - 3} more)"
            report += "\n"
            report += f"   Extract to: {pattern.suggested_primitive}\n\n"

        # Add summary
        report += "\nSummary\n"
        report += "-" * 50 + "\n"
        report += f"Total patterns: {len(sorted_patterns)}\n"
        report += f"Total duplications: {sum(p.occurrences for p in sorted_patterns)}\n"
        report += f"Suggested primitives: {len(sorted_patterns)}\n"

        return report

    def get_summary(self) -> Dict[str, Any]:
        """Get summary statistics."""
        return {
            'total_patterns': len(self.patterns),
            'total_duplications': sum(p.occurrences for p in self.patterns),
            'pattern_types': list({p.pattern_type for p in self.patterns}),
            'most_duplicated': max(self.patterns, key=lambda p: p.occurrences).pattern_name if self.patterns else None
        }
