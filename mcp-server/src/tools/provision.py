"""Provision and destroy tools (prototype mode - triggers GitHub Actions)."""

import base64
import json
import logging
from typing import Any

from ..github.client import GitHubClient
from ..patterns.loader import load_patterns
from ..patterns.resolver import PatternResolver

logger = logging.getLogger(__name__)

WORKFLOW_FILE = "prototype-provision.yaml"

# Module-level client for connection reuse
_github_client: GitHubClient | None = None


def _get_github_client() -> GitHubClient:
    global _github_client
    if _github_client is None:
        _github_client = GitHubClient()
    return _github_client


def _get_resolver() -> PatternResolver:
    return PatternResolver(load_patterns())


async def provision(
    pattern_name: str,
    environment: str,
    config: dict[str, Any],
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    location: str = "eastus",
    size: str | None = None,
) -> dict[str, Any]:
    """Provision infrastructure by triggering a GitHub Actions workflow.

    This is the prototype flow: MCP server triggers workflow_dispatch on
    infrastructure-automation repo, which runs terraform apply.
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
    tfvars_json = json.dumps(tfvars)
    tfvars_b64 = base64.b64encode(tfvars_json.encode()).decode()

    state_key = resolver.compute_state_key(
        pattern_name, environment, resolved_config, metadata
    )

    # Trigger workflow
    gh = _get_github_client()
    result = await gh.trigger_workflow(
        WORKFLOW_FILE,
        inputs={
            "pattern": pattern_name,
            "environment": environment,
            "tfvars_json": tfvars_b64,
            "action": "create",
            "state_key": state_key,
        },
    )

    logger.info("Triggered provision: %s/%s for %s", pattern_name, environment, project)
    return {
        "status": "triggered",
        "action": "create",
        "pattern": pattern_name,
        "environment": environment,
        "state_key": state_key,
        "workflow": result,
    }


async def destroy(
    pattern_name: str,
    environment: str,
    config: dict[str, Any],
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    location: str = "eastus",
) -> dict[str, Any]:
    """Destroy infrastructure by triggering a GitHub Actions workflow."""
    resolver = _get_resolver()

    metadata = {
        "project": project,
        "environment": environment,
        "business_unit": business_unit,
        "owners": owners or [],
        "location": location,
    }

    resolved_config = dict(config)

    # Validate
    validation = resolver.validate_config(pattern_name, environment, resolved_config, metadata)
    if not validation["valid"]:
        return {"error": "Validation failed", "details": validation["errors"]}

    tfvars = resolver.resolve(pattern_name, environment, resolved_config, metadata)
    tfvars_json = json.dumps(tfvars)
    tfvars_b64 = base64.b64encode(tfvars_json.encode()).decode()

    state_key = resolver.compute_state_key(
        pattern_name, environment, resolved_config, metadata
    )

    # Trigger destroy workflow
    gh = _get_github_client()
    result = await gh.trigger_workflow(
        WORKFLOW_FILE,
        inputs={
            "pattern": pattern_name,
            "environment": environment,
            "tfvars_json": tfvars_b64,
            "action": "destroy",
            "state_key": state_key,
        },
    )

    logger.info("Triggered destroy: %s/%s for %s", pattern_name, environment, project)
    return {
        "status": "triggered",
        "action": "destroy",
        "pattern": pattern_name,
        "environment": environment,
        "state_key": state_key,
        "workflow": result,
    }
