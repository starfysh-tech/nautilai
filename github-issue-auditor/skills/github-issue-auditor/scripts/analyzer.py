"""
GitHub Issue Analyzer Module.
Analyzes discovered issues using Levenshtein distance and pattern matching.
"""

import re
from datetime import datetime
from typing import Any, Dict, List, Optional


class IssueAnalyzer:
    """Analyzes issues and suggests actions."""

    def __init__(self, similarity_threshold: float = 0.75):
        """
        Initialize issue analyzer.

        Args:
            similarity_threshold: Minimum similarity for potential duplicates (0.0-1.0)
        """
        self.similarity_threshold = similarity_threshold
        self.title_similarity = TitleSimilarity()

    def analyze_findings(self, findings: Dict[str, List[Dict[str, Any]]]) -> Dict[str, List[Dict[str, Any]]]:
        """
        Analyze all findings and add suggested actions.

        Args:
            findings: Dictionary of discovered issues by category

        Returns:
            Findings with added suggested_action and rationale fields
        """
        print("\nStarting analysis phase...")

        # Analyze each category
        findings['duplicates'] = self._analyze_duplicates(findings.get('duplicates', []))
        findings['unlabeled'] = self._analyze_unlabeled(findings.get('unlabeled', []))
        findings['stale_backlog'] = self._analyze_stale_backlog(findings.get('stale_backlog', []))
        findings['orphaned'] = self._analyze_orphaned(findings.get('orphaned', []))

        # Compute potential duplicates
        all_open_issues = self._get_all_open_issues(findings)
        findings['potential_duplicates'] = self._find_potential_duplicates(all_open_issues)

        print(f"  - Potential duplicates: {len(findings['potential_duplicates'])} pairs found")
        print("Analysis complete.\n")

        return findings

    def _analyze_duplicates(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Analyze duplicate issues."""
        for issue in issues:
            original_number = self._extract_duplicate_reference(issue.get('body', ''))
            issue['suggested_action'] = 'close'
            if original_number:
                issue['rationale'] = f"Already marked as duplicate of #{original_number}"
            else:
                issue['rationale'] = "Labeled as duplicate but no reference found"

        return issues

    def _analyze_unlabeled(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Analyze unlabeled issues."""
        for issue in issues:
            title = issue.get('title', '').lower()
            body = issue.get('body', '').lower()

            # Suggest labels based on content
            suggested_labels = []

            # Bug detection keywords
            bug_keywords = ['bug', 'error', 'issue', 'problem', 'broken', 'crash', 'fail']
            if any(keyword in title or keyword in body for keyword in bug_keywords):
                suggested_labels.append('type: bug')

            # Feature detection keywords
            feature_keywords = ['add', 'new', 'feature', 'enhancement', 'implement', 'support']
            if any(keyword in title or keyword in body for keyword in feature_keywords):
                suggested_labels.append('type: enhancement')

            # Documentation detection keywords
            doc_keywords = ['doc', 'documentation', 'readme', 'guide', 'example']
            if any(keyword in title or keyword in body for keyword in doc_keywords):
                suggested_labels.append('type: documentation')

            issue['suggested_action'] = 'label'
            issue['suggested_labels'] = suggested_labels
            issue['rationale'] = f"Needs triage - suggest labels: {', '.join(suggested_labels)}"

        return issues

    def _analyze_stale_backlog(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Analyze stale backlog issues."""
        for issue in issues:
            age_days = self.calculate_age_days(issue.get('createdAt', ''))
            issue['age_days'] = age_days
            issue['suggested_action'] = 'investigate'
            issue['rationale'] = f"Backlog item is {age_days} days old - verify if still needed"

        return issues

    def _analyze_orphaned(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Analyze orphaned sub-issues."""
        for issue in issues:
            parent_number = issue.get('parent_issue')
            issue['suggested_action'] = 'close'
            issue['rationale'] = f"Parent issue #{parent_number} is closed"

        return issues

    def _get_all_open_issues(self, findings: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
        """Extract all unique open issues from findings."""
        all_issues = []
        seen_numbers = set()

        for category_issues in findings.values():
            if isinstance(category_issues, list):
                for issue in category_issues:
                    number = issue.get('number')
                    if number and number not in seen_numbers:
                        all_issues.append(issue)
                        seen_numbers.add(number)

        return all_issues

    def _find_potential_duplicates(self, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Find potential duplicate pairs using Levenshtein distance.

        Args:
            issues: List of all open issues

        Returns:
            List of potential duplicate pairs
        """
        print("  Computing title similarities...", end=" ", flush=True)

        duplicates = []

        # Compare all pairs
        for i in range(len(issues)):
            for j in range(i + 1, len(issues)):
                issue1 = issues[i]
                issue2 = issues[j]

                title1 = issue1.get('title', '')
                title2 = issue2.get('title', '')

                similarity = self.title_similarity.compute_similarity(title1, title2)

                if similarity >= self.similarity_threshold:
                    duplicates.append({
                        'issue1_number': issue1['number'],
                        'issue1_title': title1,
                        'issue2_number': issue2['number'],
                        'issue2_title': title2,
                        'similarity': round(similarity, 3),
                        'suggested_action': 'merge',
                        'rationale': f"{int(similarity * 100)}% similar titles - consider merging or linking"
                    })

        print("✓")
        return duplicates

    def _extract_duplicate_reference(self, body: str) -> Optional[int]:
        """
        Extract original issue number from duplicate body.

        Args:
            body: Issue body text

        Returns:
            Original issue number or None
        """
        # Look for patterns like "duplicate of #123" or "see #456"
        patterns = [
            r'duplicate\s+of\s+#(\d+)',
            r'see\s+#(\d+)',
            r'same\s+as\s+#(\d+)',
            r'related\s+to\s+#(\d+)'
        ]

        for pattern in patterns:
            match = re.search(pattern, body.lower())
            if match:
                return int(match.group(1))

        return None

    def calculate_age_days(self, created_at: str) -> int:
        """
        Calculate issue age in days.

        Args:
            created_at: ISO format datetime string

        Returns:
            Age in days
        """
        try:
            created_date = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
            age = datetime.now(created_date.tzinfo) - created_date
            return age.days
        except (ValueError, AttributeError):
            return 0

    def suggest_action(self, issue: Dict[str, Any]) -> str:
        """
        Suggest action for an issue.

        Args:
            issue: Issue dictionary

        Returns:
            Suggested action
        """
        return issue.get('suggested_action', 'investigate')


class TitleSimilarity:
    """Computes similarity between issue titles using Levenshtein distance."""

    def compute_levenshtein_distance(self, s1: str, s2: str) -> int:
        """
        Compute Levenshtein distance between two strings.

        Args:
            s1: First string
            s2: Second string

        Returns:
            Edit distance (number of character operations needed)
        """
        # Create matrix
        m, n = len(s1), len(s2)
        dp = [[0] * (n + 1) for _ in range(m + 1)]

        # Initialize first row and column
        for i in range(m + 1):
            dp[i][0] = i
        for j in range(n + 1):
            dp[0][j] = j

        # Fill matrix
        for i in range(1, m + 1):
            for j in range(1, n + 1):
                if s1[i - 1] == s2[j - 1]:
                    dp[i][j] = dp[i - 1][j - 1]
                else:
                    dp[i][j] = 1 + min(
                        dp[i - 1][j],      # Deletion
                        dp[i][j - 1],      # Insertion
                        dp[i - 1][j - 1]   # Substitution
                    )

        return dp[m][n]

    def compute_similarity(self, title1: str, title2: str) -> float:
        """
        Compute normalized similarity score between two titles.

        Args:
            title1: First title
            title2: Second title

        Returns:
            Similarity score (0.0-1.0, where 1.0 is identical)
        """
        # Normalize titles (lowercase, strip whitespace)
        t1 = title1.strip().lower()
        t2 = title2.strip().lower()

        if not t1 or not t2:
            return 0.0

        # Compute Levenshtein distance
        distance = self.compute_levenshtein_distance(t1, t2)

        # Normalize to 0-1 scale
        max_length = max(len(t1), len(t2))
        if max_length == 0:
            return 1.0

        similarity = 1.0 - (distance / max_length)
        return max(0.0, min(1.0, similarity))


def main():
    """Main entry point for testing analyzer module."""
    # Test Levenshtein distance
    similarity = TitleSimilarity()

    test_pairs = [
        ("Add user authentication", "Add authentication for users"),
        ("Fix bug in login", "Fix login bug"),
        ("Implement new feature", "Completely different title"),
        ("Update documentation", "Update docs")
    ]

    print("=== Testing Similarity Computation ===\n")
    for title1, title2 in test_pairs:
        score = similarity.compute_similarity(title1, title2)
        print(f"Title 1: {title1}")
        print(f"Title 2: {title2}")
        print(f"Similarity: {score:.3f} ({int(score * 100)}%)\n")


if __name__ == "__main__":
    main()
