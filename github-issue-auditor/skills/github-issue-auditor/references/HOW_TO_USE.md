# How to Use GitHub Issue Auditor

This guide provides invocation examples and usage patterns for the GitHub Issue Auditor skill.

## Prerequisites Checklist

Before using this skill, ensure:

- [ ] GitHub CLI (`gh`) is installed
- [ ] You're authenticated with `gh auth login`
- [ ] You're in a GitHub repository directory
- [ ] You have write access to the repository (for actions)

## Quick Start

### Basic Audit

```
Hey Claude—I just added the "github-issue-auditor" skill. Can you audit this repository's issues for cleanup opportunities?
```

**What happens**:
1. Discovery phase runs (5 parallel queries)
2. Analysis phase computes similarities and ages
3. Summary table displayed
4. You select categories to review
5. Individual approval for each action
6. Execution summary displayed

### Specific Category

```
Hey Claude—I just added the "github-issue-auditor" skill. Can you find orphaned sub-issues where the parent is closed?
```

**What happens**:
1. Discovery focuses on orphaned category
2. Shows issues referencing closed parents
3. Individual approval for each closure
4. Execution summary

## Invocation Examples

### Example 1: Full Audit

```
Hey Claude—I just added the "github-issue-auditor" skill. Run a complete audit of this repository's issues.
```

**What to Expect**:
- All 5 categories audited
- Comprehensive summary table
- Option to review each category
- Individual approval workflow
- Execution summary with success/failure counts

### Example 2: Stale Backlog Check

```
Hey Claude—I just added the "github-issue-auditor" skill. Check for stale backlog items older than 60 days.
```

**What to Provide**:
- Custom threshold (60 days instead of default 30)

**What You'll Get**:
- List of backlog items >60 days old
- Suggested action: Add investigation comment
- Approval workflow for each item

### Example 3: Find Duplicates

```
Hey Claude—I just added the "github-issue-auditor" skill. Find potential duplicate issues using fuzzy matching.
```

**What You'll Get**:
- Pairs of issues with similar titles
- Similarity score (0.0-1.0)
- Suggested action: Link or merge issues
- Individual approval for each pair

### Example 4: Unlabeled Issues

```
Hey Claude—I just added the "github-issue-auditor" skill. Find unlabeled issues and suggest appropriate labels.
```

**What You'll Get**:
- Issues with zero labels
- AI-suggested labels based on title/body
- Approval workflow to add labels

### Example 5: Generate Report

```
Hey Claude—I just added the "github-issue-auditor" skill. Audit issues and generate a markdown report for documentation.
```

**What You'll Get**:
- Full audit execution
- Markdown report saved to `issue-audit-report-YYYY-MM-DD.md`
- Report includes summary, findings, execution results, recommendations

## What to Provide

### Minimal (Auto-detected)

The skill auto-detects:
- Current repository
- Open issues
- Labels and states
- Parent-child relationships

### Optional Configuration

Create `config.json` to customize:

```json
{
  "stale_threshold_days": 60,
  "similarity_threshold": 0.80,
  "categories_to_audit": ["duplicates", "orphaned"],
  "generate_report": true
}
```

### Custom Thresholds

Specify in natural language:

```
Check for stale items older than 90 days
```

```
Use 80% similarity threshold for duplicates
```

## What You'll Get

### Discovery Results

```
Discovery Phase:
  Finding duplicates... ✓ 3 found
  Finding unlabeled... ✓ 7 found
  Finding stale backlog... ✓ 12 found
  Finding orphaned... ✓ 2 found
  Finding potential duplicates... ✓ 5 pairs found
```

### Summary Table

```
=================================================
AUDIT SUMMARY
=================================================
  Duplicates (already marked).................. 3
  Unlabeled (need triage)...................... 7
  Stale Backlog (>threshold).................. 12
  Orphaned Sub-Issues.......................... 2
  Potential Duplicates (similar titles)........ 5
  Total....................................... 29
=================================================
```

### Interactive Review

```
Which categories would you like to review?
  1. Duplicates
  2. Unlabeled
  3. Stale Backlog
  4. Orphaned
  5. Potential Duplicates

Enter numbers separated by commas (e.g., '1,2,4') or 'all':
> 1,4

=== REVIEWING DUPLICATES ===
Found 3 issue(s) to review.

--- Issue 1 of 3 ---
Issue #45: Add user authentication
Age: 58 days
Body preview: Marked as duplicate of #42. See original issue for implementation details.

Suggested action: close
Rationale: Already marked as duplicate of #42

Approve this action? [y/n/s(kip)]: y
✓ Approved
```

### Execution Summary

```
=================================================
EXECUTION SUMMARY
=================================================
Successful: 4
Failed: 1

Failed actions:
  - Issue #102: Permission denied
```

### Markdown Report

```markdown
# GitHub Issue Audit Report

**Generated**: 2026-01-13 10:30:00

## Executive Summary

- **Total Issues Found**: 29
- **Actions Executed**: 8
- **Actions Failed**: 1

### Issues by Category

- **Duplicates (already marked)**: 3
- **Unlabeled (need triage)**: 7
- **Stale Backlog**: 12
- **Orphaned Sub-Issues**: 2
- **Potential Duplicates**: 5

[... detailed findings ...]
```

## Common Workflows

### Weekly Cleanup

```
Hey Claude—run a weekly issue audit and show me what needs attention.
```

**Use Case**: Regular maintenance to keep issue tracker clean

### Pre-Sprint Planning

```
Hey Claude—audit backlog items and identify stale issues before sprint planning.
```

**Use Case**: Clean up backlog before team planning session

### New Project Manager Onboarding

```
Hey Claude—generate an audit report showing current issue health.
```

**Use Case**: Give new PM visibility into issue tracker quality

### After Epic Completion

```
Hey Claude—find orphaned sub-issues after we closed the authentication epic.
```

**Use Case**: Clean up sub-issues when parent work is done

### Duplicate Prevention

```
Hey Claude—find potential duplicates before I create this new issue.
```

**Use Case**: Check if issue already exists before creation

## Tips

### Start Small

First time? Start with one category:

```
Hey Claude—just show me orphaned issues for now.
```

### Use Dry Run

Preview without changes:

```
Hey Claude—audit issues in dry-run mode so I can see what would change.
```

### Generate Reports

Document cleanup efforts:

```
Hey Claude—generate a report after audit completion.
```

### Adjust Thresholds

Tune for your workflow:

```
Hey Claude—our backlog moves slower, use 90 days for stale threshold.
```

### Review Parent Formats

Ensure your team uses supported formats:
- "Part of #123"
- "Epic: #123"
- "Parent: #123"
- "Subtask of #123"

## Error Handling

### If `gh` Not Found

```
Error: GitHub CLI (gh) is not installed.
Install from: https://cli.github.com/
```

**Solution**: Install GitHub CLI

### If Not Authenticated

```
Error: Not authenticated with GitHub.
Run: gh auth login
```

**Solution**: Authenticate with `gh auth login`

### If Not in Repository

```
Error: Not in a GitHub repository.
Navigate to a repository root directory and try again.
```

**Solution**: `cd /path/to/repository`

### If Permission Denied

```
✗ Failed to close issue #102: Permission denied
```

**Solution**: Verify repository write access

## Advanced Usage

### Custom Configuration

Create `config.json`:

```json
{
  "stale_threshold_days": 45,
  "similarity_threshold": 0.85,
  "categories_to_audit": ["orphaned", "potential_duplicates"],
  "generate_report": true,
  "dry_run": false
}
```

Then run:

```
Hey Claude—audit issues using my custom config.json settings.
```

### Combining with Other Skills

```
Hey Claude—audit issues, then use the prompt-factory skill to create a GitHub Actions workflow that runs this audit weekly.
```

## Best Practices

1. **Start Conservative**: Use higher similarity thresholds (0.80+) initially
2. **Review Carefully**: Read issue context before approving closures
3. **Communicate**: Inform team before bulk operations
4. **Generate Reports**: Document cleanup decisions
5. **Regular Cadence**: Run audits weekly or bi-weekly
6. **Adjust Thresholds**: Tune based on your team's workflow
7. **Test First**: Use dry-run mode on first attempt

## Support

If you encounter issues:
1. Check prerequisites (gh CLI, auth, repository)
2. Review README.md for troubleshooting
3. Test individual modules: `python3 scripts/discovery.py`
4. Check GitHub API rate limits: `gh api rate_limit`

## Summary

The GitHub Issue Auditor helps maintain healthy issue trackers by:
- Identifying duplicates automatically
- Finding orphaned work items
- Flagging issues needing triage
- Highlighting stale backlog items
- Using fuzzy matching for potential duplicates

All with safe, individual approval workflow and optional reporting.
