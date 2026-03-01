"""Infrastructure Self-Service MCP Server.

Provides tools for discovering, validating, and provisioning
infrastructure patterns via Claude Code.
"""

import json
import logging
import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .patterns.loader import load_patterns
from .patterns.resolver import PatternResolver
from .tools import patterns as pattern_tools
from .tools import provision as provision_tools
from .tools import status as status_tools
from .tools import tfvars as tfvars_tools

# Configure logging
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

transport = os.environ.get("MCP_TRANSPORT", "streamable-http")
host = os.environ.get("MCP_HOST", "127.0.0.1")
port = int(os.environ.get("MCP_PORT", "8000"))

# --- Entra ID Authentication (enabled when env vars are set) ---

_tenant_id = os.environ.get("AZURE_TENANT_ID")
_entra_client_id = os.environ.get("MCP_ENTRA_CLIENT_ID")
_server_url = os.environ.get("MCP_SERVER_URL")

if all([_tenant_id, _entra_client_id, _server_url]):
    from mcp.server.auth.settings import AuthSettings, ClientRegistrationOptions
    from pydantic import AnyHttpUrl

    from .auth.provider import EntraOAuthProvider

    _auth_provider = EntraOAuthProvider(_tenant_id, _entra_client_id, _server_url)
    _auth_settings = AuthSettings(
        issuer_url=AnyHttpUrl(_server_url),
        resource_server_url=AnyHttpUrl(f"{_server_url.rstrip('/')}/mcp"),
        client_registration_options=ClientRegistrationOptions(
            enabled=True,
            valid_scopes=["access"],
            default_scopes=["access"],
        ),
    )
    logger.info("Entra ID authentication enabled")
else:
    _auth_provider = None
    _auth_settings = None

mcp = FastMCP(
    "Infrastructure Self-Service",
    instructions="Provision and manage Azure infrastructure through patterns",
    host=host,
    port=port,
    auth_server_provider=_auth_provider,
    auth=_auth_settings,
)

# Register Entra ID callback route when auth is enabled
if _auth_provider:

    @mcp.custom_route("/auth/callback", methods=["GET"])
    async def auth_callback(request):
        return await _auth_provider.handle_callback(request)

# Shared resolver instance (patterns are cached after first load)
_resolver: PatternResolver | None = None


def _get_resolver() -> PatternResolver:
    """Get or create the shared PatternResolver instance."""
    global _resolver
    if _resolver is None:
        _resolver = PatternResolver(load_patterns())
    return _resolver


# --- Pattern Discovery Tools ---


@mcp.tool()
def list_patterns(category: str | None = None) -> str:
    """List available infrastructure patterns.

    Args:
        category: Optional filter - "single-resource" or "composite"
    """
    results = pattern_tools.list_patterns(category)
    return json.dumps(results, indent=2)


@mcp.tool()
def get_pattern_details(pattern_name: str) -> str:
    """Get full details for a pattern including sizing, config options, and costs.

    Args:
        pattern_name: Pattern name (key_vault, storage_account, postgresql, container_app, web_backend)
    """
    details = pattern_tools.get_pattern_details(pattern_name)
    return json.dumps(details, indent=2)


@mcp.tool()
def estimate_cost(
    pattern_name: str, environment: str, size: str | None = None
) -> str:
    """Estimate monthly cost for a pattern configuration.

    Args:
        pattern_name: Pattern name
        environment: Target environment (dev, staging, prod)
        size: T-shirt size (small, medium, large). Defaults based on environment.
    """
    result = pattern_tools.estimate_cost(pattern_name, environment, size)
    return json.dumps(result, indent=2)


@mcp.tool()
def validate_config(
    pattern_name: str,
    environment: str,
    name: str,
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    size: str | None = None,
) -> str:
    """Validate a pattern configuration before provisioning.

    Args:
        pattern_name: Pattern name
        environment: Target environment (dev, staging, prod)
        name: Resource name
        project: Project name
        business_unit: Business unit
        owners: List of owner emails
        size: T-shirt size override
    """
    resolver = _get_resolver()

    config: dict[str, Any] = {"name": name}
    if size:
        config["size"] = size

    metadata = {
        "project": project,
        "environment": environment,
        "business_unit": business_unit,
        "owners": owners or [],
    }

    validation = resolver.validate_config(pattern_name, environment, config, metadata)

    # Also show what would be resolved
    if validation["valid"]:
        tfvars = resolver.resolve(pattern_name, environment, config, metadata)
        cost = resolver.estimate_cost(pattern_name, environment, size)
        validation["resolved_tfvars"] = tfvars
        validation["cost_estimate"] = cost

    return json.dumps(validation, indent=2)


# --- Provisioning Tools (Prototype Mode) ---


@mcp.tool()
async def provision(
    pattern_name: str,
    environment: str,
    name: str,
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    location: str = "eastus",
    size: str | None = None,
) -> str:
    """Provision infrastructure (prototype mode - triggers GitHub Actions).

    Creates Azure resources by triggering a workflow_dispatch on the
    infrastructure-automation repository.

    Args:
        pattern_name: Pattern to provision (key_vault, storage_account, postgresql, container_app, web_backend)
        environment: Target environment (dev, staging, prod)
        name: Resource name
        project: Project name
        business_unit: Business unit for tagging
        owners: List of owner email addresses
        location: Azure region (default: eastus)
        size: T-shirt size (small, medium, large)
    """
    result = await provision_tools.provision(
        pattern_name=pattern_name,
        environment=environment,
        config={"name": name},
        project=project,
        business_unit=business_unit,
        owners=owners,
        location=location,
        size=size,
    )
    return json.dumps(result, indent=2)


@mcp.tool()
async def destroy(
    pattern_name: str,
    environment: str,
    name: str,
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    location: str = "eastus",
) -> str:
    """Destroy infrastructure (prototype mode - triggers GitHub Actions).

    Tears down Azure resources by triggering a destroy workflow.

    Args:
        pattern_name: Pattern to destroy
        environment: Target environment
        name: Resource name
        project: Project name
        business_unit: Business unit
        owners: Owner emails
        location: Azure region
    """
    result = await provision_tools.destroy(
        pattern_name=pattern_name,
        environment=environment,
        config={"name": name},
        project=project,
        business_unit=business_unit,
        owners=owners,
        location=location,
    )
    return json.dumps(result, indent=2)


# --- Production Mode (GitOps) ---


@mcp.tool()
async def push_tfvars(
    pattern_name: str,
    environment: str,
    name: str,
    project: str,
    business_unit: str = "",
    owners: list[str] | None = None,
    location: str = "eastus",
    size: str | None = None,
) -> str:
    """Push tfvars to app-infrastructure repo for GitOps deployment (production mode).

    Creates a branch {project}/{environment} and pushes terraform.tfvars.json
    and backend.hcl. The push triggers terraform apply in the app-infrastructure repo.

    Args:
        pattern_name: Pattern to deploy
        environment: Target environment (dev, staging, prod)
        name: Resource name
        project: Project name
        business_unit: Business unit
        owners: Owner emails
        location: Azure region
        size: T-shirt size
    """
    result = await tfvars_tools.push_tfvars(
        pattern_name=pattern_name,
        environment=environment,
        config={"name": name},
        project=project,
        business_unit=business_unit,
        owners=owners,
        location=location,
        size=size,
    )
    return json.dumps(result, indent=2)


# --- Status Tools ---


@mcp.tool()
async def check_status(run_id: int) -> str:
    """Check the status of a provisioning workflow run.

    Args:
        run_id: GitHub Actions workflow run ID
    """
    result = await status_tools.check_status(run_id)
    return json.dumps(result, indent=2)


@mcp.tool()
async def list_deployments(
    status: str | None = None, limit: int = 10
) -> str:
    """List recent infrastructure deployments.

    Args:
        status: Filter by status (queued, in_progress, completed)
        limit: Max results (default 10, max 100)
    """
    results = await status_tools.list_deployments(status=status, limit=limit)
    return json.dumps(results, indent=2)


def main():
    """Run the MCP server."""
    # Eagerly load patterns at startup
    patterns = load_patterns()
    logger.info("Server starting with %d patterns loaded", len(patterns))

    mcp.run(transport=transport)


if __name__ == "__main__":
    main()
