"""
GitHub Issue Interactive Review Module.
Presents findings and collects individual user approvals.
"""

from typing import Any, Dict, List, Optional


class InteractiveReviewer:
    """Handles interactive user review workflow."""

    def __init__(self):
        """Initialize interactive reviewer."""
        self.approved_actions = []

    @staticmethod
    def present_summary(findings: Dict[str, List[Dict[str, Any]]]) -> None:
        """
        Present summary table of findings.

        Args:
            findings: Dictionary of issues by category
        """
        print("\n" + "=" * 60)
        print("AUDIT SUMMARY")
        print("=" * 60)

        categories = {
            'duplicates': 'Duplicates (already marked)',
            'unlabeled': 'Unlabeled (need triage)',
            'stale_backlog': 'Stale Backlog (>threshold)',
            'orphaned': 'Orphaned Sub-Issues',
            'potential_duplicates': 'Potential Duplicates (similar titles)'
        }

        total = 0
        for key, label in categories.items():
            count = len(findings.get(key, []))
            total += count
            print(f"  {label:.<50} {count:>3}")

        print(f"  {'Total':.>50} {total:>3}")
        print("=" * 60 + "\n")

    def select_categories(self) -> List[str]:
        """
        Prompt user to select which categories to review.

        Returns:
            List of selected category keys
        """
        categories = {
            '1': 'duplicates',
            '2': 'unlabeled',
            '3': 'stale_backlog',
            '4': 'orphaned',
            '5': 'potential_duplicates'
        }

        print("Which categories would you like to review?")
        print("  1. Duplicates")
        print("  2. Unlabeled")
        print("  3. Stale Backlog")
        print("  4. Orphaned")
        print("  5. Potential Duplicates")
        print("\nEnter numbers separated by commas (e.g., '1,2,4') or 'all':")

        while True:
            selection = input("> ").strip().lower()

            if selection == 'all':
                return list(categories.values())

            if not selection:
                print("Please enter a selection.")
                continue

            # Parse selections
            selected_keys = []
            valid = True

            for part in selection.split(','):
                part = part.strip()
                if part in categories:
                    selected_keys.append(categories[part])
                else:
                    print(f"Invalid selection: {part}")
                    valid = False
                    break

            if valid and selected_keys:
                return selected_keys

            print("Please try again.")

    def review_category(
        self,
        category: str,
        issues: List[Dict[str, Any]],
        category_label: str
    ) -> List[Dict[str, Any]]:
        """
        Review all issues in a category with individual approval.

        Args:
            category: Category key
            issues: List of issues in category
            category_label: Human-readable category label

        Returns:
            List of approved actions
        """
        if not issues:
            print(f"\n=== {category_label} ===")
            print("No issues found in this category.\n")
            return []

        print(f"\n{'=' * 60}")
        print(f"{category_label.upper()}")
        print(f"{'=' * 60}")
        print(f"Found {len(issues)} issue(s) to review.\n")

        approved = []

        for idx, issue in enumerate(issues, 1):
            print(f"--- Issue {idx} of {len(issues)} ---")

            # Review depends on category type
            if category == 'potential_duplicates':
                action = self._review_potential_duplicate(issue)
            else:
                action = self._review_issue(issue)

            if action:
                approved.append(action)

            print()  # Blank line between issues

        return approved

    @staticmethod
    def _review_issue(issue: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Review a single issue and get user approval.

        Args:
            issue: Issue dictionary

        Returns:
            Approved action dictionary or None
        """
        # Display issue details
        print(f"Issue #{issue['number']}: {issue['title']}")
        print(f"Age: {issue.get('age_days', 'N/A')} days")

        # Display body preview (first 200 chars)
        body = issue.get('body', '')
        if body:
            preview = body[:200] + ('...' if len(body) > 200 else '')
            print(f"Body preview: {preview}")
        else:
            print("Body preview: (empty)")

        print(f"\nSuggested action: {issue.get('suggested_action', 'investigate')}")
        print(f"Rationale: {issue.get('rationale', 'N/A')}")

        # Display suggested labels if present
        if 'suggested_labels' in issue:
            print(f"Suggested labels: {', '.join(issue['suggested_labels'])}")

        # Get approval
        print("\nApprove this action? [y/n/s(kip)]:", end=" ")
        response = input().strip().lower()

        if response == 'y':
            print("✓ Approved")
            return {
                'issue_number': issue['number'],
                'action': issue.get('suggested_action'),
                'labels': issue.get('suggested_labels', []),
                'parent_issue': issue.get('parent_issue'),
                'rationale': issue.get('rationale')
            }
        elif response == 's':
            print("⊘ Skipped")
            return None
        else:
            print("✗ Not approved")
            return None

    @staticmethod
    def _review_potential_duplicate(duplicate_pair: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Review a potential duplicate pair.

        Args:
            duplicate_pair: Duplicate pair dictionary

        Returns:
            Approved action dictionary or None
        """
        print(f"Issue #{duplicate_pair['issue1_number']}: {duplicate_pair['issue1_title']}")
        print(f"Issue #{duplicate_pair['issue2_number']}: {duplicate_pair['issue2_title']}")
        print(f"Similarity: {duplicate_pair['similarity']:.3f} ({int(duplicate_pair['similarity'] * 100)}%)")

        print(f"\nSuggested action: {duplicate_pair.get('suggested_action', 'investigate')}")
        print(f"Rationale: {duplicate_pair.get('rationale', 'N/A')}")

        print("\nApprove linking/merging these issues? [y/n/s(kip)]:", end=" ")
        response = input().strip().lower()

        if response == 'y':
            print("✓ Approved")
            return {
                'issue_number': duplicate_pair['issue1_number'],
                'action': 'comment',
                'comment': f"This issue appears similar to #{duplicate_pair['issue2_number']}. Consider merging or linking.",
                'rationale': duplicate_pair.get('rationale')
            }
        elif response == 's':
            print("⊘ Skipped")
            return None
        else:
            print("✗ Not approved")
            return None

    def review_all(self, findings: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
        """
        Orchestrate complete interactive review process.

        Args:
            findings: All discovered and analyzed findings

        Returns:
            List of all approved actions
        """
        self.approved_actions = []

        # Present summary
        self.present_summary(findings)

        # Select categories
        selected_categories = self.select_categories()

        if not selected_categories:
            print("No categories selected. Exiting review.")
            return []

        # Category labels
        category_labels = {
            'duplicates': 'Reviewing Duplicates',
            'unlabeled': 'Reviewing Unlabeled Issues',
            'stale_backlog': 'Reviewing Stale Backlog',
            'orphaned': 'Reviewing Orphaned Sub-Issues',
            'potential_duplicates': 'Reviewing Potential Duplicates'
        }

        # Review each selected category
        for category in selected_categories:
            issues = findings.get(category, [])
            label = category_labels.get(category, category.replace('_', ' ').title())

            approved = self.review_category(category, issues, label)
            self.approved_actions.extend(approved)

        # Summary
        print(f"\n{'=' * 60}")
        print("REVIEW COMPLETE")
        print(f"{'=' * 60}")
        print(f"Total approved actions: {len(self.approved_actions)}")
        print()

        return self.approved_actions


def main():
    """Main entry point for testing interactive review module."""
    # Test data
    test_findings = {
        'duplicates': [
            {
                'number': 45,
                'title': 'Add user authentication',
                'createdAt': '2025-11-15T10:30:00Z',
                'body': 'Marked as duplicate of #42',
                'age_days': 58,
                'suggested_action': 'close',
                'rationale': 'Already marked as duplicate of #42'
            }
        ],
        'unlabeled': [
            {
                'number': 67,
                'title': 'Fix database migration issue',
                'createdAt': '2026-01-10T14:20:00Z',
                'body': 'Database migrations failing on production',
                'labels': [],
                'age_days': 3,
                'suggested_action': 'label',
                'suggested_labels': ['bug', 'priority: high'],
                'rationale': 'Production issue needs triage'
            }
        ],
        'stale_backlog': [],
        'orphaned': [],
        'potential_duplicates': []
    }

    reviewer = InteractiveReviewer()
    approved_actions = reviewer.review_all(test_findings)

    print(f"\nApproved {len(approved_actions)} action(s):")
    for action in approved_actions:
        print(f"  - Issue #{action['issue_number']}: {action['action']}")


if __name__ == "__main__":
    main()
