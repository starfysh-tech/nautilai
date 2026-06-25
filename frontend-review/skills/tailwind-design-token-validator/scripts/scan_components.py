"""
Component scanner module.
Scans directories for React/TypeScript component files.
"""

from pathlib import Path
from typing import List, Optional


class ComponentScanner:
    """Scan directories for React/TypeScript component files."""

    def __init__(self, base_directory: str, extensions: Optional[List[str]] = None):
        """
        Initialize component scanner.

        Args:
            base_directory: Root directory to scan
            extensions: File extensions to include (default: ['.tsx', '.jsx'])
        """
        self.base_directory = Path(base_directory)
        self.extensions = extensions or ['.tsx', '.jsx']

    def scan(self) -> List[Path]:
        """
        Scan directory for component files.

        Returns:
            List of component file paths
        """
        if not self.base_directory.exists():
            raise FileNotFoundError(f"Directory not found: {self.base_directory}")

        component_files = []

        for ext in self.extensions:
            # Recursively find all files with extension
            component_files.extend(self.base_directory.rglob(f"*{ext}"))

        # Exclude node_modules, build directories
        component_files = [
            f for f in component_files
            if not any(part.startswith('.') or part in ['node_modules', 'build', 'dist']
                      for part in f.parts)
        ]

        return sorted(component_files)

    def scan_css_files(self, css_directory: Optional[str] = None) -> List[Path]:
        """
        Scan for CSS files that might contain @apply.

        Args:
            css_directory: Directory to scan for CSS files (optional)

        Returns:
            List of CSS file paths
        """
        css_dir = Path(css_directory) if css_directory else self.base_directory

        if not css_dir.exists():
            return []

        css_files = []
        css_extensions = ['.css', '.scss', '.sass']

        for ext in css_extensions:
            css_files.extend(css_dir.rglob(f"*{ext}"))

        # Exclude node_modules, build directories
        css_files = [
            f for f in css_files
            if not any(part.startswith('.') or part in ['node_modules', 'build', 'dist']
                      for part in f.parts)
        ]

        return sorted(css_files)

    def read_file_lines(self, file_path: Path) -> List[str]:
        """
        Read file and return lines with content.

        Args:
            file_path: Path to file

        Returns:
            List of lines from file
        """
        try:
            return file_path.read_text().splitlines()
        except (OSError, UnicodeDecodeError) as e:
            print(f"Error reading {file_path}: {e}")
            return []
