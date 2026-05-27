# pluuug-openapi-mcp

[pluuug openapi](https://openapi.pluuug.com)를 Model Context Protocol(MCP)
도구로 노출하는 wrapper. Claude Desktop, Cursor 등 MCP 클라이언트에서 pluuug API를
LLM tool로 사용할 수 있다.

내부적으로 [`awslabs/openapi-mcp-server`](https://github.com/awslabs/mcp/tree/main/src/openapi-mcp-server)를
사용하되, pluuug 백엔드가 요구하는 **X-API-Key + X-Signature(HMAC-SHA256 of body)**
인증을 자동으로 추가한다.

## 설치 및 실행

[`uv`](https://docs.astral.sh/uv/) 또는 `pipx`로 실행. 별도 설치 없이 `uvx`로 한
줄 실행 가능.

GitHub repo에서 직접 실행 (현재 권장):

```bash
uvx --from "git+https://github.com/postoo-io/pluuug-openapi-mcp.git" pluuug-openapi-mcp
```

> PyPI publish 이후엔 단축 명령 가능: `uvx pluuug-openapi-mcp@latest`

## Claude Desktop 설정

`~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) 또는
`%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "pluuug": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/postoo-io/pluuug-openapi-mcp.git",
        "pluuug-openapi-mcp"
      ],
      "env": {
        "PLUUUG_API_KEY": "<발급받은 API Key>",
        "PLUUUG_SECRET_KEY": "<발급받은 Secret Key>"
      }
    }
  }
}
```

API Key와 Secret Key는 위 `env` 블록에 **직접** 넣는다.

> ⚠️ **OS 환경변수(`launchctl setenv` / `export` / Windows 사용자 변수)로는 안 된다.**
> Claude Desktop은 MCP 서버 서브프로세스의 환경을 자체 구성하므로 OS 환경변수가
> 전달되지 않는다(서버 로그에 `PLUUUG_API_KEY env var not set` → 호출 403/401).
> `claude_desktop_config.json`의 `env` 블록만 안정적으로 전달된다.
>
> **보안:** `env` 블록은 secret을 config 파일에 평문으로 저장한다. 파일 권한(chmod 600)·
> 백업·스크린샷 유출에 주의한다.

설정 변경 후 Claude Desktop을 **완전히 종료(트레이 포함) 후 재시작**한다.

## API Key / Secret Key 발급

pluuug 어드민 페이지에서 비즈니스별로 API Key를 발급받는다.

> **중요:** `secret_key`는 **발급 시점에 1회만 응답에 포함**된다. 잃어버리면
> 재발급이 필요하다. 발급 직후 1Password, OS 키체인 등 안전한 곳에 저장하라.

## 인증 방식

pluuug 백엔드는 두 헤더를 모두 요구한다:

| 헤더 | 값 | 비고 |
|---|---|---|
| `X-API-Key` | `PLUUUG_API_KEY` 값 | 신원 식별 (와이어로 전송) |
| `X-Signature` | `HMAC-SHA256(secret_key, request_body)`의 hex digest | 본 wrapper가 자동 계산 (secret_key는 와이어로 안 보냄) |

수동으로 HMAC 계산하지 않아도 wrapper가 매 요청마다 자동 처리한다.

## 노출되는 도구

[pluuug openapi 스펙](https://openapi.pluuug.com/openapi.json/)에서 자동으로 약
72개 MCP tool이 생성된다. 도메인:

- 의뢰 (inquiry) — 의뢰 CRUD + 히스토리(상태/폴더/제출/이메일/텍스트) + 파일
- 계약 (contract), 정산 (settlement), 고객 (client), 견적 (estimate)
- 프로젝트 (project), Todo, 실무자 (worker), 멤버 (member)
- 폴더 (folder), 커스텀 필드 (field), Presigned URL, 호출 로그

각 tool은 우리 OpenAPI 스펙의 description을 그대로 사용한다. Tool 사용 가능
여부는 비즈니스 플랜에 따라 다를 수 있다 (project/worker는 FREE/AGENCY 전용 등).

## 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| 401 인증 실패 | `PLUUUG_API_KEY` 누락/오기재 | env 확인, Claude Desktop 완전 재시작 |
| 모든 호출 403 (signature mismatch) | `PLUUUG_SECRET_KEY` 누락/오기재 | env 확인 |
| 403 PLAN_PERMISSION_DENIED | 플랜 제약 (project/worker/member) | 해당 플랜으로 업그레이드 |
| 429 Too Many Requests | throttle 1000/min 초과 | 호출 빈도 조정 |
| 자격증명이 MCP 서버에 안 보임 (401/403) | OS env가 Claude Desktop 서브프로세스에 미전달 | `claude_desktop_config.json`의 `env` 블록에 키 직접 주입 후 완전 재시작 |
| Secret Key 분실 | 정책상 발급 시점 1회만 노출 | 새 API Key 재발급 + `env` 블록 값 갱신 + Claude Desktop 재시작 |
| MCP 서버 startup fail (pydantic enum error) | fastmcp 3.x 호환 깨짐 | 이 패키지가 자동으로 `fastmcp<3.0.0` 핀 — 별도 처리 불필요 |

## 라이선스

MIT.
