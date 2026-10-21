"""pluuug 인증 = X-API-Key 헤더 하나.

pluuug 백엔드가 요청 서명(X-Signature)을 폐지해, wrapper는 awslabs 내장 ``api_key``
인증에 기본값만 채운다. 고객은 ``PLUUUG_API_KEY`` 하나만 넣는다.
"""

from awslabs.openapi_mcp_server.api.config import load_config
from awslabs.openapi_mcp_server.auth.auth_factory import clear_provider_cache, get_auth_provider
from awslabs.openapi_mcp_server.auth.register import register_provider_by_type

from pluuug_openapi_mcp.cli import _apply_api_key_env, _ensure_default_args


def _flag_value(argv, flag):
    return argv[argv.index(flag) + 1]


def test_default_args_use_builtin_api_key_auth_on_x_api_key_header():
    argv = _ensure_default_args([])

    assert _flag_value(argv, "--auth-type") == "api_key"
    assert _flag_value(argv, "--auth-api-key-name") == "X-API-Key"
    assert _flag_value(argv, "--auth-api-key-in") == "header"
    assert "--auth-api-key" not in argv  # 키는 프로세스 목록에 남는 argv 대신 env로 넘긴다


def test_pluuug_api_key_env_is_passed_to_awslabs(monkeypatch):
    monkeypatch.setenv("PLUUUG_API_KEY", "customer-key")
    monkeypatch.delenv("AUTH_API_KEY", raising=False)

    _apply_api_key_env()

    import os

    assert os.environ["AUTH_API_KEY"] == "customer-key"


def test_explicit_auth_api_key_is_not_overridden(monkeypatch):
    monkeypatch.setenv("PLUUUG_API_KEY", "customer-key")
    monkeypatch.setenv("AUTH_API_KEY", "explicit-key")

    _apply_api_key_env()

    import os

    assert os.environ["AUTH_API_KEY"] == "explicit-key"


def test_awslabs_sends_only_x_api_key_header(monkeypatch):
    monkeypatch.setenv("PLUUUG_API_KEY", "customer-key")
    monkeypatch.delenv("AUTH_API_KEY", raising=False)
    monkeypatch.setenv("AUTH_TYPE", "api_key")
    monkeypatch.setenv("AUTH_API_KEY_NAME", "X-API-Key")
    monkeypatch.setenv("AUTH_API_KEY_IN", "header")
    _apply_api_key_env()
    clear_provider_cache()
    register_provider_by_type("api_key")  # awslabs server.main 이 서버 생성 시 하는 등록과 같다

    provider = get_auth_provider(load_config())

    assert provider.get_auth_headers() == {"X-API-Key": "customer-key"}
