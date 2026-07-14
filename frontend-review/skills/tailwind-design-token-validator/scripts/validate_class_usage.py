"""
Class usage validator module.
Validates Tailwind class usage and detects anti-patterns.
"""

import re
from pathlib import Path
from typing import Any, Dict, List


class TailwindClassValidator:
    """Validate Tailwind class usage against design tokens and best practices."""

    def __init__(self, tokens: Dict[str, Any]):
        """
        Initialize validator with design tokens.

        Args:
            tokens: Dictionary of semantic tokens from config
        """
        self.tokens = tokens
        self.violations: List[Dict[str, Any]] = []

    def validate_file(self, file_path: Path, lines: List[str]) -> List[Dict[str, Any]]:
        """
        Validate all Tailwind usage in a file.

        Args:
            file_path: Path to component file
            lines: Lines from file

        Returns:
            List of violations found
        """
        file_violations = []

        for line_num, line in enumerate(lines, start=1):
            # Check for arbitrary values
            file_violations.extend(
                self._check_arbitrary_values(file_path, line_num, line)
            )

            # Check for dynamic class concatenation
            file_violations.extend(
                self._check_dynamic_concatenation(file_path, line_num, line)
            )

            # Check for inline styles
            file_violations.extend(
                self._check_inline_styles(file_path, line_num, line)
            )

            # Check for responsive patterns
            file_violations.extend(
                self._check_responsive_patterns(file_path, line_num, line)
            )

            # Check class ordering
            file_violations.extend(
                self._check_class_ordering(file_path, line_num, line)
            )

        return file_violations

    def _check_arbitrary_values(
        self, file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for arbitrary values like bg-[#ff0000]."""
        violations = []

        # Pattern: class-[value]
        arbitrary_pattern = r'(bg|text|border|from|to|via)-\[([^\]]+)\]'
        matches = re.finditer(arbitrary_pattern, line)

        for match in matches:
            prefix = match.group(1)
            value = match.group(2)

            # Map prefix to token category
            category_map = {
                'bg': 'colors',
                'text': 'colors',
                'border': 'colors',
                'from': 'colors',
                'to': 'colors',
                'via': 'colors'
            }
            category = category_map.get(prefix, 'colors')

            # Check if value matches a semantic token
            if value.startswith('#') or value.startswith('rgb'):
                violations.append({
                    'file': str(file_path),
                    'line': line_num,
                    'type': 'arbitrary_value',
                    'severity': 'high',
                    'message': f"Arbitrary color value: {prefix}-[{value}]",
                    'suggestion': self._suggest_token_for_value(value, category),
                    'code': line.strip()
                })

        return violations

    @staticmethod
    def _check_dynamic_concatenation(
        file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for dynamic class concatenation that breaks purging."""
        violations = []

        # Pattern: className={`border-${variable}`}
        dynamic_pattern = r'className=\{[`"].*\$\{.*\}.*[`"]\}'
        if re.search(dynamic_pattern, line):
            violations.append({
                'file': str(file_path),
                'line': line_num,
                'type': 'dynamic_concatenation',
                'severity': 'high',
                'message': 'Dynamic class concatenation breaks Tailwind purging',
                'suggestion': 'Use safelist in tailwind.config.js or use complete class names with conditional logic',
                'code': line.strip()
            })

        return violations

    @staticmethod
    def _check_inline_styles(
        file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for inline style attributes."""
        violations = []

        # Pattern: style={{ ... }} or style="..."
        if re.search(r'style\s*=\s*[{"{\[]', line):
            violations.append({
                'file': str(file_path),
                'line': line_num,
                'type': 'inline_style',
                'severity': 'medium',
                'message': 'Inline style detected, should use Tailwind utilities',
                'suggestion': 'Replace inline styles with Tailwind utility classes',
                'code': line.strip()
            })

        return violations

    @staticmethod
    def _check_responsive_patterns(
        file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for proper mobile-first responsive patterns."""
        violations = []

        # Check for desktop-first patterns (less common but worth flagging)
        # Example: max-md: without corresponding min-md:
        # This is a simplified check
        if 'max-' in line and 'min-' not in line:
            # Could indicate desktop-first approach
            pass  # This is acceptable in some cases, so we don't flag it

        return violations

    @staticmethod
    def _check_class_ordering(
        file_path: Path, line_num: int, line: str
    ) -> List[Dict[str, Any]]:
        """Check for consistent class ordering (layout → typography → color → state)."""
        violations = []

        # Extract className attribute
        class_match = re.search(r'className=["\'`"]([^"\'`]+)["\'`"]', line)
        if not class_match:
            return violations

        classes = class_match.group(1).split()

        # Define category order
        layout_classes = {'flex', 'grid', 'block', 'inline', 'hidden', 'container', 'mx', 'my', 'px', 'py', 'p', 'm', 'w', 'h'}
        typography_classes = {'text', 'font', 'leading', 'tracking', 'uppercase', 'lowercase'}
        color_classes = {'bg', 'text', 'border'}
        state_classes = {'hover', 'focus', 'active', 'disabled'}

        # Check if classes are roughly in order (simplified check)
        # This is a basic heuristic and could be improved
        categories_seen = []
        for cls in classes:
            prefix = cls.split('-')[0] if '-' in cls else cls

            if any(layout in cls for layout in layout_classes):
                categories_seen.append('layout')
            elif any(typo in cls for typo in typography_classes):
                categories_seen.append('typography')
            elif any(color in cls for color in color_classes):
                categories_seen.append('color')
            elif any(state in cls for state in state_classes):
                categories_seen.append('state')

        # Check for ordering violations (simplified)
        # If we see color before layout, that's a potential issue
        if 'color' in categories_seen and 'layout' in categories_seen:
            color_idx = categories_seen.index('color')
            layout_idx = categories_seen.index('layout')
            if color_idx < layout_idx:
                violations.append({
                    'file': str(file_path),
                    'line': line_num,
                    'type': 'class_ordering',
                    'severity': 'low',
                    'message': 'Class ordering should follow: layout → typography → color → state',
                    'suggestion': 'Reorder classes for consistency',
                    'code': line.strip()
                })

        return violations

    @staticmethod
    def _hex_to_rgb(hex_value: str):
        """
        Convert hex color to RGB tuple.

        Args:
            hex_value: Hex color like #3b82f6

        Returns:
            (r, g, b) tuple or None
        """
        hex_value = hex_value.lstrip('#')

        if len(hex_value) == 3:
            hex_value = ''.join([c * 2 for c in hex_value])

        if len(hex_value) != 6:
            return None

        try:
            rgb = tuple(int(hex_value[i:i+2], 16) for i in (0, 2, 4))
            return rgb
        except ValueError:
            return None

    def _find_closest_color_token(
        self, hex_value: str, color_tokens: Dict[str, str]
    ):
        """
        Find closest color token by comparing RGB values.

        Args:
            hex_value: Target hex color
            color_tokens: Available color tokens

        Returns:
            Closest token name or None
        """
        if not color_tokens:
            return None

        # Convert hex to RGB
        target_rgb = self._hex_to_rgb(hex_value)
        if not target_rgb:
            return None

        min_distance = float('inf')
        closest_token = None

        for token_name, token_value in color_tokens.items():
            token_rgb = self._hex_to_rgb(token_value)
            if not token_rgb:
                continue

            # Calculate Euclidean distance
            distance = sum((a - b) ** 2 for a, b in zip(target_rgb, token_rgb)) ** 0.5

            if distance < min_distance:
                min_distance = distance
                closest_token = token_name

        return closest_token

    def _suggest_token_for_value(self, value: str, category: str) -> str:
        """Suggest semantic token for arbitrary value."""
        token_names = self.tokens.get(category, {})

        if not token_names:
            return f"Add semantic token to tailwind.config.js {category}"

        # For colors starting with '#', use RGB distance matching
        if value.startswith('#'):
            closest_token = self._find_closest_color_token(value, token_names)
            if closest_token:
                return f"Use semantic token → {category[:-1]}-{closest_token}"

        # For other categories, provide generic suggestion
        first_token = list(token_names.keys())[0]
        return f"Use semantic token → {category[:-1]}-{first_token}"

    @staticmethod
    def check_apply_overuse(css_file: Path, lines: List[str]) -> List[Dict[str, Any]]:
        """
        Check for excessive @apply usage in CSS files.

        Args:
            css_file: Path to CSS file
            lines: Lines from CSS file

        Returns:
            List of violations
        """
        violations = []
        apply_count = 0

        for line_num, line in enumerate(lines, start=1):
            if '@apply' in line:
                apply_count += 1

                # Count number of classes in @apply
                classes_match = re.search(r'@apply\s+(.*);', line)
                if classes_match:
                    num_classes = len(classes_match.group(1).split())

                    if num_classes > 5:
                        violations.append({
                            'file': str(css_file),
                            'line': line_num,
                            'type': 'apply_overuse',
                            'severity': 'medium',
                            'message': f'@apply with {num_classes} classes (consider component)',
                            'suggestion': 'Extract to reusable component instead of @apply',
                            'code': line.strip()
                        })

        # If more than 10 @apply statements in one file, flag it
        if apply_count > 10:
            violations.append({
                'file': str(css_file),
                'line': 1,
                'type': 'apply_overuse',
                'severity': 'high',
                'message': f'{apply_count} @apply statements in file (excessive)',
                'suggestion': 'Consider using components instead of @apply',
                'code': ''
            })

        return violations
