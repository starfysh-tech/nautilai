"""
Folder structure validation module.
Ensures components are organized according to architecture rules.
"""

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional


class ComponentCategory(Enum):
    """Component categories."""
    PRIMITIVE = "primitive"
    FEATURE = "feature"
    LAYOUT = "layout"
    PAGE = "page"
    UTILITY = "utility"
    UNKNOWN = "unknown"


@dataclass
class FolderViolation:
    """Folder structure violation."""
    file_path: str
    current_location: str
    expected_location: str
    category: ComponentCategory
    reason: str


class FolderStructureValidator:
    """Validate React component folder organization."""

    def __init__(self, source_dir: str, rules: Optional[Dict[str, str]] = None):
        """
        Initialize folder structure validator.

        Args:
            source_dir: Path to source directory
            rules: Custom folder rules (overrides defaults)
        """
        self.source_dir = Path(source_dir)
        self.rules = rules or {
            'primitives': 'components/ui',
            'features': 'features',
            'layouts': 'layouts',
            'pages': 'pages',
            'utils': 'utils',
            'hooks': 'hooks',
            'types': 'types'
        }
        self.violations: List[FolderViolation] = []

    def validate_directory(self) -> List[FolderViolation]:
        """
        Validate entire directory structure.

        Returns:
            List of folder structure violations
        """
        tsx_files = list(self.source_dir.rglob("*.tsx"))

        # Skip test files and node_modules
        tsx_files = [f for f in tsx_files if not any(
            x in str(f) for x in ['node_modules', 'dist', '.next', '__tests__', '.test.', '.spec.']
        )]

        for file_path in tsx_files:
            category = self._categorize_component(file_path)
            expected_location = self._get_expected_location(category, file_path)

            # Check if file is in correct location
            relative_path = file_path.relative_to(self.source_dir)
            current_location = str(relative_path.parent)

            if not self._is_in_correct_location(current_location, expected_location, category):
                self.violations.append(FolderViolation(
                    file_path=str(relative_path),
                    current_location=current_location,
                    expected_location=expected_location,
                    category=category,
                    reason=self._get_violation_reason(category, current_location, expected_location)
                ))

        return self.violations

    def _categorize_component(self, file_path: Path) -> ComponentCategory:
        """
        Categorize component based on its characteristics.

        Args:
            file_path: Path to component file

        Returns:
            Component category
        """
        try:
            content = file_path.read_text(encoding='utf-8')
        except Exception:
            return ComponentCategory.UNKNOWN

        file_name = file_path.stem

        # Check if it's a primitive (ui component)
        if self._is_primitive(content, file_name):
            return ComponentCategory.PRIMITIVE

        # Check if it's a layout
        if self._is_layout(content, file_name):
            return ComponentCategory.LAYOUT

        # Check if it's a page
        if self._is_page(content, file_name):
            return ComponentCategory.PAGE

        # Check if it's a feature component
        if self._is_feature(content, file_name):
            return ComponentCategory.FEATURE

        return ComponentCategory.UNKNOWN

    def _is_primitive(self, content: str, file_name: str) -> bool:
        """Check if component is a primitive UI component."""
        # Primitive indicators
        primitive_names = [
            'Button', 'Input', 'Select', 'Checkbox', 'Radio', 'Switch',
            'Card', 'Badge', 'Avatar', 'Icon', 'Spinner', 'Loader',
            'Alert', 'Toast', 'Tooltip', 'Popover', 'Dialog', 'Modal',
            'Tabs', 'Accordion', 'Dropdown', 'Menu', 'Label', 'Textarea'
        ]

        # Check file name
        if any(name.lower() in file_name.lower() for name in primitive_names):
            return True

        # Check if component is simple (no business logic)
        has_business_logic = any([
            'useEffect(' in content,
            'useState(' in content and content.count('useState(') > 2,
            'fetch(' in content,
            'axios' in content,
            'api.' in content
        ])

        # Check for variant system
        has_variants = 'variant' in content or 'size' in content

        # Primitives are simple and often have variants
        return has_variants and not has_business_logic

    def _is_layout(self, content: str, file_name: str) -> bool:
        """Check if component is a layout."""
        layout_indicators = [
            'Layout' in file_name,
            'Sidebar' in file_name,
            'Header' in file_name,
            'Footer' in file_name,
            'Navigation' in file_name,
            'Nav' in file_name
        ]

        return any(layout_indicators)

    def _is_page(self, content: str, file_name: str) -> bool:
        """Check if component is a page."""
        page_indicators = [
            'Page' in file_name,
            file_name.endswith('page'),
            'export default function' in content and 'Page' in content
        ]

        return any(page_indicators)

    def _is_feature(self, content: str, file_name: str) -> bool:
        """Check if component is a feature component."""
        # Feature components typically have:
        # - Business logic
        # - API calls
        # - State management
        # - Specific business domain in name

        feature_indicators = [
            'Form' in file_name,
            'List' in file_name,
            'Table' in file_name,
            'Dashboard' in file_name,
            'Profile' in file_name,
            'Settings' in file_name,
            'Auth' in file_name,
            'Login' in file_name,
            'Signup' in file_name
        ]

        has_business_logic = any([
            'useState(' in content,
            'useEffect(' in content,
            'fetch(' in content,
            'axios' in content,
            'api.' in content
        ])

        return any(feature_indicators) or has_business_logic

    def _get_expected_location(self, category: ComponentCategory, file_path: Path) -> str:
        """Get expected location for component category."""
        if category == ComponentCategory.PRIMITIVE:
            return self.rules['primitives']
        elif category == ComponentCategory.FEATURE:
            # Feature components can be in feature-specific folders
            return self.rules['features']
        elif category == ComponentCategory.LAYOUT:
            return self.rules['layouts']
        elif category == ComponentCategory.PAGE:
            return self.rules.get('pages', 'pages')
        else:
            return "components"  # Default fallback

    def _is_in_correct_location(self, current: str, expected: str, category: ComponentCategory) -> bool:
        """Check if file is in correct location."""
        # Normalize paths
        current = current.replace('\\', '/')
        expected = expected.replace('\\', '/')

        # Check if current location starts with expected
        if current.startswith(expected):
            return True

        # For features, allow subfolders
        if category == ComponentCategory.FEATURE:
            if 'features/' in current or 'feature/' in current:
                return True

        return False

    def _get_violation_reason(self, category: ComponentCategory, current: str, expected: str) -> str:
        """Get human-readable reason for violation."""
        reasons = {
            ComponentCategory.PRIMITIVE: f"Primitive components should be in {expected}/ for reusability",
            ComponentCategory.FEATURE: f"Feature components should be in {expected}/ organized by domain",
            ComponentCategory.LAYOUT: f"Layout components should be in {expected}/ for consistency",
            ComponentCategory.PAGE: f"Page components should be in {expected}/ for routing clarity",
            ComponentCategory.UNKNOWN: "Component category unclear - consider reorganizing"
        }

        return reasons.get(category, "Component is in unexpected location")

    def generate_report(self) -> str:
        """
        Generate markdown report of folder violations.

        Returns:
            Markdown formatted report
        """
        if not self.violations:
            return "✓ Folder Structure: Compliant\n"

        report = f"⚠ Folder Structure Violations ({len(self.violations)} found)\n"
        report += "=" * 50 + "\n\n"

        # Group by category
        by_category: Dict[ComponentCategory, List[FolderViolation]] = {}
        for v in self.violations:
            if v.category not in by_category:
                by_category[v.category] = []
            by_category[v.category].append(v)

        for category, violations in by_category.items():
            report += f"{category.value.capitalize()} Components ({len(violations)})\n"
            report += "-" * 50 + "\n"

            for v in violations:
                report += f"  ❌ {v.file_path}\n"
                report += f"     Current: {v.current_location}\n"
                report += f"     Expected: {v.expected_location}\n"
                report += f"     Reason: {v.reason}\n\n"

        # Add summary
        report += "\nSummary\n"
        report += "-" * 50 + "\n"
        report += f"Total violations: {len(self.violations)}\n"
        for category, violations in by_category.items():
            report += f"  - {category.value}: {len(violations)}\n"

        return report

    def get_summary(self) -> Dict[str, Any]:
        """Get summary statistics."""
        by_category: Dict[str, int] = {}
        for v in self.violations:
            cat = v.category.value
            by_category[cat] = by_category.get(cat, 0) + 1

        return {
            'total_violations': len(self.violations),
            'violations_by_category': by_category,
            'is_compliant': len(self.violations) == 0
        }

    def suggest_folder_structure(self) -> str:
        """Suggest ideal folder structure."""
        structure = """
Suggested Folder Structure
==========================

src/
├── components/
│   └── ui/                    # Primitives only
│       ├── Button.tsx
│       ├── Input.tsx
│       ├── Card.tsx
│       ├── Badge.tsx
│       └── Dialog.tsx
├── features/
│   ├── auth/                  # Authentication feature
│   │   ├── LoginForm.tsx
│   │   ├── SignupForm.tsx
│   │   └── ForgotPassword.tsx
│   ├── dashboard/             # Dashboard feature
│   │   ├── DashboardHeader.tsx
│   │   ├── DashboardStats.tsx
│   │   └── DashboardChart.tsx
│   └── profile/               # Profile feature
│       ├── ProfileForm.tsx
│       └── ProfileAvatar.tsx
├── layouts/
│   ├── AppLayout.tsx
│   ├── AuthLayout.tsx
│   └── DashboardLayout.tsx
├── pages/
│   ├── HomePage.tsx
│   ├── DashboardPage.tsx
│   └── SettingsPage.tsx
└── utils/
    ├── cn.ts                  # Tailwind class merger
    └── formatters.ts
"""
        return structure
