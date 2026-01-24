#!/usr/bin/env python3
"""
Pattern Resolution Script

Resolves a pattern request YAML into Terraform variables:
1. Validates pattern name and config
2. Resolves t-shirt sizing based on environment
3. Evaluates conditional features (prod-only, etc.)
4. Outputs Terraform tfvars

Supports multi-document YAML files with action field (create/destroy).

Usage:
    python3 resolve-pattern.py <request.yaml> [--output tfvars|json|env|multi-json]
    python3 resolve-pattern.py --validate <request.yaml>
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml


# Default paths (relative to repo root)
REPO_ROOT = Path(__file__).parent.parent
PATTERNS_DIR = REPO_ROOT / "config" / "patterns"
SIZING_DEFAULTS = REPO_ROOT / "config" / "sizing-defaults.yaml"


class PatternResolver:
    """Resolves pattern requests to Terraform variables."""

    def __init__(self, patterns_dir: Path = PATTERNS_DIR, sizing_file: Path = SIZING_DEFAULTS):
        self.patterns_dir = patterns_dir
        self.sizing_file = sizing_file
        self.patterns: Dict[str, Dict] = {}
        self.sizing_defaults: Dict[str, Any] = {}
        self._load_metadata()

    def _load_metadata(self):
        """Load all pattern metadata and sizing defaults."""
        # Load sizing defaults
        if self.sizing_file.exists():
            with open(self.sizing_file) as f:
                self.sizing_defaults = yaml.safe_load(f)

        # Load pattern definitions
        if self.patterns_dir.exists():
            for pattern_file in self.patterns_dir.glob("*.yaml"):
                with open(pattern_file) as f:
                    pattern = yaml.safe_load(f)
                    if pattern and "name" in pattern:
                        self.patterns[pattern["name"]] = pattern

    def validate_request(self, request: Dict) -> Dict[str, Any]:
        """
        Validate a pattern request.

        Returns:
            {"valid": bool, "errors": list, "warnings": list}
        """
        errors = []
        warnings = []

        # Validate action field (optional, defaults to "create")
        action = request.get("action", "create")
        if action not in ["create", "destroy"]:
            errors.append(f"Invalid action: {action}. Must be 'create' or 'destroy'")

        # Check required fields
        if "pattern" not in request:
            errors.append("Missing required field: pattern")
        if "metadata" not in request:
            errors.append("Missing required field: metadata")
        else:
            meta = request.get("metadata", {})
            for field in ["project", "environment", "business_unit", "owners"]:
                if field not in meta:
                    errors.append(f"Missing required metadata field: {field}")

            # Validate environment
            env = meta.get("environment", "")
            if env not in ["dev", "staging", "prod"]:
                errors.append(f"Invalid environment: {env}. Must be dev, staging, or prod")

        # Validate pattern exists
        pattern_name = request.get("pattern", "")
        if pattern_name and pattern_name not in self.patterns:
            errors.append(f"Unknown pattern: {pattern_name}. Available: {list(self.patterns.keys())}")

        # Validate config
        config = request.get("config", {})
        if pattern_name in self.patterns:
            pattern = self.patterns[pattern_name]
            required_config = pattern.get("config", {}).get("required", [])
            for field in required_config:
                if field not in config:
                    errors.append(f"Missing required config field: {field}")

        return {
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings
        }

    def resolve(self, request: Dict) -> Dict[str, Any]:
        """
        Resolve a pattern request to Terraform variables.

        Args:
            request: Parsed YAML request

        Returns:
            Dictionary of Terraform variable values
        """
        # Validate first
        validation = self.validate_request(request)
        if not validation["valid"]:
            raise ValueError(f"Invalid request: {validation['errors']}")

        pattern_name = request["pattern"]
        pattern = self.patterns[pattern_name]
        metadata = request["metadata"]
        config = request.get("config", {})
        environment = metadata["environment"]

        # Determine size (from config or environment default)
        size = config.get("size", self._get_default_size(environment))

        # Get sizing values for this pattern/size/environment
        sizing = self._resolve_sizing(pattern, size, environment)

        # Start building terraform vars
        tfvars = {
            # Metadata
            "project": metadata["project"],
            "environment": environment,
            "business_unit": metadata["business_unit"],
            "owners": metadata["owners"],
            "location": metadata.get("location", "eastus"),

            # Pattern name for unique resource group naming
            "pattern_name": pattern_name,

            # Resource name from config
            "name": config.get("name", metadata["project"]),
        }

        # Add sizing-resolved values
        tfvars.update(sizing)

        # Add pattern-specific config values
        # Handle both list format (from YAML files) and dict format
        optional_raw = pattern.get("config", {}).get("optional", {})
        if isinstance(optional_raw, list):
            # Convert list of single-key dicts to a flat dict
            optional_config = {}
            for item in optional_raw:
                if isinstance(item, dict):
                    optional_config.update(item)
        else:
            optional_config = optional_raw

        for key, spec in optional_config.items():
            if key in config:
                tfvars[key] = config[key]
            elif isinstance(spec, dict) and "default" in spec:
                tfvars[key] = spec["default"]

        # Apply conditional features
        tfvars = self._apply_conditionals(tfvars, environment)

        return tfvars

    def _get_default_size(self, environment: str) -> str:
        """Get default t-shirt size for environment."""
        defaults = self.sizing_defaults.get("environment_defaults", {})
        return defaults.get(environment, "small")

    def _resolve_sizing(self, pattern: Dict, size: str, environment: str) -> Dict[str, Any]:
        """Resolve sizing values from pattern metadata."""
        sizing = pattern.get("sizing", {})

        # Get values for this size and environment
        if size in sizing and environment in sizing[size]:
            return sizing[size][environment].copy()

        # Fallback to common SKUs from sizing defaults
        common = self.sizing_defaults.get("common_skus", {})
        result = {}

        # Map pattern name to common SKU type
        pattern_name = pattern.get("name", "")
        if pattern_name in common:
            sku_info = common[pattern_name].get(size, {})
            if isinstance(sku_info, dict):
                result.update(sku_info)
            else:
                result["sku"] = sku_info

        return result

    def _apply_conditionals(self, tfvars: Dict[str, Any], environment: str) -> Dict[str, Any]:
        """Apply conditional features based on environment."""
        conditionals = self.sizing_defaults.get("conditional_features", {})

        for feature, env_values in conditionals.items():
            # Only apply if not already set
            if feature not in tfvars:
                tfvars[feature] = env_values.get(environment, False)

        # Note: access_review requires enable_access_review: true in sizing config
        # It is NOT auto-enabled when access_reviewers is provided because
        # the msgraph provider has reliability issues. Users can explicitly
        # set enable_access_review in their pattern config to override.

        return tfvars

    def get_cost_estimate(self, request: Dict) -> Dict[str, Any]:
        """Get estimated monthly cost for a pattern request."""
        pattern_name = request.get("pattern", "")
        if pattern_name not in self.patterns:
            return {"error": f"Unknown pattern: {pattern_name}"}

        pattern = self.patterns[pattern_name]
        config = request.get("config", {})
        environment = request.get("metadata", {}).get("environment", "dev")
        size = config.get("size", self._get_default_size(environment))

        costs = pattern.get("estimated_costs", {})
        if size in costs and environment in costs[size]:
            return {
                "pattern": pattern_name,
                "size": size,
                "environment": environment,
                "estimated_monthly_cost_usd": costs[size][environment]
            }

        return {"error": "Cost estimate not available"}

    def list_patterns(self) -> Dict[str, Dict]:
        """List all available patterns."""
        result = {}
        for name, pattern in self.patterns.items():
            result[name] = {
                "description": pattern.get("description", "").split("\n")[0],
                "category": pattern.get("category", "unknown"),
                "components": pattern.get("components", []),
            }
        return result

    def _compute_state_key(self, request: Dict) -> str:
        """Compute the Terraform state key for a pattern request."""
        metadata = request.get("metadata", {})
        pattern_name = request.get("pattern", "unknown")
        config = request.get("config", {})

        business_unit = metadata.get("business_unit", "default")
        environment = metadata.get("environment", "dev")
        project = metadata.get("project", "unknown")
        name = config.get("name", pattern_name)

        return f"{business_unit}/{environment}/{project}/{pattern_name}-{name}/terraform.tfstate"

    def resolve_all(self, documents: List[Dict]) -> List[Dict[str, Any]]:
        """
        Resolve all pattern documents from a multi-document YAML.

        Args:
            documents: List of parsed YAML documents

        Returns:
            List of results with index, action, pattern, tfvars, and state_key
        """
        results = []
        for i, doc in enumerate(documents):
            if doc is None:
                continue

            action = doc.get("action", "create")
            pattern_name = doc.get("pattern", "unknown")

            # Validate the document
            validation = self.validate_request(doc)
            if not validation["valid"]:
                results.append({
                    "index": i,
                    "action": action,
                    "pattern": pattern_name,
                    "valid": False,
                    "errors": validation["errors"],
                    "tfvars": None,
                    "state_key": None
                })
                continue

            # Resolve the pattern
            try:
                tfvars = self.resolve(doc)
                results.append({
                    "index": i,
                    "action": action,
                    "pattern": pattern_name,
                    "valid": True,
                    "errors": [],
                    "tfvars": tfvars,
                    "state_key": self._compute_state_key(doc)
                })
            except ValueError as e:
                results.append({
                    "index": i,
                    "action": action,
                    "pattern": pattern_name,
                    "valid": False,
                    "errors": [str(e)],
                    "tfvars": None,
                    "state_key": None
                })

        return results

    def compute_execution_order(self, results: List[Dict[str, Any]]) -> List[int]:
        """
        Compute the execution order for pattern results.

        Destroy actions run first, then create actions.

        Args:
            results: List of resolved pattern results

        Returns:
            List of indices in execution order
        """
        destroy_indices = []
        create_indices = []

        for result in results:
            if not result.get("valid", False):
                continue
            if result.get("action") == "destroy":
                destroy_indices.append(result["index"])
            else:
                create_indices.append(result["index"])

        # Destroy first, then create
        return destroy_indices + create_indices


def output_tfvars(tfvars: Dict[str, Any]) -> str:
    """Output Terraform tfvars format."""
    lines = []
    for key, value in sorted(tfvars.items()):
        if isinstance(value, bool):
            lines.append(f'{key} = {str(value).lower()}')
        elif isinstance(value, str):
            lines.append(f'{key} = "{value}"')
        elif isinstance(value, (int, float)):
            lines.append(f'{key} = {value}')
        elif isinstance(value, list):
            items = ", ".join(f'"{v}"' if isinstance(v, str) else str(v) for v in value)
            lines.append(f'{key} = [{items}]')
        elif isinstance(value, dict):
            lines.append(f'{key} = {json.dumps(value)}')
        else:
            lines.append(f'{key} = {json.dumps(value)}')
    return "\n".join(lines)


def output_env(tfvars: Dict[str, Any]) -> str:
    """Output environment variable format (for CI/CD)."""
    lines = []
    for key, value in sorted(tfvars.items()):
        env_key = f"TF_VAR_{key}"
        if isinstance(value, (list, dict)):
            lines.append(f'{env_key}={json.dumps(value)}')
        elif isinstance(value, bool):
            lines.append(f'{env_key}={str(value).lower()}')
        else:
            lines.append(f'{env_key}={value}')
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Resolve pattern request to Terraform variables"
    )
    parser.add_argument(
        "request_file",
        type=Path,
        help="Path to pattern request YAML file"
    )
    parser.add_argument(
        "--output", "-o",
        choices=["tfvars", "json", "env", "multi-json"],
        default="tfvars",
        help="Output format (default: tfvars). Use 'multi-json' for multi-document YAML files."
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Only validate the request, don't resolve"
    )
    parser.add_argument(
        "--cost",
        action="store_true",
        help="Show cost estimate"
    )
    parser.add_argument(
        "--list-patterns",
        action="store_true",
        help="List available patterns"
    )
    parser.add_argument(
        "--patterns-dir",
        type=Path,
        default=PATTERNS_DIR,
        help="Path to patterns directory"
    )
    parser.add_argument(
        "--sizing-file",
        type=Path,
        default=SIZING_DEFAULTS,
        help="Path to sizing defaults file"
    )

    args = parser.parse_args()

    resolver = PatternResolver(
        patterns_dir=args.patterns_dir,
        sizing_file=args.sizing_file
    )

    # List patterns mode
    if args.list_patterns:
        patterns = resolver.list_patterns()
        if args.output == "json":
            print(json.dumps(patterns, indent=2))
        else:
            for name, info in patterns.items():
                print(f"\n{name}:")
                print(f"  {info['description']}")
                print(f"  Category: {info['category']}")
                print(f"  Components: {', '.join(info['components'])}")
        return 0

    # Load request
    if not args.request_file.exists():
        print(f"Error: File not found: {args.request_file}", file=sys.stderr)
        return 1

    with open(args.request_file) as f:
        # Use safe_load_all for multi-document YAML support
        documents = list(yaml.safe_load_all(f))

    # Filter out None documents (empty documents in multi-doc YAML)
    documents = [doc for doc in documents if doc is not None]

    if not documents:
        print("Error: No valid documents found in YAML file", file=sys.stderr)
        return 1

    # Multi-document mode (multi-json output or multiple documents)
    is_multi_doc = len(documents) > 1 or args.output == "multi-json"

    if is_multi_doc:
        # Multi-document processing
        results = resolver.resolve_all(documents)
        execution_order = resolver.compute_execution_order(results)

        # Check for any validation errors
        all_valid = all(r.get("valid", False) for r in results)

        if args.validate:
            validation_results = []
            for r in results:
                validation_results.append({
                    "index": r["index"],
                    "action": r["action"],
                    "pattern": r["pattern"],
                    "valid": r["valid"],
                    "errors": r.get("errors", [])
                })
            output = {
                "document_count": len(documents),
                "all_valid": all_valid,
                "validations": validation_results,
                "execution_order": execution_order,
                "create_count": sum(1 for r in results if r.get("valid") and r.get("action") == "create"),
                "destroy_count": sum(1 for r in results if r.get("valid") and r.get("action") == "destroy")
            }
            print(json.dumps(output, indent=2))
            return 0 if all_valid else 1

        if args.cost:
            costs = []
            for doc in documents:
                cost = resolver.get_cost_estimate(doc)
                cost["action"] = doc.get("action", "create")
                costs.append(cost)
            print(json.dumps(costs, indent=2))
            return 0

        # Multi-json output for provisioning workflow
        output = {
            "document_count": len(documents),
            "all_valid": all_valid,
            "execution_order": execution_order,
            "patterns": results,
            "create_count": sum(1 for r in results if r.get("valid") and r.get("action") == "create"),
            "destroy_count": sum(1 for r in results if r.get("valid") and r.get("action") == "destroy")
        }

        if not all_valid:
            invalid_docs = [r for r in results if not r.get("valid")]
            print(f"Error: {len(invalid_docs)} document(s) failed validation", file=sys.stderr)
            for r in invalid_docs:
                print(f"  Document {r['index']}: {r['errors']}", file=sys.stderr)

        print(json.dumps(output, indent=2))
        return 0 if all_valid else 1

    # Single document mode (backward compatible)
    request = documents[0]

    # Validate mode
    if args.validate:
        validation = resolver.validate_request(request)
        if args.output == "json":
            print(json.dumps(validation, indent=2))
        else:
            if validation["valid"]:
                print("Request is valid")
            else:
                print("Request is invalid:")
                for error in validation["errors"]:
                    print(f"  - {error}")
            for warning in validation["warnings"]:
                print(f"  Warning: {warning}")
        return 0 if validation["valid"] else 1

    # Cost estimate mode
    if args.cost:
        cost = resolver.get_cost_estimate(request)
        if args.output == "json":
            print(json.dumps(cost, indent=2))
        else:
            if "error" in cost:
                print(f"Error: {cost['error']}")
                return 1
            print(f"Pattern: {cost['pattern']}")
            print(f"Size: {cost['size']}")
            print(f"Environment: {cost['environment']}")
            print(f"Estimated monthly cost: ${cost['estimated_monthly_cost_usd']}")
        return 0

    # Resolve mode
    try:
        tfvars = resolver.resolve(request)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    # Output
    if args.output == "json":
        print(json.dumps(tfvars, indent=2))
    elif args.output == "env":
        print(output_env(tfvars))
    else:
        print(output_tfvars(tfvars))

    return 0


if __name__ == "__main__":
    sys.exit(main())
