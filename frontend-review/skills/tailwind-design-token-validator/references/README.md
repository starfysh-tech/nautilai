# Tailwind Design Token Validator

**Version**: 1.0.0
**Type**: Claude Code Skill
**Domain**: SaaS Frontend Development

## Overview

The Tailwind Design Token Validator analyzes React/TypeScript codebases for Tailwind CSS usage anti-patterns and enforces design system token compliance. It scans component files, validates class usage against semantic tokens, and identifies accessibility gaps.

## Features

- ✅ **Token Compliance Validation** - Flag arbitrary values and suggest semantic tokens
- ✅ **Anti-Pattern Detection** - Identify dynamic concatenation, @apply overuse, inline styles
- ✅ **Accessibility Auditing** - Validate ARIA attributes, focus states, semantic HTML
- ✅ **Class Order Consistency** - Verify layout → typography → color → state ordering
- ✅ **Responsive Pattern Validation** - Check mobile-first responsive usage
- ✅ **Multi-Format Reports** - Text, JSON (CI/CD), Markdown outputs

## Installation

### Claude Code (Project-Level)
```bash
# Clone or download this skill
cp -r tailwind-design-token-validator ~/.claude/skills/

# Or for project-specific installation
mkdir -p .claude/skills
cp -r tailwind-design-token-validator .claude/skills/
```

### Claude Code (User-Level)
```bash
# Install globally for all projects
cp -r tailwind-design-token-validator ~/.claude/skills/
```

### Verify Installation
```bash
# Check skill is loaded
ls ~/.claude/skills/tailwind-design-token-validator
```

## Usage

### Basic Validation
```
Hey Claude—I just added the "tailwind-design-token-validator" skill.
Can you validate src/components/ against tailwind.config.js?
```

### Specific Checks
```
Hey Claude—can you check for:
- Arbitrary color values that should use semantic tokens
- Dynamic class concatenation anti-patterns
- Missing accessibility attributes
- Inline styles that should be Tailwind utilities
```

### Generate Reports
```
Hey Claude—generate a markdown report of all Tailwind violations
with suggested fixes
```

## Python Modules

### Core Modules

1. **analyze_tailwind_config.py** - Extracts semantic tokens from Tailwind config
   - Parses `tailwind.config.js/ts`
   - Extracts colors, spacing, fonts, borders, shadows
   - Provides token matching utilities

2. **scan_components.py** - Scans component directories
   - Finds `.tsx`, `.jsx` files
   - Scans CSS files for @apply
   - Excludes node_modules, build directories

3. **validate_class_usage.py** - Validates Tailwind class usage
   - Checks arbitrary values
   - Detects dynamic concatenation
   - Identifies inline styles
   - Validates responsive patterns
   - Checks class ordering
   - Detects @apply overuse

4. **check_accessibility.py** - Validates accessibility
   - Checks ARIA attributes
   - Validates focus states
   - Verifies semantic HTML
   - Basic color contrast checks

5. **suggest_tokens.py** - Recommends semantic tokens
   - Suggests color token replacements
   - Suggests spacing token replacements
   - Suggests font token replacements
   - Calculates color distance for closest matches

6. **generate_report.py** - Outputs formatted reports
   - Text format (human-readable)
   - JSON format (CI/CD integration)
   - Markdown format (documentation)
   - Summary statistics

## Validation Checks

### High Severity
- **Arbitrary Values**: `bg-[#3b82f6]` → Use semantic token
- **Dynamic Concatenation**: `border-[${color}]` → Breaks purging
- **Missing ARIA Labels**: Buttons without labels

### Medium Severity
- **Inline Styles**: `style={{padding: '16px'}}` → Use utilities
- **@apply Overuse**: Excessive @apply in CSS files
- **Missing Focus States**: Interactive elements without focus styles

### Low Severity
- **Class Ordering**: Inconsistent class order
- **Non-Semantic Elements**: Using div/span as buttons

## Configuration

### Sample Input
```json
{
  "config_path": "tailwind.config.js",
  "component_directory": "src/components",
  "css_directory": "src/styles",
  "options": {
    "check_arbitrary_values": true,
    "check_dynamic_concatenation": true,
    "check_inline_styles": true,
    "check_responsive_patterns": true,
    "check_class_ordering": true,
    "check_accessibility": true,
    "check_apply_overuse": true
  }
}
```

## Example Output

```
Design Token Validation Report
===============================

✗ src/components/Button.tsx
  Violations: 1 high, 0 medium, 0 low

  🔴 Line 12: Arbitrary color value: bg-[#3b82f6]
     → Use semantic token → bg-primary
     Code: <button className="bg-[#3b82f6] text-white">

✗ src/components/Card.tsx
  Violations: 0 high, 1 medium, 0 low

  🟡 Line 8: Inline style detected, should use Tailwind utilities
     → Replace inline styles with Tailwind utility classes
     Code: <div style={{padding: '16px'}}>

✓ src/components/Input.tsx
  All checks passed

===============================
Summary: 2 violations, 1 compliant

By Type:
  - arbitrary_value: 1
  - inline_style: 1

By Severity:
  - high: 1
  - medium: 1
```

## CI/CD Integration

### Pre-Commit Hook
```bash
# .husky/pre-commit
python validate_tailwind.py --format json --fail-on high
```

### GitHub Actions
```yaml
- name: Validate Tailwind Tokens
  run: |
    python validate_tailwind.py \
      --config tailwind.config.js \
      --components src/components \
      --format json \
      --output violations.json
```

## Best Practices

1. **Run Early**: Validate during development, not just in CI/CD
2. **Fix High Severity First**: Arbitrary values and dynamic concatenation
3. **Maintain Token Library**: Keep semantic tokens current in config
4. **Document Exceptions**: When arbitrary values are necessary
5. **Accessibility Priority**: Address a11y violations immediately
6. **Consistent Ordering**: Follow layout → typography → color → state

## Limitations

- Requires valid Tailwind config (JavaScript/TypeScript)
- Cannot analyze runtime-generated class names
- Optimized for React/TypeScript (may need adjustments for Vue/Svelte)
- May not recognize custom Tailwind plugin tokens
- Basic accessibility validation (not comprehensive WCAG audit)

## Requirements

- Python 3.7+
- React/TypeScript codebase
- Tailwind CSS v3+
- Valid `tailwind.config.js` or `tailwind.config.ts`

## Support

For issues or questions about this skill:
1. Verify all Python modules are in the skill folder
2. Check that Tailwind config path is correct
3. Ensure component directory contains `.tsx` or `.jsx` files
4. Review sample input/output files for expected formats

## License

This skill is part of the Claude Code Skills Factory and follows the same license terms.

---

**Generated with Claude Code Skills Factory**
**Last Updated**: 2026-01-25
