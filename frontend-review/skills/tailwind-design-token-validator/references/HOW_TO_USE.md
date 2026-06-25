# How to Use This Skill

## Usage

This is a **Claude agent library module**, not a CLI tool. The Python modules provide programmatic validation capabilities that Claude uses to analyze Tailwind CSS usage. You interact with it through natural language requests to Claude.

### Python Library Usage

```python
from validator import validate_directory, generate_report

# Validate Tailwind usage
results = validate_directory(
    component_dir="src/components/",
    tailwind_config_path="tailwind.config.js",
    options={
        "check_arbitrary_values": True,
        "check_dynamic_concatenation": True,
        "check_accessibility": True
    }
)

# Generate report
report = generate_report(results, format="markdown")
print(report)
```

### Skill Invocation

Hey Claude—I just added the "tailwind-design-token-validator" skill. Can you validate Tailwind token usage in my React codebase?

## Example Invocations

**Example 1:**
Hey Claude—I just added the "tailwind-design-token-validator" skill. Can you validate the components in src/components/ against my tailwind.config.js?

**Example 2:**
Hey Claude—I just added the "tailwind-design-token-validator" skill. Can you check for Tailwind anti-patterns like arbitrary values and dynamic class concatenation?

**Example 3:**
Hey Claude—I just added the "tailwind-design-token-validator" skill. Can you audit accessibility compliance in my components and check for missing ARIA attributes?

**Example 4:**
Hey Claude—I just added the "tailwind-design-token-validator" skill. Can you find all inline styles that should be replaced with Tailwind utilities?

**Example 5:**
Hey Claude—I just added the "tailwind-design-token-validator" skill. Can you validate class ordering and responsive patterns across my codebase?

## What to Provide

- **Component directory path**: Path to React/TypeScript components (e.g., `src/components/`)
- **Tailwind config path**: Path to `tailwind.config.js` or `tailwind.config.ts`
- **Optional CSS directory**: Path to CSS files if checking @apply overuse
- **Optional validation options**: Specific checks to enable/disable

## What You'll Get

- **Violation report**: Detailed list of violations by file, line number, type, and severity
- **Suggested fixes**: Semantic token recommendations for arbitrary values
- **Accessibility findings**: Missing ARIA attributes, focus states, semantic HTML issues
- **Summary statistics**: Total violations by category, severity, and file
- **Multiple formats**: Text, JSON (CI/CD), or Markdown reports

## Validation Options

You can customize which checks to run:
- `check_arbitrary_values`: Flag arbitrary values like `bg-[#ff0000]`
- `check_dynamic_concatenation`: Detect dynamic class patterns that break purging
- `check_inline_styles`: Find inline style attributes
- `check_responsive_patterns`: Validate mobile-first responsive usage
- `check_class_ordering`: Verify consistent class ordering
- `check_accessibility`: Validate ARIA, focus states, semantic HTML
- `check_apply_overuse`: Detect excessive @apply in CSS files

## Integration with CI/CD

Generate JSON reports for automated builds using the Python library:

```python
import json
from validator import validate_directory, generate_report

# Validate and generate JSON report
results = validate_directory(
    component_dir="src/components/",
    tailwind_config_path="tailwind.config.js"
)

report = generate_report(results, format="json")

# Save to file for CI/CD
with open("violations.json", "w") as f:
    json.dump(report, f, indent=2)
```

~~### CLI Usage (Not Available)~~

~~```bash~~
~~# Output JSON for CI/CD pipeline~~
~~python validate.py --format json --output violations.json~~
~~```~~

## Best Practices

1. Run validation before committing code
2. Fix high-severity violations first (arbitrary values, dynamic concatenation)
3. Address accessibility issues immediately
4. Use consistent class ordering across the codebase
5. Document any necessary exceptions (safelist usage, justified arbitrary values)
