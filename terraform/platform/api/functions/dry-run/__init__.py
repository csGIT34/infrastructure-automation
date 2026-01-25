"""
Dry Run API Function

Validates and resolves pattern requests without provisioning.
Provides pre-commit validation showing exactly what will be built.

POST /api/dry-run
Body: YAML content (infrastructure.yaml)
Returns: JSON with validation results, resolved patterns, and cost estimates
"""

import json
import logging
import azure.functions as func
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Default paths - patterns config is embedded in the function deployment
FUNCTION_ROOT = Path(__file__).parent.parent
PATTERNS_DIR = FUNCTION_ROOT / "config" / "patterns"
SIZING_DEFAULTS = FUNCTION_ROOT / "config" / "sizing-defaults.yaml"


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
        """Validate a pattern request."""
        errors = []
        warnings = []

        # Validate action field
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

        # Validate pattern_version is provided
        if "pattern_version" not in request:
            warnings.append("pattern_version not specified; will use latest version")

        return {
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings
        }

    def resolve(self, request: Dict) -> Dict[str, Any]:
        """Resolve a pattern request to Terraform variables."""
        validation = self.validate_request(request)
        if not validation["valid"]:
            raise ValueError(f"Invalid request: {validation['errors']}")

        pattern_name = request["pattern"]
        pattern = self.patterns[pattern_name]
        metadata = request["metadata"]
        config = request.get("config", {})
        environment = metadata["environment"]

        # Determine size
        size = config.get("size", self._get_default_size(environment))

        # Get sizing values
        sizing = self._resolve_sizing(pattern, size, environment)

        # Build terraform vars
        tfvars = {
            "project": metadata["project"],
            "environment": environment,
            "business_unit": metadata["business_unit"],
            "owners": metadata["owners"],
            "location": metadata.get("location", "eastus"),
            "pattern_name": pattern_name,
            "name": config.get("name", metadata["project"]),
        }

        tfvars.update(sizing)

        # Add pattern-specific config values
        optional_raw = pattern.get("config", {}).get("optional", {})
        if isinstance(optional_raw, list):
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

        if size in sizing and environment in sizing[size]:
            return sizing[size][environment].copy()

        # Fallback to common SKUs
        common = self.sizing_defaults.get("common_skus", {})
        result = {}

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
            if feature not in tfvars:
                tfvars[feature] = env_values.get(environment, False)

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

        return {"estimated_monthly_cost_usd": None}

    def get_pattern_info(self, pattern_name: str) -> Optional[Dict[str, Any]]:
        """Get detailed information about a pattern."""
        if pattern_name not in self.patterns:
            return None

        pattern = self.patterns[pattern_name]
        return {
            "name": pattern_name,
            "description": pattern.get("description", "").split("\n")[0],
            "category": pattern.get("category", "unknown"),
            "components": pattern.get("components", []),
            "use_cases": pattern.get("use_cases", [])
        }

    def _compute_resource_group(self, request: Dict) -> str:
        """Compute the resource group name for a pattern request."""
        metadata = request.get("metadata", {})
        pattern_name = request.get("pattern", "unknown")

        project = metadata.get("project", "unknown")
        environment = metadata.get("environment", "dev")

        return f"rg-{project}-{pattern_name}-{environment}"

    def resolve_all(self, documents: List[Dict]) -> List[Dict[str, Any]]:
        """Resolve all pattern documents from a multi-document YAML."""
        results = []
        for i, doc in enumerate(documents):
            if doc is None:
                continue

            action = doc.get("action", "create")
            pattern_name = doc.get("pattern", "unknown")

            validation = self.validate_request(doc)

            if not validation["valid"]:
                results.append({
                    "index": i,
                    "action": action,
                    "pattern": pattern_name,
                    "valid": False,
                    "errors": validation["errors"],
                    "warnings": validation.get("warnings", []),
                    "tfvars": None,
                    "cost_estimate": None,
                    "pattern_info": None,
                    "resource_group": None
                })
                continue

            try:
                tfvars = self.resolve(doc)
                cost = self.get_cost_estimate(doc)
                pattern_info = self.get_pattern_info(pattern_name)
                resource_group = self._compute_resource_group(doc)

                # Determine environment-specific features
                env = doc.get("metadata", {}).get("environment", "dev")
                env_features = []
                if tfvars.get("enable_diagnostics"):
                    env_features.append("diagnostics")
                if tfvars.get("enable_access_review"):
                    env_features.append("access_review")
                if tfvars.get("geo_redundant_backup"):
                    env_features.append("geo_redundant_backup")

                results.append({
                    "index": i,
                    "action": action,
                    "pattern": pattern_name,
                    "valid": True,
                    "errors": [],
                    "warnings": validation.get("warnings", []),
                    "components": pattern_info.get("components", []) if pattern_info else [],
                    "environment_features": env_features,
                    "resource_group": resource_group,
                    "estimated_cost_usd": cost.get("estimated_monthly_cost_usd"),
                    "tfvars": tfvars
                })
            except ValueError as e:
                results.append({
                    "index": i,
                    "action": action,
                    "pattern": pattern_name,
                    "valid": False,
                    "errors": [str(e)],
                    "warnings": [],
                    "tfvars": None,
                    "cost_estimate": None,
                    "resource_group": None
                })

        return results

    def compute_execution_order(self, results: List[Dict[str, Any]]) -> List[int]:
        """Compute execution order: destroy first, then create."""
        destroy_indices = []
        create_indices = []

        for result in results:
            if not result.get("valid", False):
                continue
            if result.get("action") == "destroy":
                destroy_indices.append(result["index"])
            else:
                create_indices.append(result["index"])

        return destroy_indices + create_indices


# Initialize resolver once (cold start optimization)
resolver = None


def get_resolver() -> PatternResolver:
    """Get or create the pattern resolver instance."""
    global resolver
    if resolver is None:
        resolver = PatternResolver()
    return resolver


def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Dry Run API endpoint.

    POST /api/dry-run
    Body: YAML content (infrastructure.yaml)

    Returns JSON response with:
    - valid: boolean indicating if all patterns are valid
    - documents: array of resolved pattern information
    - total_monthly_cost_usd: sum of all pattern costs
    - execution_order: indices in execution order (destroy first)
    - errors: array of any errors encountered
    """
    logger.info("Dry Run API invoked")

    # Get request body
    try:
        yaml_content = req.get_body().decode("utf-8")
    except Exception as e:
        logger.error(f"Failed to read request body: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Failed to read request body", "details": str(e)}),
            mimetype="application/json",
            status_code=400
        )

    if not yaml_content.strip():
        return func.HttpResponse(
            json.dumps({"error": "Empty request body"}),
            mimetype="application/json",
            status_code=400
        )

    # Parse YAML (supports multi-document)
    try:
        documents = list(yaml.safe_load_all(yaml_content))
        documents = [d for d in documents if d is not None]
    except yaml.YAMLError as e:
        logger.error(f"YAML parse error: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Invalid YAML", "details": str(e)}),
            mimetype="application/json",
            status_code=400
        )

    if not documents:
        return func.HttpResponse(
            json.dumps({"error": "No valid documents found in YAML"}),
            mimetype="application/json",
            status_code=400
        )

    # Resolve all patterns
    try:
        res = get_resolver()
        results = res.resolve_all(documents)
        execution_order = res.compute_execution_order(results)
    except Exception as e:
        logger.error(f"Pattern resolution error: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Pattern resolution failed", "details": str(e)}),
            mimetype="application/json",
            status_code=500
        )

    # Build response
    all_valid = all(r.get("valid", False) for r in results)
    all_errors = []
    total_cost = 0

    for r in results:
        if r.get("errors"):
            all_errors.extend([f"Document {r['index']}: {e}" for e in r["errors"]])
        if r.get("estimated_cost_usd"):
            total_cost += r["estimated_cost_usd"]

    # Build clean document results (exclude tfvars from response to keep it concise)
    doc_results = []
    for r in results:
        doc = {
            "index": r["index"],
            "pattern": r["pattern"],
            "action": r["action"],
            "valid": r["valid"],
            "errors": r.get("errors", []),
            "warnings": r.get("warnings", [])
        }

        if r["valid"]:
            doc.update({
                "components": r.get("components", []),
                "estimated_cost_usd": r.get("estimated_cost_usd"),
                "resource_group": r.get("resource_group"),
                "environment_features": r.get("environment_features", [])
            })

        doc_results.append(doc)

    response = {
        "valid": all_valid,
        "document_count": len(documents),
        "documents": doc_results,
        "total_monthly_cost_usd": total_cost if total_cost > 0 else None,
        "execution_order": execution_order,
        "create_count": sum(1 for r in results if r.get("valid") and r.get("action") == "create"),
        "destroy_count": sum(1 for r in results if r.get("valid") and r.get("action") == "destroy")
    }

    if all_errors:
        response["errors"] = all_errors

    status_code = 200 if all_valid else 400

    return func.HttpResponse(
        json.dumps(response, indent=2),
        mimetype="application/json",
        status_code=status_code
    )
