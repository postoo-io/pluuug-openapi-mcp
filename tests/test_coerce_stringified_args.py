"""Regression test for `_patch_coerce_stringified_args`.

일부 MCP 클라이언트가 nested object/array 인자를 JSON 문자열로 직렬화해 보내는
케이스를, 패치가 선언 타입(object/array) 기준으로만 복원하고 스칼라(string)는
그대로 두는지 검증한다. fastmcp 내부(RequestDirector)에 대한 monkey-patch라
fastmcp 버전업으로 hook 지점이 바뀌면 이 테스트가 깨져 회귀를 잡는다.
"""

import asyncio
import json

import httpx

from pluuug_openapi_mcp.cli import _patch_coerce_stringified_args

# nested object(oneOf null+$ref) + array(type[array,null]+items $ref) + scalar 를
# 모두 가진 최소 스펙 — pluuug 실제 connection 파라미터 형태를 모사.
SPEC = {
    "openapi": "3.1.0",
    "info": {"title": "t", "version": "1"},
    "paths": {
        "/thing": {
            "post": {
                "operationId": "thing_create",
                "requestBody": {
                    "required": True,
                    "content": {
                        "application/json": {"schema": {"$ref": "#/components/schemas/ThingRequest"}}
                    },
                },
                "responses": {"200": {"description": "ok"}},
            }
        }
    },
    "components": {
        "schemas": {
            "ThingRequest": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "ref": {"oneOf": [{"type": "null"}, {"$ref": "#/components/schemas/Ref"}]},
                    "items": {"type": ["array", "null"], "items": {"$ref": "#/components/schemas/Ref"}},
                },
            },
            "Ref": {"type": "object", "properties": {"id": {"type": "integer"}}, "required": ["id"]},
        }
    },
}


def _run_tool(args: dict) -> dict:
    """패치 적용 후 thing_create를 호출하고 wire에 실린 JSON 본문을 돌려준다."""
    _patch_coerce_stringified_args()

    from fastmcp.server.openapi import FastMCPOpenAPI

    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = request.content.decode("utf-8", "replace")
        captured["content_type"] = request.headers.get("content-type")
        return httpx.Response(200, json={"ok": True})

    async def go():
        client = httpx.AsyncClient(
            base_url="https://example.com", transport=httpx.MockTransport(handler)
        )
        mcp = FastMCPOpenAPI(openapi_spec=SPEC, client=client, name="t")
        tool = (await mcp.get_tools())["thing_create"]
        await tool.run(args)
        await client.aclose()

    asyncio.run(go())
    return json.loads(captured["body"])


def test_stringified_object_and_array_are_revived():
    body = _run_tool(
        {
            "name": "hello",
            "ref": '{"id": 5}',  # object as JSON string
            "items": '[{"id": 7}]',  # array as JSON string
        }
    )
    assert body["ref"] == {"id": 5}, body
    assert body["items"] == [{"id": 7}], body
    # 스칼라 string은 그대로
    assert body["name"] == "hello", body


def test_proper_structures_pass_through_unchanged():
    body = _run_tool({"name": "x", "ref": {"id": 9}, "items": [{"id": 1}]})
    assert body["ref"] == {"id": 9}
    assert body["items"] == [{"id": 1}]


def test_scalar_string_that_looks_like_json_is_not_coerced():
    # name은 선언 타입이 string이라, 값이 JSON처럼 보여도 건드리면 안 된다.
    body = _run_tool({"name": "[1, 2, 3]", "ref": {"id": 1}})
    assert body["name"] == "[1, 2, 3]", body
    assert isinstance(body["name"], str)
