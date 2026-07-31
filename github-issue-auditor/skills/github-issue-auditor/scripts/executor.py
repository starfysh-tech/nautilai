"""
GitHub Issue Action Executor Module.
Executes approved actions via gh CLI with error handling.
"""

import subprocess
from typing import Any, Dict, List


class ActionExecutor:
    """Executes approved actions via gh CLI."""

    def __init__(self, dry_run: bool = False) -> None:
        """
        Initialize action executor.

        Args:
            dry_run: If True, preview actions without executing
        """
        self.dry_run = dry_run
        self.executed_actions: List[Any] = []
        self.failed_actions: List[Any] = []

    def execute_actions(self, actions: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Execute all approved actions.

        Args:
            actions: List of approved action dictionaries

        Returns:
            Summary dictionary with success/failure counts
        """
        if not actions:
            print("No actions to execute.")
            return {'successful': 0, 'failed': 0, 'actions': []}

        print(f"\n{'=' * 60}")
        print("EXECUTION PHASE")
        print(f"{'=' * 60}")

        if self.dry_run:
            print("DRY RUN MODE - No actual changes will be made\n")
        else:
            print(f"Executing {len(actions)} approved action(s)...\n")

        for idx, action in enumerate(actions, 1):
            print(f"[{idx}/{len(actions)}] ", end="")
            self._execute_single_action(action)

        # Summary
        print(f"\n{'=' * 60}")
        print("EXECUTION SUMMARY")
        print(f"{'=' * 60}")
        print(f"Successful: {len(self.executed_actions)}")
        print(f"Failed: {len(self.failed_actions)}")

        if self.failed_actions:
            print("\nFailed actions:")
            for failed in self.failed_actions:
                print(f"  - Issue #{failed['issue_number']}: {failed['error']}")

        return {
            'successful': len(self.executed_actions),
            'failed': len(self.failed_actions),
            'executed_actions': self.executed_actions,
            'failed_actions': self.failed_actions
        }

    def _execute_single_action(self, action: Dict[str, Any]) -> None:
        """
        Execute a single action.

        Args:
            action: Action dictionary
        """
        issue_number = action.get('issue_number')
        action_type = action.get('action')

        try:
            if action_type == 'close':
                self._close_issue(action)
            elif action_type == 'label':
                self._add_labels(action)
            elif action_type == 'comment':
                self._add_comment(action)
            elif action_type == 'investigate':
                self._add_investigation_comment(action)
            else:
                print(f"Unknown action type '{action_type}' for issue #{issue_number}")
                self.failed_actions.append({
                    'issue_number': issue_number,
                    'action': action_type,
                    'error': f"Unknown action type: {action_type}"
                })

        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if hasattr(e, 'stderr') else str(e)
            print(f"✗ Failed to {action_type} issue #{issue_number}: {error_msg}")
            self.failed_actions.append({
                'issue_number': issue_number,
                'action': action_type,
                'error': error_msg
            })
        except Exception as e:
            print(f"✗ Unexpected error for issue #{issue_number}: {str(e)}")
            self.failed_actions.append({
                'issue_number': issue_number,
                'action': action_type,
                'error': str(e)
            })

    def _close_issue(self, action: Dict[str, Any]) -> None:
        """
        Close an issue with a comment.

        Args:
            action: Action dictionary
        """
        issue_number = action['issue_number']
        rationale = action.get('rationale', 'Closing based on audit')

        print(f"Closing issue #{issue_number}...", end=" ")

        if self.dry_run:
            print("(dry run)")
            return

        # Add comment first
        comment_cmd = [
            'gh', 'issue', 'comment', str(issue_number),
            '--body', rationale
        ]
        subprocess.run(comment_cmd, check=True, capture_output=True, text=True)

        # Close issue
        close_cmd = ['gh', 'issue', 'close', str(issue_number)]
        subprocess.run(close_cmd, check=True, capture_output=True, text=True)

        print("✓")
        self.executed_actions.append(action)

    def _add_labels(self, action: Dict[str, Any]) -> None:
        """
        Add labels to an issue.

        Args:
            action: Action dictionary
        """
        issue_number = action['issue_number']
        labels = action.get('labels', [])

        if not labels:
            print(f"No labels specified for issue #{issue_number}")
            return

        print(f"Adding labels to issue #{issue_number} ({', '.join(labels)})...", end=" ")

        if self.dry_run:
            print("(dry run)")
            return

        # Add labels: `gh issue edit --add-label` accepts a comma-separated
        # list, so one call covers all labels instead of one call per label.
        cmd = [
            'gh', 'issue', 'edit', str(issue_number),
            '--add-label', ','.join(labels)
        ]
        subprocess.run(cmd, check=True, capture_output=True, text=True)

        print("✓")
        self.executed_actions.append(action)

    def _add_comment(self, action: Dict[str, Any]) -> None:
        """
        Add a comment to an issue.

        Args:
            action: Action dictionary
        """
        issue_number = action['issue_number']
        comment = action.get('comment', action.get('rationale', 'Audit comment'))

        print(f"Adding comment to issue #{issue_number}...", end=" ")

        if self.dry_run:
            print("(dry run)")
            return

        cmd = [
            'gh', 'issue', 'comment', str(issue_number),
            '--body', comment
        ]
        subprocess.run(cmd, check=True, capture_output=True, text=True)

        print("✓")
        self.executed_actions.append(action)

    def _add_investigation_comment(self, action: Dict[str, Any]) -> None:
        """
        Add an investigation comment to an issue.

        Args:
            action: Action dictionary
        """
        issue_number = action['issue_number']
        rationale = action.get('rationale', 'This issue needs investigation')

        print(f"Adding investigation comment to issue #{issue_number}...", end=" ")

        if self.dry_run:
            print("(dry run)")
            return

        comment = f"🔍 **Audit Note**: {rationale}\n\nPlease confirm if this issue is still relevant or should be closed."

        cmd = [
            'gh', 'issue', 'comment', str(issue_number),
            '--body', comment
        ]
        subprocess.run(cmd, check=True, capture_output=True, text=True)

        print("✓")
        self.executed_actions.append(action)


def main():
    """Main entry point for testing executor module."""
    # Test data
    test_actions = [
        {
            'issue_number': 45,
            'action': 'close',
            'rationale': 'Already marked as duplicate of #42'
        },
        {
            'issue_number': 67,
            'action': 'label',
            'labels': ['bug', 'priority: high'],
            'rationale': 'Production issue needs triage'
        },
        {
            'issue_number': 89,
            'action': 'investigate',
            'rationale': 'Backlog item is 73 days old - verify if still needed'
        }
    ]

    print("=== Testing Executor (DRY RUN) ===\n")
    executor = ActionExecutor(dry_run=True)
    summary = executor.execute_actions(test_actions)

    print("\n=== Execution Summary ===")
    print(f"Successful: {summary['successful']}")
    print(f"Failed: {summary['failed']}")


if __name__ == "__main__":
    main()
