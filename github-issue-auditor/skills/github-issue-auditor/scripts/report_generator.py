"""
GitHub Issue Audit Report Generator Module.
Generates markdown reports of audit results.
"""

from datetime import datetime
from typing import Any, Dict, List, Optional


class ReportGenerator:
    """Generates markdown audit reports."""

    def generate_report(
        self,
        findings: Dict[str, List[Dict[str, Any]]],
        execution_summary: Dict[str, Any],
        config: Dict[str, Any]
    ) -> str:
        """
        Generate comprehensive markdown audit report.

        Args:
            findings: Discovered and analyzed findings
            execution_summary: Results of execution phase
            config: Configuration used for audit

        Returns:
            Markdown report string
        """
        report_lines = []

        # Header
        report_lines.append("# GitHub Issue Audit Report")
        report_lines.append("")
        report_lines.append(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report_lines.append("")

        # Executive Summary
        report_lines.extend(self._generate_executive_summary(findings, execution_summary))

        # Configuration
        report_lines.extend(self._generate_configuration_section(config))

        # Findings by Category
        report_lines.extend(self._generate_findings_section(findings))

        # Execution Summary
        report_lines.extend(self._generate_execution_section(execution_summary))

        # Recommendations
        report_lines.extend(self._generate_recommendations(findings))

        return "\n".join(report_lines)

    def _generate_executive_summary(
        self,
        findings: Dict[str, List[Dict[str, Any]]],
        execution_summary: Dict[str, Any]
    ) -> List[str]:
        """Generate executive summary section."""
        lines = []

        lines.append("## Executive Summary")
        lines.append("")

        # Calculate totals
        total_found = sum(len(findings.get(cat, [])) for cat in findings)
        total_executed = execution_summary.get('successful', 0)
        total_failed = execution_summary.get('failed', 0)

        lines.append(f"- **Total Issues Found**: {total_found}")
        lines.append(f"- **Actions Executed**: {total_executed}")
        lines.append(f"- **Actions Failed**: {total_failed}")
        lines.append("")

        # Breakdown by category
        lines.append("### Issues by Category")
        lines.append("")

        categories = {
            'duplicates': 'Duplicates (already marked)',
            'unlabeled': 'Unlabeled (need triage)',
            'stale_backlog': 'Stale Backlog',
            'orphaned': 'Orphaned Sub-Issues',
            'potential_duplicates': 'Potential Duplicates'
        }

        for key, label in categories.items():
            count = len(findings.get(key, []))
            lines.append(f"- **{label}**: {count}")

        lines.append("")

        return lines

    @staticmethod
    def _generate_configuration_section(config: Dict[str, Any]) -> List[str]:
        """Generate configuration section."""
        lines = []

        lines.append("## Audit Configuration")
        lines.append("")
        lines.append("| Setting | Value |")
        lines.append("|---------|-------|")

        lines.append(f"| Stale Threshold | {config.get('stale_threshold_days', 30)} days |")
        lines.append(f"| Similarity Threshold | {config.get('similarity_threshold', 0.75)} |")

        categories = ', '.join(config.get('categories_to_audit', ['all']))
        lines.append(f"| Categories Audited | {categories} |")

        lines.append("")

        return lines

    def _generate_findings_section(self, findings: Dict[str, List[Dict[str, Any]]]) -> List[str]:
        """Generate detailed findings section."""
        lines = []

        lines.append("## Detailed Findings")
        lines.append("")

        # Duplicates
        lines.extend(self._generate_duplicates_section(findings.get('duplicates', [])))

        # Unlabeled
        lines.extend(self._generate_unlabeled_section(findings.get('unlabeled', [])))

        # Stale Backlog
        lines.extend(self._generate_stale_backlog_section(findings.get('stale_backlog', [])))

        # Orphaned
        lines.extend(self._generate_orphaned_section(findings.get('orphaned', [])))

        # Potential Duplicates
        lines.extend(self._generate_potential_duplicates_section(findings.get('potential_duplicates', [])))

        return lines

    def _generate_duplicates_section(self, issues: List[Dict[str, Any]]) -> List[str]:
        """Generate duplicates section."""
        lines = []

        lines.append("### Duplicates (Already Marked)")
        lines.append("")

        if not issues:
            lines.append("*No duplicates found.*")
            lines.append("")
            return lines

        lines.append("| Issue | Title | Age (days) | Rationale |")
        lines.append("|-------|-------|------------|-----------|")

        for issue in issues:
            number = issue.get('number')
            title = issue.get('title', '').replace('|', '\\|')
            age = issue.get('age_days', 'N/A')
            rationale = issue.get('rationale', '').replace('|', '\\|')

            lines.append(f"| #{number} | {title} | {age} | {rationale} |")

        lines.append("")

        return lines

    def _generate_unlabeled_section(self, issues: List[Dict[str, Any]]) -> List[str]:
        """Generate unlabeled section."""
        lines = []

        lines.append("### Unlabeled Issues")
        lines.append("")

        if not issues:
            lines.append("*No unlabeled issues found.*")
            lines.append("")
            return lines

        lines.append("| Issue | Title | Suggested Labels |")
        lines.append("|-------|-------|------------------|")

        for issue in issues:
            number = issue.get('number')
            title = issue.get('title', '').replace('|', '\\|')
            labels = ', '.join(issue.get('suggested_labels', []))

            lines.append(f"| #{number} | {title} | {labels} |")

        lines.append("")

        return lines

    def _generate_stale_backlog_section(self, issues: List[Dict[str, Any]]) -> List[str]:
        """Generate stale backlog section."""
        lines = []

        lines.append("### Stale Backlog Items")
        lines.append("")

        if not issues:
            lines.append("*No stale backlog items found.*")
            lines.append("")
            return lines

        lines.append("| Issue | Title | Age (days) | Rationale |")
        lines.append("|-------|-------|------------|-----------|")

        for issue in issues:
            number = issue.get('number')
            title = issue.get('title', '').replace('|', '\\|')
            age = issue.get('age_days', 'N/A')
            rationale = issue.get('rationale', '').replace('|', '\\|')

            lines.append(f"| #{number} | {title} | {age} | {rationale} |")

        lines.append("")

        return lines

    def _generate_orphaned_section(self, issues: List[Dict[str, Any]]) -> List[str]:
        """Generate orphaned section."""
        lines = []

        lines.append("### Orphaned Sub-Issues")
        lines.append("")

        if not issues:
            lines.append("*No orphaned sub-issues found.*")
            lines.append("")
            return lines

        lines.append("| Issue | Title | Parent Issue | Rationale |")
        lines.append("|-------|-------|--------------|-----------|")

        for issue in issues:
            number = issue.get('number')
            title = issue.get('title', '').replace('|', '\\|')
            parent = issue.get('parent_issue', 'N/A')
            rationale = issue.get('rationale', '').replace('|', '\\|')

            lines.append(f"| #{number} | {title} | #{parent} | {rationale} |")

        lines.append("")

        return lines

    def _generate_potential_duplicates_section(self, pairs: List[Dict[str, Any]]) -> List[str]:
        """Generate potential duplicates section."""
        lines = []

        lines.append("### Potential Duplicates")
        lines.append("")

        if not pairs:
            lines.append("*No potential duplicates found.*")
            lines.append("")
            return lines

        lines.append("| Issue 1 | Issue 2 | Similarity | Rationale |")
        lines.append("|---------|---------|------------|-----------|")

        for pair in pairs:
            issue1 = f"#{pair.get('issue1_number')}"
            issue2 = f"#{pair.get('issue2_number')}"
            similarity = f"{int(pair.get('similarity', 0) * 100)}%"
            rationale = pair.get('rationale', '').replace('|', '\\|')

            lines.append(f"| {issue1} | {issue2} | {similarity} | {rationale} |")

        lines.append("")

        return lines

    def _generate_execution_section(self, execution_summary: Dict[str, Any]) -> List[str]:
        """Generate execution summary section."""
        lines = []

        lines.append("## Execution Summary")
        lines.append("")

        successful = execution_summary.get('successful', 0)
        failed = execution_summary.get('failed', 0)

        lines.append(f"- **Successful Actions**: {successful}")
        lines.append(f"- **Failed Actions**: {failed}")
        lines.append("")

        # Failed actions details
        failed_actions = execution_summary.get('failed_actions', [])
        if failed_actions:
            lines.append("### Failed Actions")
            lines.append("")
            lines.append("| Issue | Action | Error |")
            lines.append("|-------|--------|-------|")

            for action in failed_actions:
                issue = f"#{action.get('issue_number')}"
                action_type = action.get('action', 'unknown')
                error = action.get('error', 'Unknown error').replace('|', '\\|')

                lines.append(f"| {issue} | {action_type} | {error} |")

            lines.append("")

        return lines

    def _generate_recommendations(self, findings: Dict[str, List[Dict[str, Any]]]) -> List[str]:
        """Generate recommendations section."""
        lines = []

        lines.append("## Recommendations")
        lines.append("")

        recommendations = []

        # Check for high duplicate count
        duplicates = len(findings.get('duplicates', []))
        if duplicates > 10:
            recommendations.append(f"- **High Duplicate Count**: Found {duplicates} marked duplicates. Consider implementing duplicate detection templates or clearer issue guidelines.")

        # Check for high unlabeled count
        unlabeled = len(findings.get('unlabeled', []))
        if unlabeled > 20:
            recommendations.append(f"- **Many Unlabeled Issues**: Found {unlabeled} unlabeled issues. Implement automatic labeling or stricter triage processes.")

        # Check for stale backlog
        stale = len(findings.get('stale_backlog', []))
        if stale > 15:
            recommendations.append(f"- **Large Stale Backlog**: Found {stale} stale backlog items. Schedule regular backlog grooming sessions.")

        # Check for orphaned issues
        orphaned = len(findings.get('orphaned', []))
        if orphaned > 5:
            recommendations.append(f"- **Orphaned Sub-Issues**: Found {orphaned} orphaned sub-issues. Update workflows to close sub-issues when epics are completed.")

        # Check for potential duplicates
        potential = len(findings.get('potential_duplicates', []))
        if potential > 10:
            recommendations.append(f"- **Many Similar Issues**: Found {potential} potential duplicate pairs. Improve issue search before creation.")

        if not recommendations:
            lines.append("*No specific recommendations at this time. Issue health appears good.*")
        else:
            lines.extend(recommendations)

        lines.append("")

        return lines

    def save_report(self, report: str, filename: Optional[str] = None) -> str:
        """
        Save report to file.

        Args:
            report: Report markdown string
            filename: Optional custom filename

        Returns:
            Path to saved file
        """
        if filename is None:
            timestamp = datetime.now().strftime('%Y-%m-%d')
            filename = f"issue-audit-report-{timestamp}.md"

        with open(filename, 'w', encoding='utf-8') as f:
            f.write(report)

        return filename


def main():
    """Main entry point for testing report generator."""
    # Test data
    test_findings = {
        'duplicates': [
            {
                'number': 45,
                'title': 'Add user authentication',
                'age_days': 58,
                'rationale': 'Already marked as duplicate of #42'
            }
        ],
        'unlabeled': [
            {
                'number': 67,
                'title': 'Fix database migration issue',
                'suggested_labels': ['bug', 'priority: high']
            }
        ],
        'stale_backlog': [],
        'orphaned': [],
        'potential_duplicates': []
    }

    test_execution_summary = {
        'successful': 2,
        'failed': 0,
        'executed_actions': [],
        'failed_actions': []
    }

    test_config = {
        'stale_threshold_days': 30,
        'similarity_threshold': 0.75,
        'categories_to_audit': ['duplicates', 'unlabeled', 'stale_backlog', 'orphaned', 'potential_duplicates']
    }

    generator = ReportGenerator()
    report = generator.generate_report(test_findings, test_execution_summary, test_config)

    print("=== Generated Report ===\n")
    print(report)


if __name__ == "__main__":
    main()
