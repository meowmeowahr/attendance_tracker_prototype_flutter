#!/usr/bin/env python3
"""
Web App Launcher Generator

Generates a single HTML file that serves as a landing page with version selection
and automatic redirection to the selected version.

Usage:
    python3 generate.py -o /path/to/output.html 0.1.0 0.1.1 0.2.0 0.3.0
"""

import argparse
import sys
from pathlib import Path
from typing import List


def generate_html(versions: List[str], root: str) -> str:
    """Generate the HTML content for the launcher page using the template."""
    
    # Sort versions in descending order (newest first)
    sorted_versions = sorted(versions, reverse=True)
    
    # Read the template file
    template_path = Path(__file__).parent / 'index.html'
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            template_content = f.read()
    except FileNotFoundError:
        raise FileNotFoundError(f"Template file not found: {template_path}")
    
    # Replace the VERSION_LIST placeholder with the actual versions
    version_list_str = ', '.join([f'"{version}"' for version in sorted_versions])
    html_content = template_content.replace('VERSION_LIST_PLACEHOLDER', version_list_str).replace('ROOT_PTH', root)

    return html_content


def main():
    """Main function to parse arguments and generate the HTML file."""
    parser = argparse.ArgumentParser(
        description="Generate a web app launcher HTML file with version selection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python3 generate.py -r /attendance_tracker_prototype_flutter/ -o launcher.html 0.1.0 0.1.1 0.2.0 0.3.0
    python3 generate.py --root /attendance_tracker_prototype_flutter/ --output /path/to/output.html 1.0.0 1.1.0 2.0.0
        """
    )
    
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output HTML file path'
    )

    parser.add_argument(
        '-r', '--root',
        default='/',
        help='Root URL path for the versions'
    )
    
    parser.add_argument(
        'versions',
        nargs='+',
        help='Version numbers to include in the launcher'
    )
    
    args = parser.parse_args()
    
    # Validate versions (basic check for version format)
    for version in args.versions:
        if not version.replace('.', '').replace('-', '').replace('_', '').isalnum():
            print(f"Warning: '{version}' might not be a valid version number", file=sys.stderr)
    
    try:
        # Generate HTML content
        html_content = generate_html(args.versions, args.root)
        
        # Write to output file
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        print(f"Successfully generated launcher HTML: {output_path}")
        print(f"Included versions: {', '.join(sorted(args.versions, reverse=True))}")
        
    except Exception as e:
        print(f"Error generating HTML file: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
