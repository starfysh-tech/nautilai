"""
Accessibility checker module.
Validates ARIA attributes, focus states, and semantic HTML.
"""

import re
from pathlib import Path
from typing import Any, Dict, List


class AccessibilityChecker:
    """Check for accessibility issues in React components."""

    def __init__(self):
        """Initialize accessibility checker."""
        self.violations: List[Dict[str, Any]] = []

    def check_file(self, file_path: Path, lines: List[str]) -> List[Dict[str, Any]]:
        """
        Check file for accessibility violations.

        Args:
            file_path: Path to component file
            lines: Lines from file

        Returns:
            List of accessibility violations
        """
        violations = []

        for line_num, line in enumerate(lines, start=1):
            violations.extend(self._check_aria_attributes(file_path, line_num, line))
            violations.extend(self._check_focus_states(file_path, line_num, line))
            violations.extend(self._check_semantic_html(file_path, line_num, line))
            violations.extend(self._check_color_contrast(file_path, line_num, line))

        return violations

    def _check_aria_attributes(
        self, file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for missing or improper ARIA attributes."""
        violations = []

        # Check buttons without aria-label when no visible text
        if '<button' in line.lower():
            # Check if button has aria-label or child text
            if 'aria-label' not in line and not re.search(r'>\s*\w+', line):
                violations.append({
                    'file': str(file_path),
                    'line': line_num,
                    'type': 'missing_aria_label',
                    'severity': 'high',
                    'message': 'Button missing aria-label (no visible text)',
                    'suggestion': 'Add aria-label or aria-labelledby attribute',
                    'code': line.strip()
                })

        # Check interactive elements without role
        if re.search(r'<div[^>]*onClick', line):
            if 'role=' not in line:
                violations.append({
                    'file': str(file_path),
                    'line': line_num,
                    'type': 'missing_role',
                    'severity': 'high',
                    'message': 'Interactive div missing role attribute',
                    'suggestion': 'Add role="button" or use <button> element',
                    'code': line.strip()
                })

        # Check images without alt text
        if '<img' in line.lower():
            if 'alt=' not in line.lower():
                violations.append({
                    'file': str(file_path),
                    'line': line_num,
                    'type': 'missing_alt_text',
                    'severity': 'high',
                    'message': 'Image missing alt attribute',
                    'suggestion': 'Add alt text or alt="" for decorative images',
                    'code': line.strip()
                })

        return violations

    def _check_focus_states(
        self, file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for proper focus state styling."""
        violations = []

        # Check if interactive elements have focus styles
        interactive_elements = ['button', 'input', 'select', 'textarea', 'a']

        for element in interactive_elements:
            if f'<{element}' in line.lower():
                # Check if className includes focus: variants
                class_match = re.search(r'className=["\'`]([^"\'`]+)["\'`]', line)
                if class_match:
                    classes = class_match.group(1)
                    if 'focus:' not in classes and 'focus-visible:' not in classes:
                        violations.append({
                            'file': str(file_path),
                            'line': line_num,
                            'type': 'missing_focus_state',
                            'severity': 'medium',
                            'message': f'{element} missing focus state styles',
                            'suggestion': 'Add focus: or focus-visible: utility classes',
                            'code': line.strip()
                        })

        return violations

    def _check_semantic_html(
        self, file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for proper semantic HTML usage."""
        violations = []

        # Check for div/span used as buttons
        if re.search(r'<(div|span)[^>]*onClick', line):
            violations.append({
                'file': str(file_path),
                'line': line_num,
                'type': 'non_semantic_element',
                'severity': 'medium',
                'message': 'Using div/span as button (non-semantic)',
                'suggestion': 'Use <button> element instead',
                'code': line.strip()
            })

        # Check for div/span used as links
        if re.search(r'<(div|span)[^>]*href=', line):
            violations.append({
                'file': str(file_path),
                'line': line_num,
                'type': 'non_semantic_element',
                'severity': 'medium',
                'message': 'Using div/span as link (non-semantic)',
                'suggestion': 'Use <a> element instead',
                'code': line.strip()
            })

        return violations

    def _check_color_contrast(
        self, file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for potential color contrast issues."""
        violations = []

        # Check for light text on light background (basic heuristic)
        if re.search(r'text-(gray|white|zinc)-[123]00', line) and re.search(r'bg-(gray|white|zinc)-[123]00', line):
            violations.append({
                'file': str(file_path),
                'line': line_num,
                'type': 'color_contrast',
                'severity': 'medium',
                'message': 'Potential color contrast issue (light text on light bg)',
                'suggestion': 'Verify WCAG AA contrast ratio (4.5:1 for text)',
                'code': line.strip()
            })

        return violations
