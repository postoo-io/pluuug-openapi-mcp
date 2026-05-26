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


def _patch_argparse_choices() -> None:
    """Extend awslabs argparse ``--auth-type`` choices to accept ``pluuug_hmac``.

    awslabs server.py defines ``--auth-type`` with a fixed ``choices`` list
    (none, basic, bearer, api_key, cognito). argparse rejects any other value
    with "invalid choice". We register a new auth type, so we have to teach
    argparse about it before ``parse_args`` runs.
    """
    import argparse

    _orig = argparse._ActionsContainer.add_argument  # type: ignore[attr-defined]

    def _patched(self, *args, **kwargs):  # type: ignore[no-untyped-def]
        flags = [a for a in args if isinstance(a, str) and a.startswith("--")]
        if "--auth-type" in flags and "choices" in kwargs and kwargs["choices"]:
            choices = list(kwargs["choices"])
            if "pluuug_hmac" not in choices:
                choices.append("pluuug_hmac")
            kwargs["choices"] = choices
        return _orig(self, *args, **kwargs)

    argparse._ActionsContainer.add_argument = _patched  # type: ignore[attr-defined]


def main() -> None:
    """Entry point for ``pluuug-openapi-mcp`` console script."""
    # 0. Extend awslabs argparse choices before its parser is constructed.
    _patch_argparse_choices()

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
