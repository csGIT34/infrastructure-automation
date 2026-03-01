"""Status and deployment listing tools."""

import logging
from typing import Any

from ..github.client import GitHubClient

logger = logging.getLogger(__name__)

# Module-level client for connection reuse
_github_client: GitHubClient | None = None


def _get_github_client() -> GitHubClient:
    global _github_client
    if _github_client is None:
        _github_client = GitHubClient()
    return _github_client


async def check_status(run_id: int) -> dict[str, Any]:
    """Check the status of a GitHub Actions workflow run.

    Args:
        run_id: The workflow run ID returned from provision/destroy

    Returns:
        Dict with run status, conclusion, and URL
    """
    if not isinstance(run_id, int) or run_id <= 0:
        raise ValueError(f"run_id must be a positive integer, got: {run_id!r}")
    gh = _get_github_client()
    return await gh.get_workflow_run(run_id)


async def list_deployments(
    status: str | None = None,
    limit: int = 10,
) -> list[dict[str, Any]]:
    """List recent infrastructure deployments (workflow runs).

    Args:
        status: Filter by status (queued, in_progress, completed)
        limit: Max results to return (capped at 100)

    Returns:
        List of deployment summaries
    """
    limit = min(max(limit, 1), 100)
    gh = _get_github_client()
    return await gh.get_workflow_runs(
        workflow_file="prototype-provision.yaml",
        status=status,
        per_page=limit,
    )
