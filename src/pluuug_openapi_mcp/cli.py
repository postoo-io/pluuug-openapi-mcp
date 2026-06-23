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
# of these by passing the flag explicitly on the command line (e.g. staging,
# self-hosted, or local-dev backends).
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


def _patch_disable_output_schema() -> None:
    """Workaround: strip outputSchema from all generated MCP tools.

    Claude Desktop rejects tool responses for tools that declare ``outputSchema``
    (treats them as "Tool execution failed" even when the wire response is valid
    and ``structuredContent`` is included). By neutralizing the OpenAPI →
    outputSchema extractor we make fastmcp register tools without an
    outputSchema, the MCP SDK then skips its strict outputSchema validation, and
    Claude Desktop processes the JSON text content successfully.

    Must be called before awslabs ``server.main`` constructs ``FastMCPOpenAPI``,
    so the extractor lookup at tool-registration time returns ``None``.
    """
    import fastmcp.experimental.utilities.openapi as _openapi_utils
    import fastmcp.server.openapi.server as _openapi_server

    def _noop(*args, **kwargs):  # type: ignore[no-untyped-def]
        return None

    _openapi_utils.extract_output_schema_from_responses = _noop
    # ``server.py``가 이미 ``from ... import extract_output_schema_from_responses``로
    # 끌어다 쓴 local reference도 교체 — Python import 의미상 같은 함수 객체가 아닌
    # module-local name이라 별도로 덮어써야 한다.
    _openapi_server.extract_output_schema_from_responses = _noop


def _patch_coerce_stringified_args() -> None:
    """Workaround: revive nested object/array args that the client sent as a JSON string.

    일부 MCP 클라이언트(LLM)는 ``client``/``status``/``fieldSet`` 같은 nested
    object·array 파라미터를 구조(dict/list)가 아니라 **JSON 문자열**로 직렬화해
    보낸다 (예: ``status="{\\"id\\": 31442}"``). fastmcp ``RequestDirector``는 받은
    값을 그대로 application/json 본문에 실으므로, 백엔드의 중첩 직렬화기가 dict/list
    자리에서 str을 받아 400("딕셔너리/리스트 대신 str")으로 거부한다. 간헐적이라
    클라이언트가 통제하기 어렵다.

    ``RequestDirector.build``를 감싸, 각 인자의 **선언 타입이 object/array인 경우에
    한해**(``route.flat_param_schema`` 기준) str 값을 ``json.loads``로 복원한다.
    스칼라(string 등) 필드는 건드리지 않으므로, 값이 우연히 JSON처럼 보이는 일반
    문자열은 그대로 보존된다.

    Must be called before awslabs ``server.main`` constructs ``FastMCPOpenAPI``.
    """
    import json

    from fastmcp.utilities.openapi.director import RequestDirector

    _orig_build = RequestDirector.build

    def _expects_structured(schema, defs, depth: int = 0) -> bool:
        """schema가 object/array(또는 그 ref/조합)를 기대하는지 판별."""
        if not isinstance(schema, dict) or depth > 12:
            return False
        type_ = schema.get("type")
        if isinstance(type_, str) and type_ in ("object", "array"):
            return True
        if isinstance(type_, list) and ("object" in type_ or "array" in type_):
            return True
        if "properties" in schema or "items" in schema:
            return True
        ref = schema.get("$ref")
        if isinstance(ref, str) and "/" in ref:
            return _expects_structured(defs.get(ref.rsplit("/", 1)[-1], {}), defs, depth + 1)
        for combiner in ("oneOf", "anyOf", "allOf"):
            for branch in schema.get(combiner) or []:
                if _expects_structured(branch, defs, depth + 1):
                    return True
        return False

    def _patched_build(self, route, flat_args, base_url="http://localhost"):  # type: ignore[no-untyped-def]
        schema = getattr(route, "flat_param_schema", None)
        if isinstance(schema, dict) and isinstance(flat_args, dict):
            props = schema.get("properties", {})
            defs = schema.get("$defs", {})
            coerced = {}
            for name, value in flat_args.items():
                if isinstance(value, str) and _expects_structured(props.get(name), defs):
                    try:
                        parsed = json.loads(value)
                    except (ValueError, TypeError):
                        parsed = value
                    coerced[name] = parsed if isinstance(parsed, (dict, list)) else value
                else:
                    coerced[name] = value
            flat_args = coerced
        return _orig_build(self, route, flat_args, base_url)

    RequestDirector.build = _patched_build


def main() -> None:
    """Entry point for ``pluuug-openapi-mcp`` console script."""
    # 0. Extend awslabs argparse choices before its parser is constructed.
    _patch_argparse_choices()
    # 0b. Disable outputSchema generation for Claude Desktop compatibility.
    _patch_disable_output_schema()
    # 0c. Revive nested object/array args sent as JSON strings by some clients.
    _patch_coerce_stringified_args()

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
