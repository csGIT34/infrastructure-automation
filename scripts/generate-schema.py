#!/usr/bin/env python3
"""
Generate derived files from pattern definitions.

This script reads all pattern definitions from config/patterns/*.yaml
and generates:
  1. schemas/infrastructure.yaml.json - JSON Schema for IDE validation
  2. web/index.html - PATTERNS_DATA section for the portal UI
  3. templates/infrastructure-workflow.yaml - valid_patterns list
  4. mcp-server/src/patterns.generated.json - Pattern data for MCP server

Usage:
    python scripts/generate-schema.py [--check]

Options:
    --check     Verify all generated files match (for CI)
"""

import json
import re
import sys
from pathlib import Path

import yaml

# Repository root (parent of scripts/)
REPO_ROOT = Path(__file__).parent.parent
PATTERNS_DIR = REPO_ROOT / "config" / "patterns"
SIZING_DEFAULTS_FILE = REPO_ROOT / "config" / "sizing-defaults.yaml"

# Output files
SCHEMA_OUTPUT_FILE = REPO_ROOT / "schemas" / "infrastructure.yaml.json"
PORTAL_HTML_FILE = REPO_ROOT / "web" / "index.html"
WORKFLOW_TEMPLATE_FILE = REPO_ROOT / "templates" / "infrastructure-workflow.yaml"
MCP_PATTERNS_FILE = REPO_ROOT / "mcp-server" / "src" / "patterns.generated.json"

# GitHub org for schema URL
GITHUB_ORG = "csGIT34"
GITHUB_REPO = "infrastructure-automation"

# Azure regions (common subset)
AZURE_REGIONS = [
    "eastus", "eastus2", "westus", "westus2", "westus3",
    "centralus", "northcentralus", "southcentralus", "westcentralus",
    "northeurope", "westeurope", "uksouth", "ukwest",
    "australiaeast", "australiasoutheast", "southeastasia", "eastasia",
    "japaneast", "japanwest", "brazilsouth",
    "canadacentral", "canadaeast", "koreacentral", "koreasouth",
    "francecentral", "germanywestcentral", "norwayeast", "switzerlandnorth",
    "uaenorth", "southafricanorth", "centralindia", "southindia", "westindia"
]


def load_patterns() -> dict:
    """Load all pattern definitions from config/patterns/*.yaml"""
    patterns = {}
    for pattern_file in sorted(PATTERNS_DIR.glob("*.yaml")):
        with open(pattern_file) as f:
            pattern = yaml.safe_load(f)
            patterns[pattern["name"]] = pattern
    return patterns


def load_sizing_defaults() -> dict:
    """Load sizing defaults from config/sizing-defaults.yaml"""
    with open(SIZING_DEFAULTS_FILE) as f:
        return yaml.safe_load(f)


def yaml_type_to_json_schema(type_str: str, field_def: dict = None) -> dict:
    """Convert YAML type definition to JSON Schema type"""
    field_def = field_def or {}

    type_mapping = {
        "string": {"type": "string"},
        "boolean": {"type": "boolean"},
        "number": {"type": "integer"},
        "integer": {"type": "integer"},
        "array": {"type": "array"},
        "object": {"type": "object", "additionalProperties": {"type": "string"}},
    }

    schema = type_mapping.get(type_str, {"type": "string"})

    # Handle array items
    if type_str == "array":
        items_type = field_def.get("items", "string")
        if isinstance(items_type, dict):
            schema["items"] = items_type
        else:
            schema["items"] = {"type": items_type}

    # Handle enums
    if "enum" in field_def:
        schema["enum"] = field_def["enum"]

    # Handle defaults
    if "default" in field_def:
        schema["default"] = field_def["default"]

    # Handle description
    if "description" in field_def:
        schema["description"] = field_def["description"]

    return schema


def build_config_properties(patterns: dict) -> dict:
    """Build the config properties schema from all patterns"""
    # Common properties for all patterns
    properties = {
        "name": {
            "type": "string",
            "pattern": "^[a-z][a-z0-9-]{0,20}$",
            "description": "Resource name suffix (lowercase, alphanumeric with hyphens, 1-21 chars)"
        },
        "size": {
            "type": "string",
            "enum": ["small", "medium", "large"],
            "description": "T-shirt size. Defaults: dev=small, staging=medium, prod=medium"
        }
    }

    # Collect all optional config fields from all patterns
    all_optional_fields = {}

    for pattern_name, pattern in patterns.items():
        config = pattern.get("config", {})

        # Add required fields beyond 'name'
        for req_field in config.get("required", []):
            if req_field == "name":
                continue
            # These are pattern-specific required fields
            if req_field not in all_optional_fields:
                all_optional_fields[req_field] = {
                    "type": "string",
                    "description": f"Required for {pattern_name} pattern"
                }

        # Add optional fields
        for opt_field in config.get("optional", []):
            if isinstance(opt_field, dict):
                for field_name, field_def in opt_field.items():
                    if field_name not in all_optional_fields:
                        field_type = field_def.get("type", "string")
                        all_optional_fields[field_name] = yaml_type_to_json_schema(
                            field_type, field_def
                        )
                        # Add pattern context to description
                        desc = field_def.get("description", "")
                        patterns_using = [p for p, pd in patterns.items()
                                         if any(field_name in (list(o.keys())[0] if isinstance(o, dict) else o)
                                               for o in pd.get("config", {}).get("optional", [])
                                               if isinstance(o, dict))]
                        if patterns_using and desc:
                            all_optional_fields[field_name]["description"] = f"{desc} (used by: {', '.join(patterns_using)})"
                        elif desc:
                            all_optional_fields[field_name]["description"] = desc

    properties.update(all_optional_fields)
    return properties


def build_pattern_required_fields(patterns: dict) -> list:
    """Build conditional required fields based on pattern selection"""
    conditions = []

    for pattern_name, pattern in patterns.items():
        config = pattern.get("config", {})
        required_fields = [f for f in config.get("required", []) if f != "name"]

        if required_fields:
            conditions.append({
                "if": {
                    "properties": {
                        "pattern": {"const": pattern_name}
                    }
                },
                "then": {
                    "properties": {
                        "config": {
                            "required": ["name"] + required_fields
                        }
                    }
                }
            })

    return conditions


def generate_json_schema(patterns: dict, sizing_defaults: dict) -> str:
    """Generate the JSON Schema"""
    pattern_names = sorted(patterns.keys())

    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": f"https://raw.githubusercontent.com/{GITHUB_ORG}/{GITHUB_REPO}/main/schemas/infrastructure.yaml.json",
        "title": "Infrastructure Pattern Request",
        "description": "Schema for infrastructure.yaml pattern request files used by the Infrastructure Self-Service Platform. Generated from config/patterns/*.yaml - DO NOT EDIT MANUALLY.",
        "type": "object",
        "required": ["version", "metadata", "pattern", "pattern_version", "config"],
        "additionalProperties": False,
        "properties": {
            "version": {
                "type": "string",
                "const": "1",
                "description": "Schema version (currently only '1' is supported)"
            },
            "action": {
                "type": "string",
                "enum": ["create", "destroy"],
                "default": "create",
                "description": "Action to perform: 'create' provisions resources, 'destroy' tears them down"
            },
            "metadata": {
                "type": "object",
                "description": "Project metadata for resource naming, tagging, and RBAC",
                "required": ["project", "environment", "business_unit", "owners"],
                "additionalProperties": False,
                "properties": {
                    "project": {
                        "type": "string",
                        "pattern": "^[a-z][a-z0-9-]{1,20}$",
                        "description": "Project name (lowercase, alphanumeric with hyphens, 2-21 chars). Used in resource naming."
                    },
                    "environment": {
                        "type": "string",
                        "enum": ["dev", "staging", "prod"],
                        "description": "Target environment. Affects sizing defaults and conditional features."
                    },
                    "business_unit": {
                        "type": "string",
                        "pattern": "^[a-z][a-z0-9-]{1,30}$",
                        "description": "Business unit for cost allocation and resource grouping"
                    },
                    "owners": {
                        "type": "array",
                        "items": {
                            "type": "string",
                            "format": "email"
                        },
                        "minItems": 1,
                        "description": "Email addresses of resource owners. Owners can manage security group membership."
                    },
                    "location": {
                        "type": "string",
                        "enum": AZURE_REGIONS,
                        "default": "eastus",
                        "description": "Azure region for resource deployment"
                    }
                }
            },
            "pattern": {
                "type": "string",
                "enum": pattern_names,
                "description": "Infrastructure pattern to provision. See pattern reference for details."
            },
            "pattern_version": {
                "type": "string",
                "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$",
                "description": "Semantic version of the pattern (e.g., '1.0.0'). Required for reproducibility."
            },
            "config": {
                "type": "object",
                "description": "Pattern-specific configuration",
                "required": ["name"],
                "properties": build_config_properties(patterns)
            }
        },
        "allOf": build_pattern_required_fields(patterns),
        "examples": [
            {
                "version": "1",
                "metadata": {
                    "project": "myapp",
                    "environment": "dev",
                    "business_unit": "engineering",
                    "owners": ["alice@company.com", "bob@company.com"],
                    "location": "eastus"
                },
                "pattern": "keyvault",
                "pattern_version": "1.0.0",
                "config": {
                    "name": "secrets",
                    "size": "small"
                }
            },
            {
                "version": "1",
                "action": "destroy",
                "metadata": {
                    "project": "myapp",
                    "environment": "dev",
                    "business_unit": "engineering",
                    "owners": ["alice@company.com"]
                },
                "pattern": "postgresql",
                "pattern_version": "1.0.0",
                "config": {
                    "name": "olddb"
                }
            }
        ]
    }

    return json.dumps(schema, indent=2) + "\n"


def generate_portal_patterns_data(patterns: dict) -> str:
    """Generate PATTERNS_DATA JavaScript object for the portal"""
    # Build the patterns data structure expected by the portal
    portal_patterns = {}

    for name, pattern in sorted(patterns.items()):
        # Map category names
        category = pattern.get("category", "single-resource")
        if category == "single-resource":
            portal_category = "single-resource"
        elif category == "composite":
            portal_category = "composite"
        else:
            portal_category = category

        portal_pattern = {
            "name": name,
            "description": pattern.get("description", "").strip(),
            "category": portal_category,
            "components": pattern.get("components", []),
            "use_cases": pattern.get("use_cases", []),
            "sizing": pattern.get("sizing", {}),
            "config": pattern.get("config", {"required": ["name"], "optional": []}),
            "estimated_costs": pattern.get("estimated_costs", {}),
        }

        # Add example if present
        if "example" in pattern:
            portal_pattern["example"] = pattern["example"]

        portal_patterns[name] = portal_pattern

    # Build the full PATTERNS_DATA structure
    patterns_data = {
        "patterns": portal_patterns,
        "environments": [
            {"value": "dev", "label": "Development"},
            {"value": "staging", "label": "Staging"},
            {"value": "prod", "label": "Production"}
        ]
    }

    # Format as JavaScript (indented for readability in the HTML)
    json_str = json.dumps(patterns_data, indent=2)
    return json_str


def update_portal_html(patterns: dict) -> tuple[str, str]:
    """Update PATTERNS_DATA in portal HTML file, return (old_content, new_content)"""
    with open(PORTAL_HTML_FILE) as f:
        content = f.read()

    old_content = content

    # Find the PATTERNS_DATA section using markers
    start_marker = "// PATTERNS_DATA_START"
    end_marker = "// PATTERNS_DATA_END"

    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker)

    if start_idx == -1 or end_idx == -1:
        raise ValueError(f"Could not find PATTERNS_DATA markers in {PORTAL_HTML_FILE}")

    # Generate new patterns data
    patterns_json = generate_portal_patterns_data(patterns)

    # Build the replacement section
    new_section = f"""{start_marker} (auto-generated - do not edit manually)
        const PATTERNS_DATA = {patterns_json};
        {end_marker}"""

    # Replace the section
    new_content = content[:start_idx] + new_section + content[end_idx + len(end_marker):]

    return old_content, new_content


def update_workflow_template(patterns: dict) -> tuple[str, str]:
    """Update valid_patterns in workflow template, return (old_content, new_content)"""
    with open(WORKFLOW_TEMPLATE_FILE) as f:
        content = f.read()

    old_content = content

    # Build the new valid_patterns list
    pattern_names = sorted(patterns.keys())

    # Format as Python list for the workflow (which uses inline Python)
    # Split into multiple lines for readability
    single_patterns = [p for p in pattern_names if patterns[p].get("category") != "composite"]
    composite_patterns = [p for p in pattern_names if patterns[p].get("category") == "composite"]

    patterns_str = "[\n"
    patterns_str += "              # Single-resource patterns (auto-generated)\n"
    patterns_str += "              " + ", ".join(f"'{p}'" for p in single_patterns) + ",\n"
    patterns_str += "              # Composite patterns (auto-generated)\n"
    patterns_str += "              " + ", ".join(f"'{p}'" for p in composite_patterns) + "\n"
    patterns_str += "          ]"

    # Replace the valid_patterns list using regex
    pattern = r"valid_patterns = \[.*?\]"
    new_content = re.sub(pattern, f"valid_patterns = {patterns_str}", content, flags=re.DOTALL)

    return old_content, new_content


def generate_mcp_patterns_json(patterns: dict) -> str:
    """Generate patterns.generated.json for MCP server"""
    # Build pattern definitions in the format expected by the MCP server
    mcp_patterns = {}

    for name, pattern in sorted(patterns.items()):
        mcp_pattern = {
            "name": name,
            "description": pattern.get("description", "").strip(),
            "category": "single" if pattern.get("category") == "single-resource" else pattern.get("category", "single"),
            "components": pattern.get("components", []),
            "use_cases": pattern.get("use_cases", []),
            "config": {
                "required": pattern.get("config", {}).get("required", ["name"]),
                "optional": {}
            },
            "sizing": pattern.get("sizing", {}),
            "estimated_costs": pattern.get("estimated_costs", {})
        }

        # Convert optional config to MCP format
        for opt_field in pattern.get("config", {}).get("optional", []):
            if isinstance(opt_field, dict):
                for field_name, field_def in opt_field.items():
                    mcp_pattern["config"]["optional"][field_name] = {
                        "type": field_def.get("type", "string"),
                        "default": field_def.get("default"),
                        "description": field_def.get("description", "")
                    }
                    if "enum" in field_def:
                        mcp_pattern["config"]["optional"][field_name]["enum"] = field_def["enum"]

        mcp_patterns[name] = mcp_pattern

    output = {
        "_comment": "Auto-generated from config/patterns/*.yaml - DO NOT EDIT MANUALLY",
        "_generator": "scripts/generate-schema.py",
        "patterns": mcp_patterns
    }

    return json.dumps(output, indent=2) + "\n"


def main():
    check_mode = "--check" in sys.argv
    errors = []

    # Load pattern definitions
    print(f"Loading patterns from {PATTERNS_DIR}...")
    patterns = load_patterns()
    print(f"  Found {len(patterns)} patterns: {', '.join(sorted(patterns.keys()))}")

    # Load sizing defaults
    print(f"Loading sizing defaults from {SIZING_DEFAULTS_FILE}...")
    sizing_defaults = load_sizing_defaults()

    # 1. Generate JSON Schema
    print("\n1. JSON Schema (schemas/infrastructure.yaml.json)")
    schema_json = generate_json_schema(patterns, sizing_defaults)

    if check_mode:
        if not SCHEMA_OUTPUT_FILE.exists():
            errors.append(f"Schema file does not exist: {SCHEMA_OUTPUT_FILE}")
        elif SCHEMA_OUTPUT_FILE.read_text() != schema_json:
            errors.append(f"JSON Schema is out of date: {SCHEMA_OUTPUT_FILE}")
        else:
            print("   OK: Schema is up to date")
    else:
        SCHEMA_OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
        SCHEMA_OUTPUT_FILE.write_text(schema_json)
        print(f"   Wrote {SCHEMA_OUTPUT_FILE}")

    # 2. Update Portal HTML
    print("\n2. Portal PATTERNS_DATA (web/index.html)")
    old_html, new_html = update_portal_html(patterns)

    if check_mode:
        current_html = PORTAL_HTML_FILE.read_text()
        if current_html != new_html:
            errors.append(f"Portal PATTERNS_DATA is out of date: {PORTAL_HTML_FILE}")
        else:
            print("   OK: Portal is up to date")
    else:
        PORTAL_HTML_FILE.write_text(new_html)
        print(f"   Updated {PORTAL_HTML_FILE}")

    # 3. Update Workflow Template
    print("\n3. Workflow valid_patterns (templates/infrastructure-workflow.yaml)")
    old_workflow, new_workflow = update_workflow_template(patterns)

    if check_mode:
        current_workflow = WORKFLOW_TEMPLATE_FILE.read_text()
        if current_workflow != new_workflow:
            errors.append(f"Workflow valid_patterns is out of date: {WORKFLOW_TEMPLATE_FILE}")
        else:
            print("   OK: Workflow is up to date")
    else:
        WORKFLOW_TEMPLATE_FILE.write_text(new_workflow)
        print(f"   Updated {WORKFLOW_TEMPLATE_FILE}")

    # 4. Generate MCP Patterns JSON
    print("\n4. MCP patterns.generated.json (mcp-server/src/patterns.generated.json)")
    mcp_json = generate_mcp_patterns_json(patterns)

    if check_mode:
        if not MCP_PATTERNS_FILE.exists():
            errors.append(f"MCP patterns file does not exist: {MCP_PATTERNS_FILE}")
        elif MCP_PATTERNS_FILE.read_text() != mcp_json:
            errors.append(f"MCP patterns file is out of date: {MCP_PATTERNS_FILE}")
        else:
            print("   OK: MCP patterns file is up to date")
    else:
        MCP_PATTERNS_FILE.parent.mkdir(parents=True, exist_ok=True)
        MCP_PATTERNS_FILE.write_text(mcp_json)
        print(f"   Wrote {MCP_PATTERNS_FILE}")

    # Summary
    print("\n" + "=" * 60)
    if check_mode:
        if errors:
            print("FAILED: The following files are out of sync:\n")
            for e in errors:
                print(f"  - {e}")
            print("\nRun 'python scripts/generate-schema.py' to regenerate.")
            sys.exit(1)
        else:
            print("OK: All generated files are up to date.")
    else:
        print("SUCCESS: All files generated from config/patterns/*.yaml")
        print(f"\nPatterns: {len(patterns)}")
        print(f"Files updated: 4")


if __name__ == "__main__":
    main()
