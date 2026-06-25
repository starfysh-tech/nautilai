# React Component Architecture Enforcer

Analyze React component structure and enforce composition patterns, reusability, and proper folder organization for TypeScript + Tailwind SaaS applications.

## Overview

This skill provides comprehensive analysis of React codebases to enforce architectural best practices:

- **Component Size**: Flag components >200 lines
- **Prop Drilling**: Detect deep prop passing (>3 levels)
- **Reusability**: Identify duplicated UI patterns
- **Folder Structure**: Validate organization (`/components/ui`, `/features/*`, `/layouts`)
- **Type Safety**: Check TypeScript prop interface coverage
- **Variant Systems**: Ensure discriminated unions over loose strings
- **Composition**: Validate composition patterns over prop drilling

## Installation

### Claude Code (User-level)
```bash
cp -r react-component-architecture ~/.claude/skills/
```

### Claude Code (Project-level)
```bash
cp -r react-component-architecture .claude/skills/
```

### Claude Apps
1. Drag the `react-component-architecture.zip` file into Claude Desktop
2. Skill will load automatically when analyzing React components

## Files Included

- `SKILL.md` - Skill definition and documentation
- `component_analyzer.py` - Parses TSX components and extracts metrics
- `prop_drilling_detector.py` - Detects deep prop passing patterns
- `duplicate_pattern_finder.py` - Identifies reusable UI patterns
- `folder_structure_validator.py` - Validates folder organization
- `architecture_reporter.py` - Generates comprehensive reports
- `sample_input.json` - Example configuration
- `expected_output.json` - Example report output
- `HOW_TO_USE.md` - Detailed usage guide
- `README.md` - This file

## Quick Start

### 1. Analyze Entire Codebase
```bash
python3 architecture_reporter.py src/
```

### 2. Export JSON for CI/CD
```bash
python3 architecture_reporter.py src/ --json --output report.json
```

### 3. Use with Claude
```
Hey Claude—I just added the "react-component-architecture" skill. Can you analyze src/ and generate an architecture report?
```

## Example Report

```markdown
React Component Architecture Report
====================================
Analyzed: 45 components in src/

⚠ Component Size Issues (3 found)
1. features/auth/LoginForm.tsx (245 lines)
   → Split into: <FormInput>, <FormButton>, <FormError>

⚠ Prop Drilling Detected (2 instances)
1. features/dashboard/Dashboard.tsx:45 (5 levels deep)
   → Use Context API or composition

✓ Duplicate Patterns Found (4 patterns)
1. Form Submit Buttons (3 files)
   → Extract: <SubmitButton variant="primary" loading={...} />

✓ Folder Structure: Compliant

⚠ Type Coverage: 87% (6 components missing types)

Architecture Health Score: 78/100
```

## Configuration

Create `architecture.config.json`:

```json
{
  "component_size_limit": 200,
  "prop_drilling_depth": 3,
  "min_duplicate_count": 3,
  "folder_structure": {
    "primitives": "components/ui",
    "features": "features",
    "layouts": "layouts",
    "utils": "utils"
  },
  "excluded_patterns": [
    "**/node_modules/**",
    "**/dist/**",
    "**/.next/**",
    "**/__tests__/**"
  ],
  "type_coverage_threshold": 95,
  "complexity_threshold": 10
}
```

## Folder Structure Best Practices

```
src/
├── components/
│   └── ui/              # Primitives only
│       ├── Button.tsx
│       ├── Input.tsx
│       └── Card.tsx
├── features/
│   ├── auth/            # Authentication
│   │   ├── LoginForm.tsx
│   │   └── SignupForm.tsx
│   └── dashboard/       # Dashboard
│       └── DashboardWidget.tsx
├── layouts/
│   ├── AppLayout.tsx
│   └── AuthLayout.tsx
└── utils/
    ├── cn.ts            # Tailwind class merger
    └── formatters.ts
```

## Integration

### Pre-commit Hook
```bash
#!/bin/bash
python3 architecture_reporter.py src/ --fail-on-violations
```

### GitHub Actions
```yaml
- name: Check Architecture
  run: |
    python3 architecture_reporter.py src/ --json > report.json
    if [ $(jq '.health_score' report.json) -lt 70 ]; then
      exit 1
    fi
```

## Health Score Guide

- **80-100**: Excellent architecture
- **70-79**: Good, minor improvements needed
- **60-69**: Needs improvement
- **<60**: Requires significant refactoring

## What Gets Checked

### Component Size (Max 200 lines)
- Primitives: 50-100 lines
- Features: 150-200 lines
- Layouts: 100-150 lines

### Prop Drilling (Max 3 levels)
```tsx
// ❌ Bad (5 levels)
<App user={user}>
  <Dashboard user={user}>
    <Panel user={user}>
      <Info user={user}>
        <Avatar user={user} />

// ✅ Good (Composition)
<Dashboard>
  <Panel>
    <Info>
      <Avatar user={user} />
```

### Variant Systems
```tsx
// ❌ Bad
type ButtonProps = {
  variant: string; // Any string
}

// ✅ Good
type ButtonProps = {
  variant: 'primary' | 'secondary' | 'ghost';
}
```

### Duplicate Patterns
- Buttons
- Inputs
- Cards
- Badges
- Spinners
- Error Messages
- Modals
- Form Submit Buttons

## Python Modules

### component_analyzer.py
- Parses TSX files
- Counts lines, props, hooks
- Calculates complexity
- Detects TypeScript interfaces

### prop_drilling_detector.py
- Traces prop chains
- Finds deep passing (>3 levels)
- Suggests refactoring strategies

### duplicate_pattern_finder.py
- Detects 8 common UI patterns
- Identifies files with duplicates
- Suggests primitive components

### folder_structure_validator.py
- Categorizes components (primitive/feature/layout)
- Validates locations
- Suggests reorganization

### architecture_reporter.py
- Orchestrates all analyses
- Calculates health score
- Generates reports (Markdown/JSON)
- CI/CD integration

## Requirements

- Python 3.8+
- TypeScript React codebase
- TSX files

## Limitations

- TSX parsing requires valid syntax
- Dynamic imports not detected
- Runtime props not analyzed
- Framework-specific (React only)
- Large codebases (1000+ components) may take 30-60 seconds

## Helpful Resources

- [React Composition Patterns](https://react.dev/learn/passing-props-to-a-component)
- [TypeScript React Cheatsheet](https://react-typescript-cheatsheet.netlify.app/)
- [Tailwind CSS Best Practices](https://tailwindcss.com/docs/reusing-styles)
- [shadcn/ui Components](https://ui.shadcn.com/)
- [Radix UI Primitives](https://www.radix-ui.com/)

## License

MIT

## Version

1.0.0
