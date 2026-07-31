"""
Component analysis module for React TSX files.
Parses components and extracts metrics like size, complexity, and structure.
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class ComponentMetrics:
    """Metrics for a single component."""
    file_path: str
    component_name: str
    line_count: int
    prop_count: int
    has_prop_types: bool
    has_typescript_interface: bool
    state_count: int
    effect_count: int
    jsx_depth: int
    imports_count: int
    cyclomatic_complexity: int


class ComponentAnalyzer:
    """Analyze React TSX components for size, complexity, and structure."""

    def __init__(self, source_dir: str, exclude_patterns: Optional[List[str]] = None):
        """
        Initialize component analyzer.

        Args:
            source_dir: Path to source directory to analyze
            exclude_patterns: Glob patterns to exclude (e.g., node_modules, dist)
        """
        self.source_dir = Path(source_dir)
        self.exclude_patterns = exclude_patterns or [
            "**/node_modules/**",
            "**/dist/**",
            "**/.next/**",
            "**/__tests__/**",
            "**/*.test.tsx",
            "**/*.spec.tsx"
        ]
        self.components: List[ComponentMetrics] = []

    def analyze_directory(self) -> List[ComponentMetrics]:
        """
        Analyze all TSX files in directory.

        Returns:
            List of component metrics
        """
        tsx_files = self._find_tsx_files()

        for file_path in tsx_files:
            metrics = self._analyze_file(file_path)
            if metrics:
                self.components.append(metrics)

        return self.components

    def _find_tsx_files(self) -> List[Path]:
        """Find all TSX files, excluding patterns."""
        all_files = list(self.source_dir.rglob("*.tsx"))

        filtered_files = []
        for file_path in all_files:
            # Check if file matches any exclude pattern
            excluded = False
            for pattern in self.exclude_patterns:
                if file_path.match(pattern):
                    excluded = True
                    break

            if not excluded:
                filtered_files.append(file_path)

        return filtered_files

    def _analyze_file(self, file_path: Path) -> Optional[ComponentMetrics]:
        """
        Analyze single TSX file.

        Args:
            file_path: Path to TSX file

        Returns:
            ComponentMetrics or None if not a valid component
        """
        try:
            content = file_path.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError):
            return None

        # Extract component name
        component_name = self._extract_component_name(content, file_path)
        if not component_name:
            return None

        # Count lines (excluding empty lines and comments)
        # Remove block comments first
        content_without_blocks = re.sub(r'/\*[\s\S]*?\*/', '', content)
        lines = [line for line in content_without_blocks.split('\n') if line.strip() and not line.strip().startswith('//')]
        line_count = len(lines)

        # Detect prop count
        prop_count = self._count_props(content)

        # Check for TypeScript interface
        has_typescript_interface = self._has_typescript_interface(content, component_name)
        has_prop_types = has_typescript_interface or 'PropTypes' in content

        # Count React hooks
        state_count = content.count('useState')
        effect_count = content.count('useEffect')

        # Calculate JSX nesting depth
        jsx_depth = self._calculate_jsx_depth(content)

        # Count imports
        imports_count = len(re.findall(r'^import\s', content, re.MULTILINE))

        # Calculate cyclomatic complexity (simplified)
        cyclomatic_complexity = self._calculate_complexity(content)

        return ComponentMetrics(
            file_path=str(file_path.relative_to(self.source_dir)),
            component_name=component_name,
            line_count=line_count,
            prop_count=prop_count,
            has_prop_types=has_prop_types,
            has_typescript_interface=has_typescript_interface,
            state_count=state_count,
            effect_count=effect_count,
            jsx_depth=jsx_depth,
            imports_count=imports_count,
            cyclomatic_complexity=cyclomatic_complexity
        )

    @staticmethod
    def _extract_component_name(content: str, file_path: Path) -> Optional[str]:
        """Extract component name from file content."""
        # Try to find function/const component declaration
        patterns = [
            r'export\s+(?:default\s+)?function\s+(\w+)',
            r'export\s+const\s+(\w+)\s*[:=]',
            r'const\s+(\w+)\s*[:=]\s*\(',
            r'function\s+(\w+)\s*\('
        ]

        for pattern in patterns:
            match = re.search(pattern, content)
            if match:
                return match.group(1)

        # Fallback to filename
        return file_path.stem

    def _count_props(self, content: str) -> int:
        """Count number of props in component."""
        # Find props interface or type
        interface_match = re.search(r'interface\s+\w+Props\s*\{([^}]+)\}', content, re.DOTALL)
        type_match = re.search(r'type\s+\w+Props\s*=\s*\{([^}]+)\}', content, re.DOTALL)

        props_block = None
        if interface_match:
            props_block = interface_match.group(1)
        elif type_match:
            props_block = type_match.group(1)

        if props_block:
            # Count properties (lines with : or ;)
            prop_lines = [line for line in props_block.split('\n') if ':' in line or ';' in line]
            return len(prop_lines)

        # Fallback: try to find destructured props
        destructure_match = re.search(r'\(\s*\{([^}]+)\}\s*\)', content)
        if destructure_match:
            props = destructure_match.group(1).split(',')
            return len([p for p in props if p.strip()])

        return 0

    def _has_typescript_interface(self, content: str, component_name: str) -> bool:
        """Check if component has TypeScript interface for props."""
        interface_patterns = [
            rf'interface\s+{component_name}Props',
            r'interface\s+\w+Props',
            rf'type\s+{component_name}Props',
            r'type\s+\w+Props\s*='
        ]

        for pattern in interface_patterns:
            if re.search(pattern, content):
                return True

        return False

    def _calculate_jsx_depth(self, content: str) -> int:
        """
        Calculate maximum JSX nesting depth.

        Note: This is a heuristic-based approximation that filters out string literals
        and comments before counting < and > characters. It may not be 100% accurate
        for all edge cases (e.g., complex template literals with JSX-like syntax),
        but provides a reasonable estimate for most React components.
        """
        max_depth = 0
        current_depth = 0

        # Remove block comments
        filtered_content = re.sub(r'/\*[\s\S]*?\*/', '', content)
        # Remove line comments
        filtered_content = re.sub(r'//.*$', '', filtered_content, flags=re.MULTILINE)
        # Remove string literals (both single and double quotes)
        filtered_content = re.sub(r'"(?:[^"\\]|\\.)*"', '', filtered_content)
        filtered_content = re.sub(r"'(?:[^'\\]|\\.)*'", '', filtered_content)
        # Remove template literals
        filtered_content = re.sub(r'`(?:[^`\\]|\\.)*`', '', filtered_content)

        # Simple depth calculation based on < and >
        for char in filtered_content:
            if char == '<':
                current_depth += 1
                max_depth = max(max_depth, current_depth)
            elif char == '>':
                current_depth = max(0, current_depth - 1)

        # Normalize (divide by 2 since we count opening and closing)
        return max_depth // 2

    def _calculate_complexity(self, content: str) -> int:
        """
        Calculate cyclomatic complexity.

        Simplified calculation based on control flow statements.
        """
        complexity = 1  # Base complexity

        # Count decision points
        patterns = [
            r'\bif\s*\(',
            r'\belse\s+if\s*\(',
            r'\belse\b',
            r'\bfor\s*\(',
            r'\bwhile\s*\(',
            r'\bswitch\s*\(',
            r'\bcase\s+',
            r'\bcatch\s*\(',
            r'\?\s*.+\s*:',  # Ternary operator
            r'&&',  # Logical AND
            r'\|\|'  # Logical OR
        ]

        for pattern in patterns:
            complexity += len(re.findall(pattern, content))

        return complexity

    def get_size_violations(self, max_lines: int = 200) -> List[ComponentMetrics]:
        """Get components exceeding size limit."""
        return [c for c in self.components if c.line_count > max_lines]

    def get_complexity_violations(self, max_complexity: int = 10) -> List[ComponentMetrics]:
        """Get components exceeding complexity limit."""
        return [c for c in self.components if c.cyclomatic_complexity > max_complexity]

    def get_missing_types(self) -> List[ComponentMetrics]:
        """Get components missing TypeScript prop types."""
        return [c for c in self.components if not c.has_typescript_interface and c.prop_count > 0]

    def get_statistics(self) -> Dict[str, Any]:
        """
        Get overall statistics.

        Returns:
            Dictionary with aggregate statistics
        """
        if not self.components:
            return {
                'total_components': 0,
                'average_size': 0,
                'type_coverage': 0,
                'average_complexity': 0
            }

        total = len(self.components)
        typed_components = len([c for c in self.components if c.has_typescript_interface])

        return {
            'total_components': total,
            'average_size': sum(c.line_count for c in self.components) / total,
            'max_size': max(c.line_count for c in self.components),
            'min_size': min(c.line_count for c in self.components),
            'type_coverage': (typed_components / total) * 100,
            'average_complexity': sum(c.cyclomatic_complexity for c in self.components) / total,
            'average_props': sum(c.prop_count for c in self.components) / total,
            'average_state_hooks': sum(c.state_count for c in self.components) / total,
            'average_effect_hooks': sum(c.effect_count for c in self.components) / total
        }
