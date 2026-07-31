"""
Architecture reporter module.
Generates comprehensive architecture reports combining all analysis results.
"""

import json
from typing import TYPE_CHECKING, Any, Dict, List, Optional

if TYPE_CHECKING:
    from component_analyzer import ComponentAnalyzer
    from duplicate_pattern_finder import DuplicatePatternFinder
    from folder_structure_validator import FolderStructureValidator
    from prop_drilling_detector import PropDrillingDetector
else:
    from component_analyzer import ComponentAnalyzer
    from duplicate_pattern_finder import DuplicatePatternFinder
    from folder_structure_validator import FolderStructureValidator
    from prop_drilling_detector import PropDrillingDetector


class ArchitectureReporter:
    """Generate comprehensive React architecture reports."""

    def __init__(self, source_dir: str, config: Optional[Dict[str, Any]] = None):
        """
        Initialize architecture reporter.

        Args:
            source_dir: Path to source directory
            config: Optional configuration for rules and thresholds
        """
        self.source_dir = source_dir
        self.config = config or self._default_config()

        # Initialize analyzers
        self.component_analyzer = ComponentAnalyzer(
            source_dir,
            exclude_patterns=self.config.get('excluded_patterns')
        )
        self.prop_drilling_detector = PropDrillingDetector(
            source_dir,
            max_depth=self.config.get('prop_drilling_depth', 3)
        )
        self.duplicate_finder = DuplicatePatternFinder(
            source_dir,
            min_occurrences=self.config.get('min_duplicate_count', 3)
        )
        self.folder_validator = FolderStructureValidator(
            source_dir,
            rules=self.config.get('folder_structure')
        )

    @staticmethod
    def _default_config() -> Dict[str, Any]:
        """Get default configuration."""
        return {
            'component_size_limit': 200,
            'prop_drilling_depth': 3,
            'min_duplicate_count': 3,
            'folder_structure': {
                'primitives': 'components/ui',
                'features': 'features',
                'layouts': 'layouts',
                'utils': 'utils'
            },
            'excluded_patterns': [
                '**/node_modules/**',
                '**/dist/**',
                '**/.next/**',
                '**/__tests__/**'
            ],
            'type_coverage_threshold': 95,
            'complexity_threshold': 10
        }

    def generate_full_report(self) -> str:
        """
        Generate complete architecture report.

        Returns:
            Markdown formatted comprehensive report
        """
        # Run all analyses
        components = self.component_analyzer.analyze_directory()
        prop_drilling = self.prop_drilling_detector.analyze_directory()
        duplicates = self.duplicate_finder.analyze_directory()
        folder_violations = self.folder_validator.validate_directory()

        # Build report using list + join pattern
        report_lines = [
            "React Component Architecture Report",
            "=" * 50,
            f"Analyzed: {len(components)} components in {self.source_dir}",
            ""
        ]

        # Component Size Issues
        size_violations = self.component_analyzer.get_size_violations(
            self.config['component_size_limit']
        )
        if size_violations:
            report_lines.append(f"⚠ Component Size Issues ({len(size_violations)} found)")
            report_lines.append("-" * 50)
            for i, comp in enumerate(size_violations, 1):
                report_lines.append(f"{i}. {comp.file_path} ({comp.line_count} lines)")
                report_lines.append("   → Consider splitting into smaller components")
            report_lines.append("")
        else:
            report_lines.append("✓ Component Size: All components within limits")
            report_lines.append("")

        # Prop Drilling
        report_lines.append(self.prop_drilling_detector.generate_report())
        report_lines.append("")

        # Duplicate Patterns
        report_lines.append(self.duplicate_finder.generate_report())
        report_lines.append("")

        # Folder Structure
        report_lines.append(self.folder_validator.generate_report())
        report_lines.append("")

        # Type Coverage
        stats = self.component_analyzer.get_statistics()
        type_coverage = stats.get('type_coverage', 0)
        missing_types = self.component_analyzer.get_missing_types()

        if type_coverage < self.config['type_coverage_threshold']:
            report_lines.append(f"⚠ Type Coverage: {type_coverage:.0f}% ({len(missing_types)} components missing prop types)")
            report_lines.append("-" * 50)
            for comp in missing_types[:5]:  # Show first 5
                report_lines.append(f"  - {comp.file_path}")
            if len(missing_types) > 5:
                report_lines.append(f"  ... and {len(missing_types) - 5} more")
            report_lines.append("")
        else:
            report_lines.append(f"✓ Type Coverage: {type_coverage:.0f}%")
            report_lines.append("")

        # Architecture Health Score
        health_score = self._calculate_health_score(
            stats, len(prop_drilling), len(duplicates), len(folder_violations)
        )
        report_lines.append(f"Architecture Health Score: {health_score}/100")
        report_lines.append("=" * 50)
        report_lines.append(self._generate_score_breakdown(health_score, stats, prop_drilling, duplicates, folder_violations))
        report_lines.append("")

        # Recommendations
        report_lines.append("")
        report_lines.append("Recommendations:")
        report_lines.append(self._generate_recommendations(
            size_violations, prop_drilling, duplicates, folder_violations, missing_types
        ))

        return "\n".join(report_lines)

    def _calculate_health_score(
        self,
        stats: Dict[str, Any],
        prop_drilling_count: int,
        duplicate_count: int,
        folder_violations_count: int
    ) -> int:
        """
        Calculate overall architecture health score (0-100).

        Args:
            stats: Component statistics
            prop_drilling_count: Number of prop drilling violations
            duplicate_count: Number of duplicate patterns
            folder_violations_count: Number of folder violations

        Returns:
            Health score (0-100)
        """
        score = 100

        # Deduct for type coverage
        type_coverage = stats.get('type_coverage', 100)
        score -= max(0, (100 - type_coverage) * 0.5)  # Max -50 points

        # Deduct for component size violations
        total_components = stats.get('total_components', 1)
        size_violations = len(self.component_analyzer.get_size_violations(self.config['component_size_limit']))
        size_violation_ratio = size_violations / total_components
        score -= size_violation_ratio * 20  # Max -20 points

        # Deduct for prop drilling
        prop_drilling_ratio = prop_drilling_count / total_components
        score -= min(prop_drilling_ratio * 30, 15)  # Max -15 points

        # Deduct for duplicate patterns (fewer is worse, as we want to extract them)
        # This is actually GOOD - we found patterns to extract
        # So we don't deduct much
        score -= min(duplicate_count * 0.5, 5)  # Max -5 points

        # Deduct for folder violations
        folder_violation_ratio = folder_violations_count / total_components
        score -= folder_violation_ratio * 10  # Max -10 points

        return max(0, int(score))

    def _generate_score_breakdown(
        self,
        health_score: int,
        stats: Dict[str, Any],
        prop_drilling: List,
        duplicates: List,
        folder_violations: List
    ) -> str:
        """Generate score breakdown."""
        total_components = stats.get('total_components', 1)
        type_coverage = stats.get('type_coverage', 0)
        size_violations = len(self.component_analyzer.get_size_violations(self.config['component_size_limit']))

        breakdown_lines = []

        # Folder structure
        folder_score = 100 if len(folder_violations) == 0 else max(0, 100 - (len(folder_violations) / total_components * 100))
        symbol = "✓" if folder_score >= 90 else "⚠"
        breakdown_lines.append(f"{symbol} Folder structure ({folder_score:.0f}%)")

        # Component size
        size_score = max(0, 100 - (size_violations / total_components * 100))
        symbol = "✓" if size_score >= 90 else "⚠"
        breakdown_lines.append(f"{symbol} Component size ({size_score:.0f}%)")

        # Type coverage
        symbol = "✓" if type_coverage >= 95 else "⚠"
        breakdown_lines.append(f"{symbol} Type coverage ({type_coverage:.0f}%)")

        # Prop drilling
        prop_score = max(0, 100 - (len(prop_drilling) / total_components * 100))
        symbol = "✓" if prop_score >= 90 else "⚠"
        breakdown_lines.append(f"{symbol} Prop drilling ({prop_score:.0f}%)")

        # Duplicates (this is actually good to find)
        duplicate_score = 95 if len(duplicates) > 0 else 100
        symbol = "✓"
        breakdown_lines.append(f"{symbol} Duplicate patterns identified ({duplicate_score:.0f}%)")

        return "\n".join(breakdown_lines)

    @staticmethod
    def _generate_recommendations(
        size_violations: List,
        prop_drilling: List,
        duplicates: List,
        folder_violations: List,
        missing_types: List
    ) -> str:
        """Generate actionable recommendations."""
        recommendations = []

        if duplicates:
            recommendations.append(
                f"1. Extract {len(duplicates)} duplicate patterns to /components/ui as reusable primitives"
            )

        if size_violations:
            recommendations.append(
                f"2. Split {len(size_violations)} large components into smaller, focused components"
            )

        if missing_types:
            recommendations.append(
                f"3. Add TypeScript interfaces to {len(missing_types)} components for type safety"
            )

        if prop_drilling:
            recommendations.append(
                f"4. Refactor {len(prop_drilling)} prop drilling instances using composition or Context API"
            )

        if folder_violations:
            recommendations.append(
                f"5. Reorganize {len(folder_violations)} components to correct folder locations"
            )

        if not recommendations:
            recommendations.append("1. Architecture looks good! Continue following best practices.")

        return "\n".join(recommendations) + "\n"

    def export_json(self, output_path: str) -> None:
        """
        Export report as JSON for CI/CD integration.

        Args:
            output_path: Path to save JSON file
        """
        # Run analyses
        components = self.component_analyzer.analyze_directory()
        prop_drilling = self.prop_drilling_detector.analyze_directory()
        duplicates = self.duplicate_finder.analyze_directory()
        folder_violations = self.folder_validator.validate_directory()

        stats = self.component_analyzer.get_statistics()
        health_score = self._calculate_health_score(
            stats, len(prop_drilling), len(duplicates), len(folder_violations)
        )

        # Build JSON structure
        report_data = {
            'health_score': health_score,
            'statistics': stats,
            'violations': {
                'component_size': len(self.component_analyzer.get_size_violations(self.config['component_size_limit'])),
                'prop_drilling': len(prop_drilling),
                'folder_structure': len(folder_violations),
                'missing_types': len(self.component_analyzer.get_missing_types())
            },
            'duplicates_found': len(duplicates),
            'components_analyzed': len(components),
            'is_passing': health_score >= 70
        }

        with open(output_path, 'w') as f:
            json.dump(report_data, f, indent=2)

    def check_ci_gates(self, min_health_score: int = 70) -> bool:
        """
        Check if architecture passes CI gates.

        Args:
            min_health_score: Minimum acceptable health score

        Returns:
            True if passing, False otherwise
        """
        # Run minimal analysis for CI (populates analyzer state used below)
        self.component_analyzer.analyze_directory()
        prop_drilling = self.prop_drilling_detector.analyze_directory()
        duplicates = self.duplicate_finder.analyze_directory()
        folder_violations = self.folder_validator.validate_directory()

        stats = self.component_analyzer.get_statistics()
        health_score = self._calculate_health_score(
            stats, len(prop_drilling), len(duplicates), len(folder_violations)
        )

        return health_score >= min_health_score
