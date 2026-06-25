"""
Tailwind config analyzer module.
Extracts semantic tokens from tailwind.config.js/ts for validation.
"""

import json
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional


class TailwindConfigAnalyzer:
    """Extract and analyze semantic tokens from Tailwind configuration."""

    def __init__(self, config_path: str):
        """
        Initialize with Tailwind config file path.

        Args:
            config_path: Path to tailwind.config.js or tailwind.config.ts
        """
        self.config_path = Path(config_path)
        self.tokens: Dict[str, Any] = {}
        self._use_node_api = True  # Try Node.js API first, fallback to regex

    def extract_tokens(self) -> Dict[str, Any]:
        """
        Extract semantic tokens from Tailwind config.

        Uses Tailwind's resolveConfig API via Node.js for accurate parsing.
        Falls back to regex parsing if Node.js is unavailable.

        Returns:
            Dictionary with categorized tokens (colors, spacing, fonts, etc.)
        """
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_path}")

        # Try Node.js API first
        if self._use_node_api:
            tokens = self._extract_via_node_api()
            if tokens:
                self.tokens = tokens
                return tokens
            # Fall back to regex if Node.js fails
            self._use_node_api = False

        # Fallback: regex-based parsing
        config_content = self.config_path.read_text()
        tokens = {
            'colors': self._extract_colors(config_content),
            'spacing': self._extract_spacing(config_content),
            'fonts': self._extract_fonts(config_content),
            'borders': self._extract_borders(config_content),
            'shadows': self._extract_shadows(config_content)
        }

        self.tokens = tokens
        return tokens

    def _extract_via_node_api(self) -> Optional[Dict[str, Any]]:
        """
        Extract tokens using Tailwind's resolveConfig API via Node.js.

        This approach handles:
        - Relative imports (require('./tailwind.colors'))
        - JavaScript expressions and computations
        - Default Tailwind theme merging
        - Complex configurations

        Returns:
            Dictionary with categorized tokens or None if Node.js fails
        """
        # Node.js script to resolve Tailwind config
        node_script = """
        const path = require('path');
        const resolveConfig = require('tailwindcss/resolveConfig');

        // Change to config directory to resolve relative imports
        process.chdir(path.dirname(process.argv[1]));

        // Load and resolve config
        const config = require(process.argv[1]);
        const resolved = resolveConfig(config);

        // Extract theme tokens
        const tokens = {
            colors: resolved.theme.colors || {},
            spacing: resolved.theme.spacing || {},
            fonts: resolved.theme.fontFamily || {},
            borders: resolved.theme.borderRadius || {},
            shadows: resolved.theme.boxShadow || {}
        };

        console.log(JSON.stringify(tokens));
        """

        try:
            # Run Node.js script with config path as argument
            # Must run from config directory to resolve relative imports
            config_dir = str(self.config_path.parent.absolute())
            result = subprocess.run(
                ['node', '-e', node_script, str(self.config_path.absolute())],
                capture_output=True,
                text=True,
                timeout=10,
                check=True,
                cwd=config_dir  # Run in config directory for relative imports
            )

            # Parse JSON output
            tokens = json.loads(result.stdout)

            # Convert font arrays and flatten nested color objects
            tokens = self._normalize_tokens(tokens)

            return tokens

        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError) as e:
            # Log warning but don't fail - will fallback to regex
            print(f"Warning: Node.js API failed ({type(e).__name__}), falling back to regex parsing")
            if hasattr(e, 'stderr'):
                print(f"stderr: {e.stderr}")
            return None

    def _normalize_tokens(self, tokens: Dict[str, Any]) -> Dict[str, Any]:
        """
        Normalize tokens from resolveConfig output.

        Tailwind's resolveConfig returns nested objects for colors (e.g., blue.500)
        and arrays for fonts. This flattens them for easier validation.

        Args:
            tokens: Raw tokens from resolveConfig

        Returns:
            Normalized token dictionary
        """
        normalized = {}

        # Flatten nested color objects
        if 'colors' in tokens:
            normalized['colors'] = self._flatten_color_object(tokens['colors'])

        # Keep spacing as-is (already flat)
        if 'spacing' in tokens:
            normalized['spacing'] = tokens['spacing']

        # Fonts are already in correct format
        if 'fonts' in tokens:
            normalized['fonts'] = tokens['fonts']

        # Borders as-is
        if 'borders' in tokens:
            normalized['borders'] = tokens['borders']

        # Shadows as-is
        if 'shadows' in tokens:
            normalized['shadows'] = tokens['shadows']

        return normalized

    def _flatten_color_object(self, colors: Dict[str, Any], prefix: str = '') -> Dict[str, str]:
        """
        Flatten nested color object (e.g., {blue: {500: '#3b82f6'}}) to {blue-500: '#3b82f6'}.

        Args:
            colors: Nested color dictionary
            prefix: Current prefix for nested keys

        Returns:
            Flat color dictionary
        """
        flat = {}
        for key, value in colors.items():
            new_key = f"{prefix}-{key}" if prefix else key

            if isinstance(value, dict):
                # Recursively flatten nested objects
                flat.update(self._flatten_color_object(value, new_key))
            elif isinstance(value, str):
                # Leaf node - actual color value
                flat[new_key] = value

        return flat

    def _extract_colors(self, config_content: str) -> Dict[str, str]:
        """
        Extract color tokens from config using regex (fallback method).

        Limitations:
        - Cannot resolve require() imports (e.g., require('./tailwind.colors'))
        - Only matches simple key: 'value' pairs
        - Nested color objects (e.g., blue: { 500: '#...' }) not supported
        - JavaScript expressions not evaluated

        For full config parsing, Node.js API is preferred.
        """
        colors = {}

        # Match colors: { primary: '#3b82f6', ... }
        color_pattern = r"colors\s*:\s*{([^}]+)}"
        match = re.search(color_pattern, config_content)

        if match:
            color_block = match.group(1)
            # Extract key-value pairs
            pairs = re.findall(r"(\w+)\s*:\s*['\"]([^'\"]+)['\"]", color_block)
            for key, value in pairs:
                colors[key] = value

        return colors

    def _extract_spacing(self, config_content: str) -> Dict[str, str]:
        """
        Extract spacing tokens from config using regex (fallback method).

        Limitations: Same as _extract_colors - cannot handle imports or complex expressions.
        """
        spacing = {}

        spacing_pattern = r"spacing\s*:\s*{([^}]+)}"
        match = re.search(spacing_pattern, config_content)

        if match:
            spacing_block = match.group(1)
            pairs = re.findall(r"(\w+)\s*:\s*['\"]([^'\"]+)['\"]", spacing_block)
            for key, value in pairs:
                spacing[key] = value

        return spacing

    def _extract_fonts(self, config_content: str) -> Dict[str, List[str]]:
        """Extract font family tokens from config."""
        fonts = {}

        font_pattern = r"fontFamily\s*:\s*{([^}]+)}"
        match = re.search(font_pattern, config_content)

        if match:
            font_block = match.group(1)
            # Extract arrays: sans: ['Inter', 'system-ui']
            pairs = re.findall(r"(\w+)\s*:\s*\[([^\]]+)\]", font_block)
            for key, value in pairs:
                font_list = [f.strip().strip("'\"") for f in value.split(',')]
                fonts[key] = font_list

        return fonts

    def _extract_borders(self, config_content: str) -> Dict[str, str]:
        """Extract border radius tokens from config."""
        borders = {}

        border_pattern = r"borderRadius\s*:\s*{([^}]+)}"
        match = re.search(border_pattern, config_content)

        if match:
            border_block = match.group(1)
            pairs = re.findall(r"(\w+)\s*:\s*['\"]([^'\"]+)['\"]", border_block)
            for key, value in pairs:
                borders[key] = value

        return borders

    def _extract_shadows(self, config_content: str) -> Dict[str, str]:
        """Extract box shadow tokens from config."""
        shadows = {}

        shadow_pattern = r"boxShadow\s*:\s*{([^}]+)}"
        match = re.search(shadow_pattern, config_content)

        if match:
            shadow_block = match.group(1)
            pairs = re.findall(r"(\w+)\s*:\s*['\"]([^'\"]+)['\"]", shadow_block)
            for key, value in pairs:
                shadows[key] = value

        return shadows

    def get_token_names(self, category: str) -> List[str]:
        """
        Get list of token names for a category.

        Args:
            category: Token category (colors, spacing, fonts, etc.)

        Returns:
            List of token names
        """
        return list(self.tokens.get(category, {}).keys())

    def find_closest_token(self, arbitrary_value: str, category: str) -> Optional[str]:
        """
        Find closest matching token for an arbitrary value.

        Args:
            arbitrary_value: Arbitrary value like #3b82f6 or 16px
            category: Token category to search

        Returns:
            Best matching token name or None (only exact matches supported)
        """
        tokens = self.tokens.get(category, {})

        if not tokens:
            return None

        # Exact match only
        for token_name, token_value in tokens.items():
            if str(token_value) == arbitrary_value:
                return token_name

        # No approximate matching - would require color distance algorithm
        # for colors or semantic similarity for other values
        return None
