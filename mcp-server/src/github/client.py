"""GitHub API client for triggering workflows and pushing files."""

import logging
import os
import re
import time
from typing import Any

import httpx
import jwt

logger = logging.getLogger(__name__)

# Validation patterns for inputs used in URL construction
REPO_PATTERN = re.compile(r"^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$")
BRANCH_PATTERN = re.compile(r"^[a-zA-Z0-9/_.-]+$")
WORKFLOW_PATTERN = re.compile(r"^[a-zA-Z0-9_.-]+\.ya?ml$")
PATTERN_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9_-]+$")
STATE_KEY_PATTERN = re.compile(r"^[a-zA-Z0-9/_.-]+$")


def _validate(value: str, pattern: re.Pattern, name: str) -> str:
    """Validate a value against a regex pattern, raising ValueError if invalid."""
    if not pattern.match(value):
        raise ValueError(f"Invalid {name}: {value!r}")
    return value


class GitHubClient:
    """GitHub API client using GitHub App authentication."""

    def __init__(
        self,
        app_id: str | None = None,
        private_key: str | None = None,
        infra_repo: str | None = None,
        app_infra_repo: str | None = None,
    ):
        self.app_id = app_id or os.environ.get("INFRA_APP_ID", "")
        self.private_key = private_key or os.environ.get("INFRA_APP_PRIVATE_KEY", "")
        self.infra_repo = infra_repo or os.environ.get("INFRA_REPO", "")
        self.app_infra_repo = app_infra_repo or os.environ.get("APP_INFRA_REPO", "")
        self.base_url = "https://api.github.com"
        self._installation_token: str | None = None
        self._token_expires: float = 0
        self._http_client: httpx.AsyncClient | None = None

        # Validate credentials at init
        if not self.app_id or not self.private_key:
            logger.warning(
                "GitHub App credentials not configured. "
                "Set INFRA_APP_ID and INFRA_APP_PRIVATE_KEY environment variables."
            )

        # Validate repo format
        if self.infra_repo and not REPO_PATTERN.match(self.infra_repo):
            raise ValueError(
                f"INFRA_REPO must be in 'owner/repo' format, got: {self.infra_repo!r}"
            )
        if self.app_infra_repo and not REPO_PATTERN.match(self.app_infra_repo):
            raise ValueError(
                f"APP_INFRA_REPO must be in 'owner/repo' format, got: {self.app_infra_repo!r}"
            )

    async def _get_client(self) -> httpx.AsyncClient:
        """Get or create a persistent HTTP client."""
        if self._http_client is None or self._http_client.is_closed:
            self._http_client = httpx.AsyncClient(timeout=30.0)
        return self._http_client

    def _generate_jwt(self) -> str:
        """Generate a JWT for GitHub App authentication."""
        if not self.app_id or not self.private_key:
            raise RuntimeError(
                "GitHub App credentials not configured. "
                "Set INFRA_APP_ID and INFRA_APP_PRIVATE_KEY."
            )
        now = int(time.time())
        payload = {
            "iat": now - 60,
            "exp": now + (10 * 60),
            "iss": self.app_id,
        }
        return jwt.encode(payload, self.private_key, algorithm="RS256")

    async def _get_installation_token(self) -> str:
        """Get or refresh an installation access token."""
        if self._installation_token and time.time() < self._token_expires:
            return self._installation_token

        jwt_token = self._generate_jwt()
        client = await self._get_client()

        # Get installations
        resp = await client.get(
            f"{self.base_url}/app/installations",
            headers={
                "Authorization": f"Bearer {jwt_token}",
                "Accept": "application/vnd.github+json",
            },
        )
        resp.raise_for_status()
        installations = resp.json()

        if not installations:
            raise RuntimeError("No GitHub App installations found")

        # Find installation matching our target repos
        installation_id = installations[0]["id"]
        for inst in installations:
            account = inst.get("account", {}).get("login", "")
            for repo in (self.infra_repo, self.app_infra_repo):
                if repo and repo.startswith(f"{account}/"):
                    installation_id = inst["id"]
                    break

        logger.info("Using GitHub App installation %s", installation_id)

        # Create installation token
        resp = await client.post(
            f"{self.base_url}/app/installations/{installation_id}/access_tokens",
            headers={
                "Authorization": f"Bearer {jwt_token}",
                "Accept": "application/vnd.github+json",
            },
        )
        resp.raise_for_status()
        token_data = resp.json()

        self._installation_token = token_data["token"]
        self._token_expires = time.time() + 3500  # ~58 min

        return self._installation_token  # type: ignore[return-value]

    async def _headers(self) -> dict[str, str]:
        """Get authenticated headers."""
        token = await self._get_installation_token()
        return {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
        }

    async def trigger_workflow(
        self,
        workflow_file: str,
        ref: str = "main",
        inputs: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """Trigger a workflow_dispatch event on the infrastructure-automation repo."""
        if not self.infra_repo:
            raise RuntimeError("INFRA_REPO not configured (must be 'owner/repo' format)")

        _validate(workflow_file, WORKFLOW_PATTERN, "workflow_file")
        headers = await self._headers()
        url = f"{self.base_url}/repos/{self.infra_repo}/actions/workflows/{workflow_file}/dispatches"

        payload: dict[str, Any] = {"ref": ref}
        if inputs:
            payload["inputs"] = inputs

        client = await self._get_client()
        resp = await client.post(url, headers=headers, json=payload)
        resp.raise_for_status()

        logger.info("Triggered workflow %s on %s", workflow_file, self.infra_repo)
        return {"status": "triggered", "workflow": workflow_file, "inputs": inputs}

    async def push_tfvars(
        self,
        branch: str,
        pattern_name: str,
        tfvars_json: str,
        backend_hcl: str,
        commit_message: str,
    ) -> dict[str, Any]:
        """Push tfvars and backend config to a branch in app-infrastructure repo."""
        if not self.app_infra_repo:
            raise RuntimeError("APP_INFRA_REPO not configured (must be 'owner/repo' format)")

        _validate(branch, BRANCH_PATTERN, "branch")
        _validate(pattern_name, PATTERN_NAME_PATTERN, "pattern_name")

        headers = await self._headers()
        client = await self._get_client()

        # Ensure branch exists (create from main if not)
        await self._ensure_branch(client, headers, branch)

        # Get current tree SHA for the branch
        ref_resp = await client.get(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/ref/heads/{branch}",
            headers=headers,
        )
        ref_resp.raise_for_status()
        current_sha = ref_resp.json()["object"]["sha"]

        # Create blobs for both files
        tfvars_blob = await self._create_blob(client, headers, tfvars_json)
        backend_blob = await self._create_blob(client, headers, backend_hcl)

        # Create tree with both files
        tree_resp = await client.post(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/trees",
            headers=headers,
            json={
                "base_tree": current_sha,
                "tree": [
                    {
                        "path": f"{pattern_name}/terraform.tfvars.json",
                        "mode": "100644",
                        "type": "blob",
                        "sha": tfvars_blob,
                    },
                    {
                        "path": f"{pattern_name}/backend.hcl",
                        "mode": "100644",
                        "type": "blob",
                        "sha": backend_blob,
                    },
                ],
            },
        )
        tree_resp.raise_for_status()
        tree_sha = tree_resp.json()["sha"]

        # Create commit
        commit_resp = await client.post(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/commits",
            headers=headers,
            json={
                "message": commit_message,
                "tree": tree_sha,
                "parents": [current_sha],
            },
        )
        commit_resp.raise_for_status()
        commit_sha = commit_resp.json()["sha"]

        # Update branch ref
        update_resp = await client.patch(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/refs/heads/{branch}",
            headers=headers,
            json={"sha": commit_sha},
        )
        update_resp.raise_for_status()

        logger.info("Pushed tfvars to %s branch %s", self.app_infra_repo, branch)
        return {
            "branch": branch,
            "commit_sha": commit_sha,
            "files": [
                f"{pattern_name}/terraform.tfvars.json",
                f"{pattern_name}/backend.hcl",
            ],
        }

    async def get_workflow_runs(
        self,
        workflow_file: str | None = None,
        status: str | None = None,
        per_page: int = 10,
    ) -> list[dict[str, Any]]:
        """List recent workflow runs."""
        if not self.infra_repo:
            raise RuntimeError("INFRA_REPO not configured")

        headers = await self._headers()
        per_page = min(per_page, 100)
        params: dict[str, Any] = {"per_page": per_page}
        if status:
            if status not in ("queued", "in_progress", "completed", "waiting", "requested"):
                raise ValueError(f"Invalid workflow status filter: {status}")
            params["status"] = status

        if workflow_file:
            _validate(workflow_file, WORKFLOW_PATTERN, "workflow_file")
            url = f"{self.base_url}/repos/{self.infra_repo}/actions/workflows/{workflow_file}/runs"
        else:
            url = f"{self.base_url}/repos/{self.infra_repo}/actions/runs"

        client = await self._get_client()
        resp = await client.get(url, headers=headers, params=params)
        resp.raise_for_status()
        data = resp.json()

        return [
            {
                "id": run["id"],
                "name": run.get("name", ""),
                "status": run["status"],
                "conclusion": run.get("conclusion"),
                "created_at": run["created_at"],
                "html_url": run["html_url"],
            }
            for run in data.get("workflow_runs", [])
        ]

    async def get_workflow_run(self, run_id: int) -> dict[str, Any]:
        """Get details for a specific workflow run."""
        if not isinstance(run_id, int) or run_id <= 0:
            raise ValueError(f"run_id must be a positive integer, got: {run_id!r}")
        if not self.infra_repo:
            raise RuntimeError("INFRA_REPO not configured")

        headers = await self._headers()
        client = await self._get_client()
        resp = await client.get(
            f"{self.base_url}/repos/{self.infra_repo}/actions/runs/{run_id}",
            headers=headers,
        )
        resp.raise_for_status()
        run = resp.json()

        return {
            "id": run["id"],
            "name": run.get("name", ""),
            "status": run["status"],
            "conclusion": run.get("conclusion"),
            "created_at": run["created_at"],
            "updated_at": run["updated_at"],
            "html_url": run["html_url"],
        }

    async def _ensure_branch(
        self, client: httpx.AsyncClient, headers: dict, branch: str
    ) -> None:
        """Ensure a branch exists in app-infrastructure, creating from main if needed."""
        resp = await client.get(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/ref/heads/{branch}",
            headers=headers,
        )
        if resp.status_code == 200:
            return

        # Get main branch SHA
        main_resp = await client.get(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/ref/heads/main",
            headers=headers,
        )
        main_resp.raise_for_status()
        main_sha = main_resp.json()["object"]["sha"]

        # Create branch
        create_resp = await client.post(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/refs",
            headers=headers,
            json={"ref": f"refs/heads/{branch}", "sha": main_sha},
        )
        create_resp.raise_for_status()
        logger.info("Created branch %s from main", branch)

    async def _create_blob(
        self, client: httpx.AsyncClient, headers: dict, content: str
    ) -> str:
        """Create a blob in the app-infrastructure repo."""
        resp = await client.post(
            f"{self.base_url}/repos/{self.app_infra_repo}/git/blobs",
            headers=headers,
            json={"content": content, "encoding": "utf-8"},
        )
        resp.raise_for_status()
        return resp.json()["sha"]

    async def close(self) -> None:
        """Close the HTTP client."""
        if self._http_client and not self._http_client.is_closed:
            await self._http_client.aclose()
