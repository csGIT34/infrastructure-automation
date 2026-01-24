#!/usr/bin/env python3
"""
Generate portal data from pattern YAML configs.

Reads all config/patterns/*.yaml files and config/sizing-defaults.yaml,
then outputs JSON for the portal.

Usage:
    python scripts/generate-portal-data.py                    # Print JSON to stdout
    python scripts/generate-portal-data.py --embed            # Embed in web/index.html
    python scripts/generate-portal-data.py --output portal.json  # Write to file
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone

import yaml


def load_pattern_configs(patterns_dir: str) -> dict:
    """Load all pattern YAML files from the patterns directory."""
    patterns = {}

    for path in sorted(glob.glob(os.path.join(patterns_dir, "*.yaml"))):
        with open(path, "r") as f:
            try:
                data = yaml.safe_load(f)
                if data and "name" in data:
                    patterns[data["name"]] = data
            except yaml.YAMLError as e:
                print(f"Warning: Failed to parse {path}: {e}", file=sys.stderr)

    return patterns


def load_sizing_defaults(path: str) -> dict:
    """Load sizing defaults configuration."""
    if not os.path.exists(path):
        return {}

    with open(path, "r") as f:
        return yaml.safe_load(f) or {}


def get_category_display_name(category: str) -> str:
    """Get human-readable category name."""
    mapping = {
        "single-resource": "Single Resource",
        "single": "Single Resource",
        "composite": "Composite",
    }
    return mapping.get(category, category.title())


def get_pattern_icon(pattern_name: str) -> str:
    """Get an icon/emoji for a pattern based on its type."""
    icons = {
        "keyvault": "key",
        "postgresql": "database",
        "mongodb": "database",
        "sql-database": "database",
        "storage": "folder",
        "function-app": "zap",
        "static-site": "globe",
        "eventhub": "activity",
        "aks-namespace": "box",
        "linux-vm": "server",
        "microservice": "layers",
        "web-app": "layout",
        "api-backend": "cpu",
        "data-pipeline": "git-branch",
    }
    return icons.get(pattern_name, "package")


def generate_portal_data(patterns_dir: str, sizing_defaults_path: str) -> dict:
    """Generate the complete portal data structure."""
    patterns = load_pattern_configs(patterns_dir)
    sizing_defaults = load_sizing_defaults(sizing_defaults_path)

    # Enhance patterns with computed fields
    for name, pattern in patterns.items():
        pattern["icon"] = get_pattern_icon(name)
        pattern["category_display"] = get_category_display_name(
            pattern.get("category", "single-resource")
        )

    # Sort patterns: single-resource first, then composite
    def sort_key(item):
        name, pattern = item
        category = pattern.get("category", "single-resource")
        is_composite = 1 if category == "composite" else 0
        return (is_composite, name)

    sorted_patterns = dict(sorted(patterns.items(), key=sort_key))

    return {
        "patterns": sorted_patterns,
        "sizing_defaults": sizing_defaults,
        "metadata": {
            "pattern_count": len(patterns),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "categories": {
                "single-resource": len([p for p in patterns.values() if p.get("category") != "composite"]),
                "composite": len([p for p in patterns.values() if p.get("category") == "composite"]),
            }
        },
        "locations": [
            {"value": "eastus", "label": "East US"},
            {"value": "eastus2", "label": "East US 2"},
            {"value": "westus", "label": "West US"},
            {"value": "westus2", "label": "West US 2"},
            {"value": "centralus", "label": "Central US"},
            {"value": "northeurope", "label": "North Europe"},
            {"value": "westeurope", "label": "West Europe"},
            {"value": "uksouth", "label": "UK South"},
            {"value": "southeastasia", "label": "Southeast Asia"},
            {"value": "australiaeast", "label": "Australia East"},
        ],
        "environments": [
            {"value": "dev", "label": "Development"},
            {"value": "staging", "label": "Staging"},
            {"value": "prod", "label": "Production"},
        ],
    }


def embed_in_html(data: dict, html_path: str) -> None:
    """Embed the JSON data in the HTML file."""
    if not os.path.exists(html_path):
        print(f"Error: HTML file not found: {html_path}", file=sys.stderr)
        sys.exit(1)

    with open(html_path, "r") as f:
        html_content = f.read()

    # Find and replace the PATTERNS_DATA placeholder or existing embedded data
    json_str = json.dumps(data, indent=2)

    # Pattern to match the PATTERNS_DATA assignment
    import re
    pattern = r"const PATTERNS_DATA = \{[^;]*\};"
    replacement = f"const PATTERNS_DATA = {json_str};"

    if re.search(pattern, html_content, re.DOTALL):
        # Replace existing embedded data
        html_content = re.sub(pattern, replacement, html_content, flags=re.DOTALL)
    else:
        # Look for a placeholder comment and insert after it
        placeholder = "// PATTERNS_DATA_PLACEHOLDER"
        if placeholder in html_content:
            html_content = html_content.replace(
                placeholder,
                f"{placeholder}\n        {replacement}"
            )
        else:
            print(f"Warning: Could not find PATTERNS_DATA in {html_path}", file=sys.stderr)
            print("Data will be printed to stdout instead.", file=sys.stderr)
            print(json.dumps(data, indent=2))
            return

    with open(html_path, "w") as f:
        f.write(html_content)

    print(f"Embedded {len(data['patterns'])} patterns in {html_path}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Generate portal data from pattern configs"
    )
    parser.add_argument(
        "--patterns-dir",
        default="config/patterns",
        help="Directory containing pattern YAML files"
    )
    parser.add_argument(
        "--sizing-defaults",
        default="config/sizing-defaults.yaml",
        help="Path to sizing defaults YAML file"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output file path (default: stdout)"
    )
    parser.add_argument(
        "--embed",
        action="store_true",
        help="Embed data in web/index.html"
    )
    parser.add_argument(
        "--html-path",
        default="web/index.html",
        help="HTML file path for --embed mode"
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Output compact JSON (no indentation)"
    )

    args = parser.parse_args()

    # Handle relative paths from repo root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)

    patterns_dir = args.patterns_dir
    if not os.path.isabs(patterns_dir):
        patterns_dir = os.path.join(repo_root, patterns_dir)

    sizing_defaults = args.sizing_defaults
    if not os.path.isabs(sizing_defaults):
        sizing_defaults = os.path.join(repo_root, sizing_defaults)

    # Generate data
    data = generate_portal_data(patterns_dir, sizing_defaults)

    if args.embed:
        html_path = args.html_path
        if not os.path.isabs(html_path):
            html_path = os.path.join(repo_root, html_path)
        embed_in_html(data, html_path)
    elif args.output:
        output_path = args.output
        if not os.path.isabs(output_path):
            output_path = os.path.join(repo_root, output_path)
        with open(output_path, "w") as f:
            json.dump(data, f, indent=None if args.compact else 2)
        print(f"Wrote {len(data['patterns'])} patterns to {output_path}", file=sys.stderr)
    else:
        # Output to stdout
        indent = None if args.compact else 2
        print(json.dumps(data, indent=indent))


if __name__ == "__main__":
    main()
