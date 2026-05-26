"""CLI entry for pluuug-openapi-mcp.

Wraps ``awslabs.openapi-mcp-server`` by:

1. Registering :class:`PluuugHMACAuthProvider` as awslabs auth type ``pluuug_hmac``.
2. Pre-filling sensible defaults for pluuug (spec URL, API URL, auth type).
3. Delegating to ``awslabs.openapi_mcp_server.server.main`` for actual startup.

Customers run via ``uvx pluuug-openapi-mcp@latest`` from their Claude Desktop /
MCP client config; credentials are picked up from ``PLUUUG_API_KEY`` and
``PLUUUG_SECRET_KEY`` environment variables.
"""

from __future__ import annotations

import os
import sys
from typing import List

from .auth import register_with_awslabs

# Default values matching pluuug production deployment. Users can override any
# of these by passing the flag explicitly on the command line.
DEFAULT_ARGS: dict[str, str] = {
    "--api-name": "pluuug",
    "--api-url": "https://openapi.pluuug.com",
    "--spec-url": "https://openapi.pluuug.com/openapi.json/",
    "--auth-type": "pluuug_hmac",
}


def _ensure_default_args(argv: List[str]) -> List[str]:
    """Inject DEFAULT_ARGS into argv for any flag that wasn't supplied."""
    out = list(argv)
    for flag, value in DEFAULT_ARGS.items():
        if flag not in out:
            out.extend([flag, value])
    return out


def main() -> None:
    """Entry point for ``pluuug-openapi-mcp`` console script."""
    # 1. Register pluuug HMAC auth provider with awslabs' factory before
    # awslabs.openapi_mcp_server.server.main consults the registry.
    register_with_awslabs()

    # 2. Patch sys.argv so awslabs argparse picks up pluuug defaults.
    sys.argv = [sys.argv[0]] + _ensure_default_args(sys.argv[1:])

    # 3. Surface credential warnings early — easier to diagnose than 401.
    if not os.environ.get("PLUUUG_API_KEY"):
        print(
            "[pluuug-openapi-mcp] WARN: PLUUUG_API_KEY env var not set; "
            "MCP tools will be visible but API calls will fail (401).",
            file=sys.stderr,
        )
    if not os.environ.get("PLUUUG_SECRET_KEY"):
        print(
            "[pluuug-openapi-mcp] WARN: PLUUUG_SECRET_KEY env var not set; "
            "X-Signature cannot be computed, API calls will fail (403).",
            file=sys.stderr,
        )

    # 4. Delegate to awslabs main.
    from awslabs.openapi_mcp_server.server import main as awslabs_main

    awslabs_main()


if __name__ == "__main__":
    main()
