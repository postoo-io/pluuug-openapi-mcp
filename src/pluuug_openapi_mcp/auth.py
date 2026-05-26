"""HMAC body signing auth for pluuug openapi.

pluuug backend requires X-API-Key + X-Signature where the signature is
HMAC-SHA256 of the request body, computed with a per-business secret_key.
This module provides:

- ``HMACAuth``: an ``httpx.Auth`` subclass that signs each outgoing request.
- ``PluuugHMACAuthProvider``: an ``awslabs.openapi-mcp-server`` AuthProvider
  that wires ``HMACAuth`` into the MCP server's underlying httpx client.

Credentials are read from environment variables:

- ``PLUUUG_API_KEY``: the API key (sent in X-API-Key header).
- ``PLUUUG_SECRET_KEY``: the secret key (used for HMAC, never sent).
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import os
from typing import Any, Dict, Generator, Optional

import httpx

logger = logging.getLogger(__name__)


class HMACAuth(httpx.Auth):
    """httpx.Auth that injects X-API-Key + X-Signature(HMAC-SHA256 of body).

    Matches pluuug backend's ``APIKeyAuthBackend`` (see
    ``pluuug-django/src/config/authentication.py``).
    """

    # Force httpx to materialize request body before invoking auth_flow.
    requires_request_body = True

    def __init__(self, api_key: str, secret_key: str) -> None:
        if not api_key or not secret_key:
            raise ValueError("HMACAuth requires non-empty api_key and secret_key")
        self._api_key = api_key
        self._secret = secret_key.encode("utf-8")

    def auth_flow(self, request: httpx.Request) -> Generator[httpx.Request, httpx.Response, None]:
        body = request.content or b""
        signature = hmac.new(self._secret, body, hashlib.sha256).hexdigest()
        request.headers["X-API-Key"] = self._api_key
        request.headers["X-Signature"] = signature
        yield request


# ----- AuthProvider registration into awslabs/openapi-mcp-server -----

try:
    from awslabs.openapi_mcp_server.auth.auth_provider import AuthProvider
except ImportError:  # pragma: no cover - allow import for unit tests
    AuthProvider = object  # type: ignore[assignment,misc]


class PluuugHMACAuthProvider(AuthProvider):  # type: ignore[misc]
    """AuthProvider implementing pluuug X-API-Key + X-Signature."""

    AUTH_TYPE = "pluuug_hmac"

    def __init__(self, config: Any = None) -> None:
        # awslabs constructs the provider with its Config object; we ignore
        # config fields and read credentials from env so that pluuug
        # customers can manage them outside the MCP config file.
        self._api_key = os.environ.get("PLUUUG_API_KEY", "")
        self._secret_key = os.environ.get("PLUUUG_SECRET_KEY", "")

        if not self._api_key:
            logger.warning("PLUUUG_API_KEY not set; pluuug MCP requests will lack X-API-Key.")
        if not self._secret_key:
            logger.warning(
                "PLUUUG_SECRET_KEY not set; HMAC signature cannot be computed."
            )

    def get_auth_headers(self) -> Dict[str, str]:
        # Headers are computed per-request inside HMACAuth.auth_flow.
        return {}

    def get_auth_params(self) -> Dict[str, str]:
        return {}

    def get_auth_cookies(self) -> Dict[str, str]:
        return {}

    def get_httpx_auth(self) -> Optional[httpx.Auth]:
        if not self.is_configured():
            return None
        return HMACAuth(self._api_key, self._secret_key)

    def is_configured(self) -> bool:
        return bool(self._api_key and self._secret_key)

    @property
    def provider_name(self) -> str:
        return self.AUTH_TYPE


def register_with_awslabs() -> None:
    """Register ``PluuugHMACAuthProvider`` under awslabs auth type ``pluuug_hmac``.

    Call this once before ``awslabs.openapi-mcp-server`` resolves auth providers
    (i.e. before the server entry point starts). Safe to call multiple times;
    subsequent registrations are skipped silently.
    """
    from awslabs.openapi_mcp_server.auth.auth_factory import (
        _AUTH_PROVIDERS,
        register_auth_provider,
    )

    if PluuugHMACAuthProvider.AUTH_TYPE in _AUTH_PROVIDERS:
        return
    register_auth_provider(PluuugHMACAuthProvider.AUTH_TYPE, PluuugHMACAuthProvider)
