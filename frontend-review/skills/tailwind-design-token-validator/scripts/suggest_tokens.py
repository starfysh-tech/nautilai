"""
Token suggestion module.
Recommends semantic token replacements for arbitrary values.
"""

import re
from typing import Any, Dict, List, Optional


class TokenSuggester:
    """Suggest semantic token replacements for arbitrary values."""

    def __init__(self, tokens: Dict[str, Any]):
        """
        Initialize with semantic tokens.

        Args:
            tokens: Dictionary of tokens from config
        """
        self.tokens = tokens

    def suggest_for_color(self, hex_value: str) -> Optional[str]:
        """
        Suggest semantic color token for hex value.

        Args:
            hex_value: Hex color value like #3b82f6

        Returns:
            Suggested token name or None
        """
        colors = self.tokens.get('colors', {})

        if not colors:
            return None

        # Check for exact match
        for token_name, token_value in colors.items():
            if token_value.lower() == hex_value.lower():
                return token_name

        # No exact match - suggest closest (simplified)
        # In production, use color distance algorithm
        return self._find_closest_color_token(hex_value, colors)

    def suggest_for_spacing(self, pixel_value: str) -> Optional[str]:
        """
        Suggest semantic spacing token for pixel value.

        Args:
            pixel_value: Pixel value like 16px

        Returns:
            Suggested token name or None
        """
        spacing = self.tokens.get('spacing', {})

        if not spacing:
            return None

        # Remove 'px' suffix
        numeric_value = pixel_value.replace('px', '').strip()

        # Check for exact match
        for token_name, token_value in spacing.items():
            if token_value.replace('px', '').strip() == numeric_value:
                return token_name

        # Check Tailwind default spacing scale
        # Tailwind uses 0.25rem = 4px scale
        try:
            pixels = int(numeric_value)
            # Common Tailwind values: 4px increments
            if pixels % 4 == 0:
                tailwind_unit = pixels // 4
                return str(tailwind_unit)
        except ValueError:
            pass

        return None

    def suggest_for_font(self, font_family: str) -> Optional[str]:
        """
        Suggest semantic font token for font family.

        Args:
            font_family: Font family string

        Returns:
            Suggested token name or None
        """
        fonts = self.tokens.get('fonts', {})

        if not fonts:
            return None

        # Check if font family matches any token
        for token_name, token_fonts in fonts.items():
            if isinstance(token_fonts, list):
                if any(font.lower() in font_family.lower() for font in token_fonts):
                    return token_name

        return None

    def _find_closest_color_token(
        self, hex_value: str, color_tokens: Dict[str, str]
    ) -> Optional[str]:
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

    @staticmethod
    def _hex_to_rgb(hex_value: str) -> Optional[tuple]:
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
            return tuple(int(hex_value[i:i+2], 16) for i in (0, 2, 4))
        except ValueError:
            return None

    def generate_suggestions(self, violations: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Generate token suggestions for all violations.

        Args:
            violations: List of violations from validator

        Returns:
            Violations with enhanced suggestions
        """
        enhanced_violations = []

        for violation in violations:
            if violation['type'] == 'arbitrary_value':
                # Extract arbitrary value from code
                code = violation['code']
                match = re.search(r'\[([^\]]+)\]', code)

                if match:
                    arbitrary_value = match.group(1)

                    # Determine type and suggest token
                    if arbitrary_value.startswith('#'):
                        suggestion = self.suggest_for_color(arbitrary_value)
                        if suggestion:
                            violation['suggestion'] = f"Use semantic token → {suggestion}"
                    elif arbitrary_value.endswith('px'):
                        suggestion = self.suggest_for_spacing(arbitrary_value)
                        if suggestion:
                            violation['suggestion'] = f"Use spacing token → {suggestion}"

            enhanced_violations.append(violation)

        return enhanced_violations
