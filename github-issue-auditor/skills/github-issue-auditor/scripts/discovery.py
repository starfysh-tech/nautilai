"""
GitHub Issue Discovery Module.
Runs gh CLI queries to discover issues across 5 categories.
"""

import json
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

# Default label names. These are the repo conventions the original skill assumed.
# They are configurable (see DiscoveryEngine.__init__) so the auditor can pass the
# taxonomy it detected for the target repo (SKILL.md Phase 1) instead of assuming.
DEFAULT_DUPLICATE_LABEL = "status: duplicate"
DEFAULT_BACKLOG_LABEL = "status: backlog"


class DiscoveryEngine:
    """Orchestrates discovery queries across all categories."""

    def __init__(
        self,
        stale_threshold_days: int = 30,
        duplicate_label: str = DEFAULT_DUPLICATE_LABEL,
        backlog_label: str = DEFAULT_BACKLOG_LABEL,
    ):
        """
        Initialize discovery engine.

        Args:
            stale_threshold_days: Days threshold for stale backlog detection
            duplicate_label: Label marking already-known duplicates in this repo
            backlog_label: Label marking backlog items in this repo
        """
        self.stale_threshold_days = stale_threshold_days
        self.duplicate_label = duplicate_label
        self.backlog_label = backlog_label
        self.gh_wrapper = GitHubCLIWrapper()

    def check_prerequisites(self) -> bool:
        """
        Check if prerequisites are met (gh CLI installed, in repository).

        Returns:
            True if prerequisites met, False otherwise
        """
        if not self.gh_wrapper.check_gh_installed():
            print("Error: GitHub CLI (gh) is not installed.")
            print("Install from: https://cli.github.com/")
            return False

        if not self.gh_wrapper.check_in_repository():
            print("Error: Not in a GitHub repository.")
            print("Navigate to a repository root directory and try again.")
            return False

        return True

    def discover_all(self) -> Dict[str, List[Dict[str, Any]]]:
        """
        Run all discovery queries and return findings.

        Returns:
            Dictionary with categories as keys and issue lists as values
        """
        print("Starting discovery phase...")

        # find_unlabeled and find_orphaned both need the full open-issue list;
        # fetch it once here and pass it to both instead of issuing the same
        # `gh issue list` query twice.
        open_issues = self._fetch_open_issues()

        findings = {
            'duplicates': self.find_duplicates(),
            'unlabeled': self.find_unlabeled(open_issues),
            'stale_backlog': self.find_stale_backlog(),
            'orphaned': self.find_orphaned(open_issues),
            'potential_duplicates': []  # Computed in analyzer
        }

        print("\nDiscovery complete:")
        print(f"  - Duplicates: {len(findings['duplicates'])}")
        print(f"  - Unlabeled: {len(findings['unlabeled'])}")
        print(f"  - Stale Backlog: {len(findings['stale_backlog'])}")
        print(f"  - Orphaned: {len(findings['orphaned'])}")

        return findings

    def find_duplicates(self) -> List[Dict[str, Any]]:
        """
        Find issues labeled as duplicates (self.duplicate_label).

        Returns:
            List of issue dictionaries
        """
        print("  Finding duplicates...", end=" ", flush=True)

        cmd = [
            'gh', 'issue', 'list',
            '--state', 'open',
            '--label', self.duplicate_label,
            '--json', 'number,title,createdAt,body,labels',
            '--limit', '1000'
        ]

        issues = self.gh_wrapper.run_gh_command(cmd)
        print(f"✓ {len(issues)} found")
        return issues

    def _fetch_open_issues(self) -> List[Dict[str, Any]]:
        """
        Fetch all open issues (unfiltered by label).

        Returns:
            List of issue dictionaries
        """
        cmd = [
            'gh', 'issue', 'list',
            '--state', 'open',
            '--json', 'number,title,createdAt,body,labels',
            '--limit', '1000'
        ]
        return self.gh_wrapper.run_gh_command(cmd)

    def find_unlabeled(self, open_issues: Optional[List[Dict[str, Any]]] = None) -> List[Dict[str, Any]]:
        """
        Find issues with zero labels.

        Args:
            open_issues: Pre-fetched open issues to filter (avoids a duplicate
                `gh issue list` call when the caller already has the list).
                Fetched if not provided.

        Returns:
            List of issue dictionaries
        """
        print("  Finding unlabeled...", end=" ", flush=True)

        all_issues = open_issues if open_issues is not None else self._fetch_open_issues()
        unlabeled = [issue for issue in all_issues if len(issue.get('labels', [])) == 0]

        print(f"✓ {len(unlabeled)} found")
        return unlabeled

    def find_stale_backlog(self) -> List[Dict[str, Any]]:
        """
        Find backlog issues older than threshold.

        Returns:
            List of issue dictionaries
        """
        print(f"  Finding stale backlog (>{self.stale_threshold_days} days)...", end=" ", flush=True)

        cmd = [
            'gh', 'issue', 'list',
            '--state', 'open',
            '--label', self.backlog_label,
            '--json', 'number,title,createdAt,body,labels',
            '--limit', '1000'
        ]

        all_backlog = self.gh_wrapper.run_gh_command(cmd)

        # Filter by age
        # tz-aware threshold: createdAt is offset-aware (...+00:00), so this must be too.
        threshold_date = datetime.now(timezone.utc) - timedelta(days=self.stale_threshold_days)
        stale = []

        for issue in all_backlog:
            created_at = datetime.fromisoformat(issue['createdAt'].replace('Z', '+00:00'))
            if created_at < threshold_date:
                stale.append(issue)

        print(f"✓ {len(stale)} found")
        return stale

    def find_orphaned(self, open_issues: Optional[List[Dict[str, Any]]] = None) -> List[Dict[str, Any]]:
        """
        Find orphaned sub-issues (parent is closed).

        Args:
            open_issues: Pre-fetched open issues to scan (avoids a duplicate
                `gh issue list` call when the caller already has the list).
                Fetched if not provided.

        Returns:
            List of issue dictionaries with parent_issue field added
        """
        print("  Finding orphaned sub-issues...", end=" ", flush=True)

        all_issues = open_issues if open_issues is not None else self._fetch_open_issues()

        # Parent reference patterns
        patterns = [
            "part of #",
            "epic: #",
            "parent: #",
            "subtask of #"
        ]

        orphaned = []
        # Cache parent-status lookups: many issues reference the same parent, and
        # each _is_parent_closed() is a separate `gh` call (N+1 otherwise).
        parent_closed: Dict[int, bool] = {}

        for issue in all_issues:
            body = issue.get('body', '').lower()

            # Check if issue references a parent
            for pattern in patterns:
                if pattern in body:
                    # Extract parent issue number
                    parent_number = self._extract_parent_number(body, pattern)
                    if parent_number is None:
                        continue
                    if parent_number not in parent_closed:
                        parent_closed[parent_number] = self._is_parent_closed(parent_number)
                    if parent_closed[parent_number]:
                        issue['parent_issue'] = parent_number
                        orphaned.append(issue)
                        break

        print(f"✓ {len(orphaned)} found")
        return orphaned

    @staticmethod
    def _extract_parent_number(body: str, pattern: str) -> Optional[int]:
        """
        Extract parent issue number from body text.

        Args:
            body: Issue body text (lowercase)
            pattern: Pattern to search for (e.g., "part of #")

        Returns:
            Parent issue number or None
        """
        try:
            idx = body.index(pattern)
            # Extract number after pattern
            num_start = idx + len(pattern)
            num_str = ''
            for char in body[num_start:]:
                if char.isdigit():
                    num_str += char
                else:
                    break
            return int(num_str) if num_str else None
        except (ValueError, IndexError):
            return None

    def _is_parent_closed(self, issue_number: int) -> bool:
        """
        Check if parent issue is closed.

        Args:
            issue_number: Issue number to check

        Returns:
            True if closed, False otherwise
        """
        cmd = ['gh', 'issue', 'view', str(issue_number), '--json', 'state']

        try:
            result = self.gh_wrapper.run_gh_command(cmd)
            return result.get('state', '').upper() == 'CLOSED'
        except subprocess.CalledProcessError:
            # Issue not found or error
            return False


class GitHubCLIWrapper:
    """Wrapper for GitHub CLI commands."""

    def check_gh_installed(self) -> bool:
        """
        Check if gh CLI is installed.

        Returns:
            True if installed, False otherwise
        """
        try:
            subprocess.run(
                ['gh', '--version'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def check_in_repository(self) -> bool:
        """
        Check if current directory is in a GitHub repository.

        Returns:
            True if in repository, False otherwise
        """
        try:
            subprocess.run(
                ['gh', 'repo', 'view', '--json', 'name'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False

    def run_gh_command(self, cmd: List[str]) -> Any:
        """
        Run a gh CLI command and return parsed JSON output.

        Args:
            cmd: Command list to execute

        Returns:
            Parsed JSON output

        Raises:
            subprocess.CalledProcessError: If command fails
        """
        try:
            result = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
                text=True
            )
            return json.loads(result.stdout)
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON from gh command: {e}", file=sys.stderr)
            return [] if '--list' in ' '.join(cmd) else {}
        except subprocess.CalledProcessError as e:
            print(f"Error running gh command: {e.stderr}", file=sys.stderr)
            raise


def main():
    """Main entry point for testing discovery module."""
    engine = DiscoveryEngine(stale_threshold_days=30)

    if not engine.check_prerequisites():
        sys.exit(1)

    findings = engine.discover_all()

    print("\n=== Discovery Results ===")
    print(json.dumps(findings, indent=2, default=str))


if __name__ == "__main__":
    main()
