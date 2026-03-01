"""Pattern discovery and information tools."""

import logging
from typing import Any

from ..patterns.loader import load_patterns
from ..patterns.resolver import PatternResolver, normalize_optional

logger = logging.getLogger(__name__)


def _get_resolver() -> PatternResolver:
    patterns = load_patterns()
    return PatternResolver(patterns)


def list_patterns(category: str | None = None) -> list[dict[str, Any]]:
    """List available infrastructure patterns.

    Args:
        category: Optional filter by category ("single-resource" or "composite")

    Returns:
        List of pattern summaries
    """
    patterns = load_patterns()
    results = []

    for name, pattern in patterns.items():
        pat_category = pattern.get("category", "unknown")
        if category and pat_category != category:
            continue

        results.append({
            "name": name,
            "description": pattern.get("description", "").strip().split("\n")[0],
            "category": pat_category,
            "components": pattern.get("components", []),
            "use_cases": pattern.get("use_cases", []),
        })

    return results


def get_pattern_details(pattern_name: str) -> dict[str, Any]:
    """Get full details for a specific pattern.

    Args:
        pattern_name: Pattern name (e.g., "key_vault")

    Returns:
        Full pattern details including sizing, config options, and costs
    """
    patterns = load_patterns()
    if pattern_name not in patterns:
        return {"error": f"Unknown pattern: {pattern_name}. Available: {list(patterns.keys())}"}

    pattern = patterns[pattern_name]
    optional_raw = pattern.get("config", {}).get("optional", {})
    optional_config = normalize_optional(optional_raw)

    return {
        "name": pattern["name"],
        "description": pattern.get("description", "").strip(),
        "category": pattern.get("category", "unknown"),
        "components": pattern.get("components", []),
        "use_cases": pattern.get("use_cases", []),
        "required_config": pattern.get("config", {}).get("required", []),
        "optional_config": optional_config,
        "sizing": pattern.get("sizing", {}),
        "estimated_costs": pattern.get("estimated_costs", {}),
    }


def estimate_cost(
    pattern_name: str, environment: str, size: str | None = None
) -> dict[str, Any]:
    """Estimate monthly cost for a pattern configuration.

    Args:
        pattern_name: Pattern name
        environment: Target environment (dev/staging/prod)
        size: T-shirt size (small/medium/large). Defaults based on environment.

    Returns:
        Cost estimate in USD/month
    """
    resolver = _get_resolver()
    return resolver.estimate_cost(pattern_name, environment, size)
