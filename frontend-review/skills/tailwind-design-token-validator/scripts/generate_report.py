"""
Report generator module.
Outputs formatted violation reports with fixes.
"""

import json
from collections import defaultdict
from typing import Any, Dict, List


class ReportGenerator:
    """Generate formatted violation reports."""

    def __init__(self, violations: List[Dict[str, Any]]):
        """
        Initialize with violations list.

        Args:
            violations: List of violations from validation
        """
        self.violations = violations

    def generate_text_report(self) -> str:
        """
        Generate human-readable text report.

        Returns:
            Formatted text report
        """
        if not self.violations:
            return "✓ No violations found - all checks passed!"

        report_lines = [
            "Design Token Validation Report",
            "=" * 60,
            ""
        ]

        # Group violations by file
        by_file = defaultdict(list)
        for violation in self.violations:
            by_file[violation['file']].append(violation)

        # Sort files alphabetically
        for file_path in sorted(by_file.keys()):
            file_violations = by_file[file_path]

            # Count violations by severity
            high = sum(1 for v in file_violations if v['severity'] == 'high')
            medium = sum(1 for v in file_violations if v['severity'] == 'medium')
            low = sum(1 for v in file_violations if v['severity'] == 'low')

            report_lines.append(f"✗ {file_path}")
            report_lines.append(f"  Violations: {high} high, {medium} medium, {low} low")
            report_lines.append("")

            # List each violation
            for violation in sorted(file_violations, key=lambda v: v['line']):
                severity_icon = {
                    'high': '🔴',
                    'medium': '🟡',
                    'low': '🟢'
                }[violation['severity']]

                report_lines.append(f"  {severity_icon} Line {violation['line']}: {violation['message']}")
                if violation['suggestion']:
                    report_lines.append(f"     → {violation['suggestion']}")
                if violation.get('code'):
                    report_lines.append(f"     Code: {violation['code'][:80]}")
                report_lines.append("")

        # Summary
        report_lines.append("=" * 60)
        report_lines.append(f"Summary: {len(self.violations)} total violations")

        by_type = defaultdict(int)
        by_severity = defaultdict(int)

        for v in self.violations:
            by_type[v['type']] += 1
            by_severity[v['severity']] += 1

        report_lines.append("")
        report_lines.append("By Type:")
        for vtype, count in sorted(by_type.items(), key=lambda x: -x[1]):
            report_lines.append(f"  - {vtype}: {count}")

        report_lines.append("")
        report_lines.append("By Severity:")
        for severity, count in sorted(by_severity.items()):
            report_lines.append(f"  - {severity}: {count}")

        return "\n".join(report_lines)

    def generate_json_report(self) -> str:
        """
        Generate JSON report for CI/CD integration.

        Returns:
            JSON formatted report
        """
        summary = {
            'total_violations': len(self.violations),
            'by_severity': self._count_by_severity(),
            'by_type': self._count_by_type(),
            'by_file': self._count_by_file()
        }

        report = {
            'summary': summary,
            'violations': self.violations
        }

        return json.dumps(report, indent=2)

    def generate_markdown_report(self) -> str:
        """
        Generate markdown report for documentation.

        Returns:
            Markdown formatted report
        """
        if not self.violations:
            return "## ✓ No violations found\n\nAll design token checks passed!"

        md_lines = [
            "# Design Token Validation Report",
            "",
            "## Summary",
            "",
            f"**Total Violations**: {len(self.violations)}",
            ""
        ]

        # Summary table
        md_lines.append("| Severity | Count |")
        md_lines.append("|----------|-------|")
        for severity, count in self._count_by_severity().items():
            md_lines.append(f"| {severity.title()} | {count} |")
        md_lines.append("")

        # Violations by file
        md_lines.append("## Violations by File")
        md_lines.append("")

        by_file = defaultdict(list)
        for violation in self.violations:
            by_file[violation['file']].append(violation)

        for file_path in sorted(by_file.keys()):
            md_lines.append(f"### `{file_path}`")
            md_lines.append("")

            file_violations = by_file[file_path]
            for violation in sorted(file_violations, key=lambda v: v['line']):
                severity_badge = {
                    'high': '🔴',
                    'medium': '🟡',
                    'low': '🟢'
                }[violation['severity']]

                md_lines.append(f"**{severity_badge} Line {violation['line']}**: {violation['message']}")
                if violation['suggestion']:
                    md_lines.append(f"  - **Fix**: {violation['suggestion']}")
                if violation.get('code'):
                    md_lines.append(f"  - **Code**: `{violation['code']}`")
                md_lines.append("")

        return "\n".join(md_lines)

    def _count_by_severity(self) -> Dict[str, int]:
        """Count violations by severity."""
        counts = defaultdict(int)
        for v in self.violations:
            counts[v['severity']] += 1
        return dict(counts)

    def _count_by_type(self) -> Dict[str, int]:
        """Count violations by type."""
        counts = defaultdict(int)
        for v in self.violations:
            counts[v['type']] += 1
        return dict(counts)

    def _count_by_file(self) -> Dict[str, int]:
        """Count violations by file."""
        counts = defaultdict(int)
        for v in self.violations:
            counts[v['file']] += 1
        return dict(counts)

    def save_report(self, output_path: str, format: str = 'text') -> None:
        """
        Save report to file.

        Args:
            output_path: Path to output file
            format: Report format (text, json, markdown)
        """
        if format == 'json':
            content = self.generate_json_report()
        elif format == 'markdown':
            content = self.generate_markdown_report()
        else:
            content = self.generate_text_report()

        with open(output_path, 'w') as f:
            f.write(content)
