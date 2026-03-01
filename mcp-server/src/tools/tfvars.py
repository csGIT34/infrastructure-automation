"""Production mode: push tfvars to app-infrastructure repo."""

import json
import logging
from typing import Any

from ..github.client import GitHubClient
from ..patterns.loader import load_patterns
from ..patterns.resolver import PatternResolver

logger = logging.getLogger(__name__)

# Module-level client for connection reuse
_github_client: GitHubClient | None = None


def _get_github_client() -> GitHubClient:
    global _github_client
    if _github_client is None:
        _github_client = GitHubClient()
    return _github_client


def _get_resolver() -> PatternResolver:
    return PatternResolver(load_patterns())


async def push_tfvars(
    pattern_name: str,
    environment: str,
    config: dict[str, Any],
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    location: str = "eastus",
    size: str | None = None,
) -> dict[str, Any]:
    """Push Terraform tfvars to app-infrastructure repo for GitOps deployment.

    Creates/updates a branch {project}/{environment} with the pattern's
    terraform.tfvars.json and backend.hcl. Push triggers the terraform-apply
    workflow in app-infrastructure.
    """
    resolver = _get_resolver()

    metadata = {
        "project": project,
        "environment": environment,
        "business_unit": business_unit,
        "owners": owners or [],
        "location": location,
    }

    # Create a copy to avoid mutating the caller's dict
    resolved_config = dict(config)
    if size:
        resolved_config["size"] = size

    # Validate and resolve
    validation = resolver.validate_config(pattern_name, environment, resolved_config, metadata)
    if not validation["valid"]:
        return {"error": "Validation failed", "details": validation["errors"]}

    tfvars = resolver.resolve(pattern_name, environment, resolved_config, metadata)
    state_key = resolver.compute_state_key(
        pattern_name, environment, resolved_config, metadata
    )

    tfvars_json = json.dumps(tfvars, indent=2)

    # Generate backend.hcl (only the state key; storage account details
    # are provided by the CI workflow via -backend-config CLI flags)
    backend_hcl = f"""# Auto-generated backend configuration
key = "{state_key}"
"""

    branch = f"{project}/{environment}"
    commit_message = f"deploy: {pattern_name} for {project}/{environment}"

    gh = _get_github_client()
    result = await gh.push_tfvars(
        branch=branch,
        pattern_name=pattern_name,
        tfvars_json=tfvars_json,
        backend_hcl=backend_hcl,
        commit_message=commit_message,
    )

    logger.info("Pushed tfvars: %s/%s for %s", pattern_name, environment, project)
    return {
        "status": "pushed",
        "branch": branch,
        "pattern": pattern_name,
        "environment": environment,
        "state_key": state_key,
        "commit": result,
    }
