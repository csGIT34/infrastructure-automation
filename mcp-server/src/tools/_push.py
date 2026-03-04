"""Shared helper for pushing tfvars to app-infrastructure repo."""

import json
import logging
from datetime import datetime, timezone
from typing import Any

from ..github.client import GitHubClient
from ..patterns.loader import load_patterns
from ..patterns.resolver import PatternResolver

logger = logging.getLogger(__name__)

# Module-level singletons for connection reuse
_github_client: GitHubClient | None = None
_resolver: PatternResolver | None = None


def _get_github_client() -> GitHubClient:
    global _github_client
    if _github_client is None:
        _github_client = GitHubClient()
    return _github_client


def _get_resolver() -> PatternResolver:
    global _resolver
    if _resolver is None:
        _resolver = PatternResolver(load_patterns())
    return _resolver


async def push_pattern(
    pattern_name: str,
    environment: str,
    config: dict[str, Any],
    metadata: dict[str, Any],
    commit_prefix: str = "deploy",
) -> dict[str, Any]:
    """Validate, resolve, and push a pattern's tfvars to app-infrastructure.

    Args:
        pattern_name: Pattern to deploy
        environment: Target environment
        config: User-provided config (name, size, etc.)
        metadata: Project metadata (project, business_unit, owners, etc.)
        commit_prefix: Prefix for the commit message

    Returns:
        Dict with push status, folder path, state key, and commit info
    """
    resolver = _get_resolver()

    # Validate and resolve
    validation = resolver.validate_config(pattern_name, environment, config, metadata)
    if not validation["valid"]:
        return {"error": "Validation failed", "details": validation["errors"]}

    tfvars = resolver.resolve(pattern_name, environment, config, metadata)
    state_key = resolver.compute_state_key(
        pattern_name, environment, config, metadata
    )

    tfvars_json = json.dumps(tfvars, indent=2)

    # Generate backend.hcl (only the state key; storage account details
    # are provided by the CI workflow via -backend-config CLI flags)
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    backend_hcl = f"""# Auto-generated backend configuration
# pushed: {timestamp}
key = "{state_key}"
"""

    application_id = metadata.get("application_id", "unknown")
    application_name = metadata.get("application_name", "unknown")

    # Folder-based path on main: {app_id}/{app_name}/{environment}
    folder_path = f"{application_id}/{application_name}/{environment}"
    commit_message = (
        f"{commit_prefix}: {pattern_name} for "
        f"{application_id}/{application_name}/{environment}"
    )

    gh = _get_github_client()
    result = await gh.push_tfvars_to_main(
        folder_path=folder_path,
        pattern_name=pattern_name,
        tfvars_json=tfvars_json,
        backend_hcl=backend_hcl,
        commit_message=commit_message,
    )

    logger.info(
        "Pushed tfvars (%s): %s/%s for %s/%s",
        commit_prefix, pattern_name, environment,
        application_id, application_name,
    )
    return {
        "status": "pushed",
        "folder_path": f"{folder_path}/{pattern_name}",
        "pattern": pattern_name,
        "environment": environment,
        "state_key": state_key,
        "commit": result,
    }
