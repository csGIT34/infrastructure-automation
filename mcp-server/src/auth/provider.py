"""Entra ID OAuth provider for MCP server authentication.

Implements OAuthAuthorizationServerProvider to proxy authentication
to Entra ID using PKCE (no client secrets). The MCP server acts as
an OAuth Authorization Server that delegates identity verification
to Entra ID, then issues its own JWT access tokens.

Flow:
    Claude Code -> MCP /authorize -> Entra ID login -> /auth/callback -> Claude Code
"""

import base64
import hashlib
import logging
import secrets
import time
from urllib.parse import urlencode

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from pydantic import AnyUrl
from starlette.requests import Request
from starlette.responses import RedirectResponse

from mcp.server.auth.provider import (
    AccessToken,
    AuthorizationCode,
    AuthorizationParams,
    RefreshToken,
)
from mcp.shared.auth import OAuthClientInformationFull, OAuthToken

logger = logging.getLogger(__name__)


class EntraOAuthProvider:
    """OAuth provider that delegates authentication to Entra ID with PKCE.

    Implements the OAuthAuthorizationServerProvider protocol so FastMCP
    handles /authorize, /token, /register endpoints automatically. This
    provider generates its own PKCE pair for the Entra ID exchange and
    stores a separate PKCE challenge from Claude Code for the MCP token
    exchange.

    All state is in-memory (acceptable for single-instance dev tool).
    """

    def __init__(self, tenant_id: str, entra_client_id: str, server_url: str):
        self.tenant_id = tenant_id
        self.entra_client_id = entra_client_id
        self.server_url = server_url.rstrip("/")
        self.callback_url = f"{self.server_url}/auth/callback"

        # Entra ID endpoints
        base = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0"
        self.entra_authorize_url = f"{base}/authorize"
        self.entra_token_url = f"{base}/token"

        # RSA key pair for signing MCP access tokens (generated at startup)
        self._private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

        # In-memory stores
        self._clients: dict[str, OAuthClientInformationFull] = {}
        self._auth_codes: dict[str, AuthorizationCode] = {}
        self._access_tokens: dict[str, AccessToken] = {}
        self._refresh_tokens: dict[str, RefreshToken] = {}

        # Pending Entra ID auth flows: entra_state -> flow context
        self._pending_auth: dict[str, dict] = {}

        # Entra refresh tokens keyed by MCP refresh token
        self._entra_refresh_tokens: dict[str, str] = {}

    # --- Client Registration (DCR) ---

    async def get_client(self, client_id: str) -> OAuthClientInformationFull | None:
        return self._clients.get(client_id)

    async def register_client(self, client_info: OAuthClientInformationFull) -> None:
        self._clients[client_info.client_id] = client_info
        logger.info("Registered OAuth client: %s", client_info.client_id)

    # --- Authorization ---

    async def authorize(
        self, client: OAuthClientInformationFull, params: AuthorizationParams
    ) -> str:
        # Generate PKCE pair for Entra ID (separate from Claude Code's PKCE)
        code_verifier = secrets.token_urlsafe(64)
        code_challenge = (
            base64.urlsafe_b64encode(
                hashlib.sha256(code_verifier.encode()).digest()
            )
            .decode()
            .rstrip("=")
        )

        entra_state = secrets.token_urlsafe(32)

        # Store flow context for the callback
        self._pending_auth[entra_state] = {
            "code_verifier": code_verifier,
            "redirect_uri": str(params.redirect_uri),
            "redirect_uri_provided_explicitly": params.redirect_uri_provided_explicitly,
            "code_challenge": params.code_challenge,
            "state": params.state,
            "client_id": client.client_id,
            "scopes": params.scopes or [],
            "resource": params.resource,
            "created_at": time.time(),
        }

        entra_params = {
            "client_id": self.entra_client_id,
            "response_type": "code",
            "redirect_uri": self.callback_url,
            "response_mode": "query",
            "scope": "openid profile email",
            "state": entra_state,
            "code_challenge": code_challenge,
            "code_challenge_method": "S256",
        }

        return f"{self.entra_authorize_url}?{urlencode(entra_params)}"

    # --- Entra ID Callback (custom route, not part of MCP protocol) ---

    async def handle_callback(self, request: Request) -> RedirectResponse:
        """Handle the OAuth callback from Entra ID after user authentication."""
        error = request.query_params.get("error")
        if error:
            error_desc = request.query_params.get("error_description", "")
            logger.error("Entra ID auth error: %s - %s", error, error_desc)
            # Can't redirect to client without state context
            return RedirectResponse(status_code=302, url="/")

        code = request.query_params.get("code")
        state = request.query_params.get("state")

        if not code or not state:
            logger.error("Missing code or state in Entra callback")
            return RedirectResponse(status_code=302, url="/")

        pending = self._pending_auth.pop(state, None)
        if not pending:
            logger.error("Unknown state in Entra callback")
            return RedirectResponse(status_code=302, url="/")

        # Expire after 10 minutes
        if time.time() - pending["created_at"] > 600:
            logger.error("Auth state expired")
            return RedirectResponse(status_code=302, url="/")

        # Exchange Entra code for tokens (PKCE, no client secret)
        async with httpx.AsyncClient() as http_client:
            resp = await http_client.post(
                self.entra_token_url,
                data={
                    "grant_type": "authorization_code",
                    "client_id": self.entra_client_id,
                    "code": code,
                    "redirect_uri": self.callback_url,
                    "code_verifier": pending["code_verifier"],
                },
            )

        if resp.status_code != 200:
            logger.error("Entra token exchange failed: %d %s", resp.status_code, resp.text)
            return RedirectResponse(status_code=302, url="/")

        entra_tokens = resp.json()

        # Generate MCP authorization code
        mcp_code = secrets.token_urlsafe(32)

        self._auth_codes[mcp_code] = AuthorizationCode(
            code=mcp_code,
            client_id=pending["client_id"],
            redirect_uri=AnyUrl(pending["redirect_uri"]),
            redirect_uri_provided_explicitly=pending["redirect_uri_provided_explicitly"],
            code_challenge=pending["code_challenge"],
            scopes=pending["scopes"],
            expires_at=time.time() + 300,  # 5 minutes
            resource=pending.get("resource"),
        )

        # Store Entra refresh token for later token refresh
        if "refresh_token" in entra_tokens:
            self._entra_refresh_tokens[mcp_code] = entra_tokens["refresh_token"]

        # Redirect back to Claude Code with the MCP auth code
        redirect_params: dict[str, str] = {"code": mcp_code}
        if pending["state"]:
            redirect_params["state"] = pending["state"]

        redirect_url = f"{pending['redirect_uri']}?{urlencode(redirect_params)}"
        return RedirectResponse(status_code=302, url=redirect_url)

    # --- Token Exchange ---

    async def load_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: str
    ) -> AuthorizationCode | None:
        return self._auth_codes.get(authorization_code)

    async def exchange_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: AuthorizationCode
    ) -> OAuthToken:
        # Single use - remove the auth code
        self._auth_codes.pop(authorization_code.code, None)

        now = int(time.time())
        expires_in = 3600  # 1 hour

        access_token_str = jwt.encode(
            {
                "sub": client.client_id,
                "iss": self.server_url,
                "aud": self.server_url,
                "iat": now,
                "exp": now + expires_in,
                "scopes": authorization_code.scopes,
                "jti": secrets.token_urlsafe(16),
            },
            self._private_key,
            algorithm="RS256",
        )

        self._access_tokens[access_token_str] = AccessToken(
            token=access_token_str,
            client_id=client.client_id,
            scopes=authorization_code.scopes,
            expires_at=now + expires_in,
        )

        refresh_token_str = secrets.token_urlsafe(48)
        self._refresh_tokens[refresh_token_str] = RefreshToken(
            token=refresh_token_str,
            client_id=client.client_id,
            scopes=authorization_code.scopes,
            expires_at=now + 86400 * 7,  # 7 days
        )

        # Migrate Entra refresh token to be keyed by MCP refresh token
        entra_rt = self._entra_refresh_tokens.pop(authorization_code.code, None)
        if entra_rt:
            self._entra_refresh_tokens[refresh_token_str] = entra_rt

        return OAuthToken(
            access_token=access_token_str,
            token_type="Bearer",
            expires_in=expires_in,
            refresh_token=refresh_token_str,
            scope=" ".join(authorization_code.scopes) if authorization_code.scopes else None,
        )

    # --- Token Verification ---

    async def load_access_token(self, token: str) -> AccessToken | None:
        stored = self._access_tokens.get(token)
        if stored is None:
            return None
        if stored.expires_at and stored.expires_at < int(time.time()):
            self._access_tokens.pop(token, None)
            return None
        return stored

    # --- Refresh Token ---

    async def load_refresh_token(
        self, client: OAuthClientInformationFull, refresh_token: str
    ) -> RefreshToken | None:
        return self._refresh_tokens.get(refresh_token)

    async def exchange_refresh_token(
        self,
        client: OAuthClientInformationFull,
        refresh_token: RefreshToken,
        scopes: list[str],
    ) -> OAuthToken:
        # Remove old refresh token (rotation)
        self._refresh_tokens.pop(refresh_token.token, None)

        now = int(time.time())
        expires_in = 3600

        access_token_str = jwt.encode(
            {
                "sub": client.client_id,
                "iss": self.server_url,
                "aud": self.server_url,
                "iat": now,
                "exp": now + expires_in,
                "scopes": scopes,
                "jti": secrets.token_urlsafe(16),
            },
            self._private_key,
            algorithm="RS256",
        )

        self._access_tokens[access_token_str] = AccessToken(
            token=access_token_str,
            client_id=client.client_id,
            scopes=scopes,
            expires_at=now + expires_in,
        )

        new_refresh_str = secrets.token_urlsafe(48)
        self._refresh_tokens[new_refresh_str] = RefreshToken(
            token=new_refresh_str,
            client_id=client.client_id,
            scopes=scopes,
            expires_at=now + 86400 * 7,
        )

        # Migrate Entra refresh token
        entra_rt = self._entra_refresh_tokens.pop(refresh_token.token, None)
        if entra_rt:
            self._entra_refresh_tokens[new_refresh_str] = entra_rt

        return OAuthToken(
            access_token=access_token_str,
            token_type="Bearer",
            expires_in=expires_in,
            refresh_token=new_refresh_str,
            scope=" ".join(scopes) if scopes else None,
        )

    # --- Revocation ---

    async def revoke_token(self, token: AccessToken | RefreshToken) -> None:
        if isinstance(token, AccessToken):
            self._access_tokens.pop(token.token, None)
        elif isinstance(token, RefreshToken):
            self._refresh_tokens.pop(token.token, None)
            self._entra_refresh_tokens.pop(token.token, None)
