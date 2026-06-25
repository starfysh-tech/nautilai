# How to Use This Skill

## Usage

This is a **Claude agent library module**, not a CLI tool. The Python modules provide programmatic analysis capabilities that Claude uses to analyze React component architecture. You interact with it through natural language requests to Claude.

### Python Library Usage

```python
from architecture_reporter import analyze_directory, generate_report

# Analyze components
results = analyze_directory("src/", {
    "component_size_limit": 200,
    "prop_drilling_depth": 3,
    "min_duplicate_count": 3
})

# Generate report
report = generate_report(results, format="markdown")
print(report)
```

### Skill Invocation

Hey Claude—I just added the "react-component-architecture" skill. Can you analyze my React components for architecture violations?

## Example Invocations

### Example 1: Full Directory Analysis
```
Hey Claude—I just added the "react-component-architecture" skill. Can you analyze all components in src/ and generate a comprehensive architecture report?
```

### Example 2: Check Specific Component
```
Hey Claude—I just added the "react-component-architecture" skill. Can you check if src/features/auth/LoginForm.tsx follows composition best practices?
```

### Example 3: Find Duplicates
```
Hey Claude—I just added the "react-component-architecture" skill. Can you find duplicated UI patterns across the dashboard feature that should be extracted as primitives?
```

### Example 4: Size Violations
```
Hey Claude—I just added the "react-component-architecture" skill. Can you show me all components exceeding 200 lines with suggestions on how to split them?
```

### Example 5: Folder Structure
```
Hey Claude—I just added the "react-component-architecture" skill. Can you validate our folder structure and suggest where components should be moved?
```

### Example 6: CI/CD Integration
```
Hey Claude—I just added the "react-component-architecture" skill. Can you run architecture checks and export a JSON report for our CI pipeline?
```

### Example 7: Prop Drilling Detection
```
Hey Claude—I just added the "react-component-architecture" skill. Can you detect prop drilling in our components and suggest refactoring strategies?
```

## What to Provide

### Required:
- **Source directory path**: Path to `src/` or components folder (e.g., `src/`, `app/components/`)

### Optional:
- **Configuration**: Custom rules for size limits, nesting depth, folder structure
  ```json
  {
    "component_size_limit": 200,
    "prop_drilling_depth": 3,
    "min_duplicate_count": 3
  }
  ```
- **Exclusion patterns**: Patterns to exclude from analysis (default: node_modules, dist, .next, __tests__)
- **Output format**: Markdown report (default) or JSON for CI/CD

## What You'll Get

### Comprehensive Report:
```markdown
React Component Architecture Report
====================================
Analyzed: 45 components in src/

⚠ Component Size Issues (3 found)
----------------------------------
1. src/features/auth/LoginForm.tsx (245 lines)
   → Split into: <FormInput>, <FormButton>, <FormError> primitives

⚠ Prop Drilling Detected (2 instances)
---------------------------------------
1. src/features/dashboard/Dashboard.tsx:45
   App → Dashboard → UserPanel → UserInfo → UserAvatar (5 levels)
   → Suggest: Use Context API or composition

✓ Duplicate Patterns Found (4 patterns)
----------------------------------------
1. Form Submit Buttons (3 files)
   → Extract: <SubmitButton variant="primary" loading={...} />

✓ Folder Structure: Compliant

⚠ Type Coverage: 87% (6 components missing prop types)

Architecture Health Score: 78/100
```

### Detailed Metrics:
- Component count and average size
- Type coverage percentage
- Prop drilling instances with depth
- Duplicate patterns ready for extraction
- Folder structure violations
- Complexity scores
- Actionable recommendations

### JSON Export (for CI/CD):
```json
{
  "health_score": 78,
  "is_passing": true,
  "violations": {
    "component_size": 3,
    "prop_drilling": 2,
    "folder_structure": 0,
    "missing_types": 6
  },
  "duplicates_found": 4
}
```

## Configuration Examples

### Basic Configuration
```json
{
  "source_directory": "src/",
  "component_size_limit": 200,
  "prop_drilling_depth": 3
}
```

### Strict Configuration (for mature projects)
```json
{
  "source_directory": "src/",
  "component_size_limit": 150,
  "prop_drilling_depth": 2,
  "min_duplicate_count": 2,
  "type_coverage_threshold": 98,
  "complexity_threshold": 8
}
```

### Lenient Configuration (for new projects)
```json
{
  "source_directory": "src/",
  "component_size_limit": 250,
  "prop_drilling_depth": 4,
  "min_duplicate_count": 4,
  "type_coverage_threshold": 80,
  "complexity_threshold": 12
}
```

## Integration with Development Workflow

### Pre-commit Hook
Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
echo "Checking React architecture..."
# Use Python library programmatically
python3 -c "
from architecture_reporter import analyze_directory, has_violations
results = analyze_directory('src/')
if has_violations(results):
    print('Architecture violations detected. Fix issues before committing.')
    exit(1)
"
```

### GitHub Actions Workflow
Add to `.github/workflows/architecture-check.yml`:
```yaml
name: Architecture Check

on: [push, pull_request]

jobs:
  architecture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run architecture analysis
        run: |
          python3 -c "
          import json
          from architecture_reporter import analyze_directory, generate_report
          results = analyze_directory('src/')
          report = generate_report(results, format='json')
          with open('report.json', 'w') as f:
              json.dump(report, f)
          "

      - name: Check health score
        run: |
          SCORE=$(jq '.health_score' report.json)
          if [ $SCORE -lt 70 ]; then
            echo "Architecture health score below 70%: $SCORE"
            exit 1
          fi
          echo "Architecture health score: $SCORE/100 ✓"

      - name: Upload report
        uses: actions/upload-artifact@v3
        with:
          name: architecture-report
          path: report.json
```

### VS Code Task
Add to `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Check Architecture",
      "type": "shell",
      "command": "python3 -c \"from architecture_reporter import analyze_directory, generate_report; results = analyze_directory('${fileDirname}'); print(generate_report(results))\"",
      "problemMatcher": [],
      "group": {
        "kind": "build",
        "isDefault": true
      }
    }
  ]
}
```

## ~~Command-Line Usage~~

**Note:** This is a library module, not a CLI tool. Use the Python API shown above.

~~### Analyze entire directory:~~
~~```bash~~
~~python3 architecture_reporter.py src/~~
~~```~~

~~### Export JSON for CI:~~
~~```bash~~
~~python3 architecture_reporter.py src/ --json --output report.json~~
~~```~~

~~### Check specific feature:~~
~~```bash~~
~~python3 architecture_reporter.py src/features/dashboard~~
~~```~~

~~### Run with custom config:~~
~~```bash~~
~~python3 architecture_reporter.py src/ --config architecture.config.json~~
~~```~~

## Tips for Best Results

1. **Run regularly**: Check architecture weekly or before major releases
2. **Set realistic thresholds**: Start lenient, gradually increase standards
3. **Focus on trends**: Track health score over time
4. **Prioritize violations**: Fix size and prop drilling first, then duplicates
5. **Extract primitives early**: When you find 2-3 duplicates, extract immediately
6. **Use with linters**: Combine with ESLint/Prettier for comprehensive checks
7. **Team alignment**: Review reports in team meetings
8. **CI/CD gates**: Fail builds if score drops below threshold (e.g., 70)

## Common Questions

**Q: What's a good health score?**
A: 80+ is excellent, 70-80 is good, 60-70 needs improvement, <60 requires refactoring.

**Q: Should I fix all violations immediately?**
A: Prioritize: 1) Type coverage 2) Component size 3) Prop drilling 4) Duplicates 5) Folder structure

**Q: Can I customize folder structure rules?**
A: Yes, edit `architecture.config.json` to match your team's conventions.

**Q: Does this work with Next.js/Remix?**
A: Yes, supports all React frameworks. Adjust `excluded_patterns` if needed.

**Q: What about React Native?**
A: Works with React Native. May need to adjust folder structure rules.

**Q: Can I ignore certain files?**
A: Yes, add patterns to `excluded_patterns` in config.

**Q: How long does analysis take?**
A: Small projects (<100 components): 5-10 seconds
   Medium projects (100-500 components): 15-30 seconds
   Large projects (500+ components): 30-60 seconds
