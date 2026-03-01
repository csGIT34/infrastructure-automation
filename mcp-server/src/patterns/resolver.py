"""Resolve pattern configs to Terraform variables.

Ported from scripts/resolve-pattern.py for use in the MCP server.
"""

import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

# Default sizes by environment (no external sizing-defaults.yaml needed)
DEFAULT_SIZES = {
    "dev": "small",
    "staging": "medium",
    "prod": "medium",
}

VALID_SIZES = ("small", "medium", "large")

VALID_ENVIRONMENTS = ("dev", "staging", "prod")

# Conditional features by environment
CONDITIONAL_FEATURES = {
    "enable_diagnostics": {"dev": False, "staging": True, "prod": True},
    "enable_access_review": {"dev": False, "staging": False, "prod": True},
}

# Validation pattern for state key path components
_SAFE_PATH_COMPONENT = re.compile(r"^[a-zA-Z0-9_-]+$")


def _sanitize_path_component(value: str, field_name: str) -> str:
    """Validate a value is safe for use in file/state paths."""
    if not _SAFE_PATH_COMPONENT.match(value):
        raise ValueError(
            f"Invalid {field_name}: {value!r}. "
            "Only alphanumeric, hyphens, and underscores are allowed."
        )
    return value


def normalize_optional(optional_raw: list | dict) -> dict[str, Any]:
    """Normalize optional config from YAML (list or dict format)."""
    if isinstance(optional_raw, list):
        result: dict[str, Any] = {}
        for item in optional_raw:
            if isinstance(item, dict):
                result.update(item)
        return result
    return optional_raw if isinstance(optional_raw, dict) else {}


class PatternResolver:
    """Resolves pattern requests to Terraform variable sets."""

    def __init__(self, patterns: dict[str, dict[str, Any]]):
        self.patterns = patterns

    def validate_config(
        self,
        pattern_name: str,
        environment: str,
        config: dict[str, Any],
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Validate a pattern configuration.

        Returns:
            {"valid": bool, "errors": list[str], "warnings": list[str]}
        """
        errors: list[str] = []
        warnings: list[str] = []

        if pattern_name not in self.patterns:
            errors.append(
                f"Unknown pattern: {pattern_name}. "
                f"Available: {list(self.patterns.keys())}"
            )
            return {"valid": False, "errors": errors, "warnings": warnings}

        if environment not in VALID_ENVIRONMENTS:
            errors.append(
                f"Invalid environment: {environment}. Must be one of: {', '.join(VALID_ENVIRONMENTS)}"
            )

        # Validate size if provided
        size = config.get("size")
        if size and size not in VALID_SIZES:
            errors.append(
                f"Invalid size: {size}. Must be one of: {', '.join(VALID_SIZES)}"
            )

        pattern = self.patterns[pattern_name]
        required_config = pattern.get("config", {}).get("required", [])
        for field in required_config:
            if field not in config:
                errors.append(f"Missing required config field: {field}")

        if metadata is None:
            errors.append("Metadata is required")
        else:
            for field in ("project", "environment", "business_unit", "owners"):
                if field not in metadata:
                    errors.append(f"Missing required metadata field: {field}")

        return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}

    def resolve(
        self,
        pattern_name: str,
        environment: str,
        config: dict[str, Any],
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        """Resolve a pattern request to Terraform variables.

        Args:
            pattern_name: Name of the pattern (e.g., "key_vault")
            environment: Target environment (dev/staging/prod)
            config: User-provided config (name, size, etc.)
            metadata: Project metadata (project, business_unit, owners, location)

        Returns:
            Dict of Terraform variable values ready for tfvars.json
        """
        validation = self.validate_config(pattern_name, environment, config, metadata)
        if not validation["valid"]:
            raise ValueError(f"Invalid config: {validation['errors']}")

        pattern = self.patterns[pattern_name]
        size = config.get("size", DEFAULT_SIZES.get(environment, "small"))

        # Resolve sizing
        sizing = self._resolve_sizing(pattern, size, environment)

        # Build tfvars
        tfvars: dict[str, Any] = {
            "project": metadata["project"],
            "environment": environment,
            "business_unit": metadata.get("business_unit", ""),
            "owners": metadata.get("owners", []),
            "location": metadata.get("location", "eastus"),
            "name": config.get("name", metadata["project"]),
        }

        # Merge sizing values
        tfvars.update(sizing)

        # Apply optional config with defaults
        optional_raw = pattern.get("config", {}).get("optional", {})
        optional_config = normalize_optional(optional_raw)

        for key, spec in optional_config.items():
            if key in config:
                tfvars[key] = config[key]
            elif isinstance(spec, dict) and "default" in spec:
                tfvars[key] = spec["default"]

        # Apply conditionals
        for feature, env_values in CONDITIONAL_FEATURES.items():
            if feature not in tfvars:
                tfvars[feature] = env_values.get(environment, False)

        logger.info(
            "Resolved %s/%s for project %s",
            pattern_name, environment, metadata.get("project"),
        )
        return tfvars

    def estimate_cost(
        self, pattern_name: str, environment: str, size: str | None = None
    ) -> dict[str, Any]:
        """Get estimated monthly cost for a pattern configuration."""
        if pattern_name not in self.patterns:
            return {"error": f"Unknown pattern: {pattern_name}"}

        if environment not in VALID_ENVIRONMENTS:
            return {"error": f"Invalid environment: {environment}"}

        if size and size not in VALID_SIZES:
            return {"error": f"Invalid size: {size}"}

        pattern = self.patterns[pattern_name]
        resolved_size = size or DEFAULT_SIZES.get(environment, "small")
        costs = pattern.get("estimated_costs", {})

        if resolved_size in costs and environment in costs[resolved_size]:
            return {
                "pattern": pattern_name,
                "size": resolved_size,
                "environment": environment,
                "estimated_monthly_cost_usd": costs[resolved_size][environment],
            }

        return {"error": "Cost estimate not available for this configuration"}

    def compute_state_key(
        self,
        pattern_name: str,
        environment: str,
        config: dict[str, Any],
        metadata: dict[str, Any],
    ) -> str:
        """Compute the Terraform state key for a deployment."""
        business_unit = _sanitize_path_component(
            metadata.get("business_unit") or "default", "business_unit"
        )
        project = _sanitize_path_component(
            metadata.get("project", "unknown"), "project"
        )
        name = _sanitize_path_component(
            config.get("name", pattern_name), "name"
        )
        _sanitize_path_component(pattern_name, "pattern_name")
        _sanitize_path_component(environment, "environment")

        return f"{business_unit}/{environment}/{project}/{pattern_name}-{name}/terraform.tfstate"

    def _resolve_sizing(
        self, pattern: dict[str, Any], size: str, environment: str
    ) -> dict[str, Any]:
        """Look up sizing values from pattern definition."""
        sizing = pattern.get("sizing", {})
        if size in sizing and environment in sizing[size]:
            return sizing[size][environment].copy()
        return {}
