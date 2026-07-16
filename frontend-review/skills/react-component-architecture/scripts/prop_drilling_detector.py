"""
Prop drilling detection module.
Analyzes component trees to find deep prop passing patterns.
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List


@dataclass
class PropDrillingInstance:
    """Instance of prop drilling detected."""
    file_path: str
    line_number: int
    prop_name: str
    depth: int
    chain: List[str]
    suggestion: str


class PropDrillingDetector:
    """Detect prop drilling patterns in React components."""

    def __init__(self, source_dir: str, max_depth: int = 3):
        """
        Initialize prop drilling detector.

        Args:
            source_dir: Path to source directory
            max_depth: Maximum acceptable prop passing depth
        """
        self.source_dir = Path(source_dir)
        self.max_depth = max_depth
        self.violations: List[PropDrillingInstance] = []

    def analyze_directory(self) -> List[PropDrillingInstance]:
        """
        Analyze directory for prop drilling.

        Returns:
            List of prop drilling violations
        """
        tsx_files = list(self.source_dir.rglob("*.tsx"))

        for file_path in tsx_files:
            # Skip test files and node_modules
            if any(x in str(file_path) for x in ['node_modules', 'dist', '.next', '__tests__', '.test.', '.spec.']):
                continue

            violations = self._analyze_file(file_path)
            self.violations.extend(violations)

        return self.violations

    def _analyze_file(self, file_path: Path) -> List[PropDrillingInstance]:
        """
        Analyze single file for prop drilling.

        Args:
            file_path: Path to TSX file

        Returns:
            List of violations in this file
        """
        try:
            content = file_path.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError):
            return []

        violations = []

        # Find props being passed through multiple levels
        prop_chains = self._trace_prop_chains(content)

        for prop_name, chain in prop_chains.items():
            if len(chain) > self.max_depth:
                # Find line number where prop is first used
                line_number = self._find_prop_line(content, prop_name)

                suggestion = self._generate_suggestion(prop_name, chain)

                violations.append(PropDrillingInstance(
                    file_path=str(file_path.relative_to(self.source_dir)),
                    line_number=line_number,
                    prop_name=prop_name,
                    depth=len(chain),
                    chain=chain,
                    suggestion=suggestion
                ))

        return violations

    def _trace_prop_chains(self, content: str) -> Dict[str, List[str]]:
        """
        Trace prop passing chains.

        LIMITATION: This implementation uses regex-based pattern matching rather than
        full AST parsing. It provides depth estimates based on prop pass-through patterns
        but may not accurately represent the true component hierarchy. For production use,
        consider using TypeScript AST parsing tools like ts-morph or @typescript-eslint/parser.

        Returns:
            Dictionary mapping prop names to component chains
        """
        chains: Dict[str, List[str]] = {}

        # Extract component props destructuring
        # Pattern: ({ propName, otherProp })
        destructure_pattern = r'\(\s*\{\s*([^}]+)\}\s*(?::\s*\w+)?\s*\)'
        matches = re.finditer(destructure_pattern, content)

        props_in_component: set = set()

        for match in matches:
            props_text = match.group(1)
            # Split by comma and clean up
            props = [p.strip().split(':')[0].split('=')[0].strip() for p in props_text.split(',')]
            props_in_component.update(props)

        # Find where props are passed to child components
        # Pattern: <ChildComponent propName={propName} />
        prop_pass_pattern = r'<\w+[^>]*\s+(\w+)=\{(\w+)\}'
        matches = re.finditer(prop_pass_pattern, content)

        for match in matches:
            passed_prop = match.group(1)
            prop_value = match.group(2)

            # If prop is being passed with same name, it's likely drilling
            if passed_prop == prop_value and prop_value in props_in_component:
                if prop_value not in chains:
                    chains[prop_value] = []
                chains[prop_value].append(self._extract_component_name(content))

        # Simulate depth calculation (simplified)
        # In real implementation, would need AST parsing for accurate depth
        for prop_name in chains:
            # Count occurrences of prop being passed
            occurrences = len(re.findall(rf'\b{prop_name}=\{{{prop_name}\}}', content))
            if occurrences > 0:
                # Estimate depth based on occurrences
                chains[prop_name] = [f"Level {i+1}" for i in range(occurrences + 1)]

        return chains

    @staticmethod
    def _find_prop_line(content: str, prop_name: str) -> int:
        """Find line number where prop is first used."""
        lines = content.split('\n')
        for i, line in enumerate(lines, 1):
            if prop_name in line and ('=' in line or ':' in line):
                return i
        return 1

    def _extract_component_name(self, content: str) -> str:
        """Extract component name from content."""
        patterns = [
            r'export\s+(?:default\s+)?function\s+(\w+)',
            r'export\s+const\s+(\w+)\s*[:=]',
            r'const\s+(\w+)\s*[:=]\s*\('
        ]

        for pattern in patterns:
            match = re.search(pattern, content)
            if match:
                return match.group(1)

        return "Component"

    def _generate_suggestion(self, prop_name: str, chain: List[str]) -> str:
        """Generate refactoring suggestion."""
        suggestions = []

        # Suggest composition
        suggestions.append(f"Use composition pattern - only pass `{prop_name}` to the component that needs it")

        # Suggest Context API if depth is high
        if len(chain) > 4:
            suggestions.append(f"Consider using Context API for `{prop_name}` to avoid deep prop passing")

        # Suggest render props
        suggestions.append(f"Use render props pattern to invert control flow")

        return " OR ".join(suggestions)

    def get_summary(self) -> Dict[str, Any]:
        """
        Get summary of prop drilling violations.

        Returns:
            Dictionary with summary statistics
        """
        if not self.violations:
            return {
                'total_violations': 0,
                'max_depth': 0,
                'average_depth': 0,
                'most_drilled_props': []
            }

        depths = [v.depth for v in self.violations]
        prop_counts: Dict[str, int] = {}

        for v in self.violations:
            prop_counts[v.prop_name] = prop_counts.get(v.prop_name, 0) + 1

        most_drilled = sorted(prop_counts.items(), key=lambda x: x[1], reverse=True)[:5]

        return {
            'total_violations': len(self.violations),
            'max_depth': max(depths),
            'average_depth': sum(depths) / len(depths),
            'most_drilled_props': [{'prop': prop, 'count': count} for prop, count in most_drilled],
            'files_affected': len(set(v.file_path for v in self.violations))
        }

    def generate_report(self) -> str:
        """
        Generate markdown report of prop drilling violations.

        Returns:
            Markdown formatted report
        """
        if not self.violations:
            return "✓ No prop drilling violations detected\n"

        report = f"⚠ Prop Drilling Detected ({len(self.violations)} instances)\n"
        report += "=" * 50 + "\n\n"

        for i, v in enumerate(self.violations, 1):
            report += f"{i}. {v.file_path}:{v.line_number}\n"
            report += f"   Prop: `{v.prop_name}` (depth: {v.depth} levels)\n"
            report += f"   Chain: {' → '.join(v.chain)}\n"
            report += f"   Suggestion: {v.suggestion}\n\n"

        # Add summary
        summary = self.get_summary()
        report += "\nSummary\n"
        report += "-" * 50 + "\n"
        report += f"Total violations: {summary['total_violations']}\n"
        report += f"Max depth: {summary['max_depth']} levels\n"
        report += f"Average depth: {summary['average_depth']:.1f} levels\n"
        report += f"Files affected: {summary['files_affected']}\n"

        if summary['most_drilled_props']:
            report += "\nMost drilled props:\n"
            for prop in summary['most_drilled_props']:
                report += f"  - {prop['prop']}: {prop['count']} instances\n"

        return report
