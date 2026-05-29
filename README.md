# pluuug-openapi-mcp

[pluuug openapi](https://openapi.pluuug.com)를 Model Context Protocol(MCP)
도구로 노출하는 wrapper. Claude Desktop, Cursor 등 MCP 클라이언트에서 pluuug
API를 LLM tool로 사용할 수 있다.

내부적으로 [`awslabs/openapi-mcp-server`](https://github.com/awslabs/mcp/tree/main/src/openapi-mcp-server)를
사용하되, pluuug 백엔드의 **X-API-Key + X-Signature(HMAC-SHA256 of body)**
인증을 자동으로 추가한다.

## Quick start (Claude Desktop, macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.sh | bash
```

스크립트가 자동으로 처리하는 것:

1. macOS / Claude Desktop / Python3 / git 환경 점검
2. `uv` 자동 설치 (미설치 시)
3. API Key / Secret Key 대화형 입력
4. `claude_desktop_config.json` 백업 + `pluuug` MCP 서버 등록
5. wrapper 받아오기 + 동작 검증
6. Claude Desktop 재기동 안내

설치 후 Claude Desktop 새 대화에서:

```
"내 비즈니스의 최근 의뢰 5건 보여줘"
```

라고 하면 LLM이 자동으로 `inquiry_list` tool을 호출한다.

**상세 가이드 / 트러블슈팅 / FAQ:**
[https://docs.openapi.pluuug.com/integrations/mcp](https://docs.openapi.pluuug.com/integrations/mcp)

## 동작 원리 — 인증

pluuug 백엔드는 두 헤더를 모두 요구한다:

| 헤더 | 값 | 비고 |
|---|---|---|
| `X-API-Key` | `PLUUUG_API_KEY` 값 | 신원 식별 (wire 전송) |
| `X-Signature` | `HMAC-SHA256(secret_key, request_body)`의 hex digest | wrapper가 자동 계산 (secret_key는 wire에 안 보냄) |

수동으로 HMAC 계산하지 않아도 wrapper가 매 요청마다 자동 처리.

## 노출되는 도구

[pluuug openapi 스펙](https://openapi.pluuug.com/openapi.json/)에서 자동으로
약 72개 MCP tool이 생성된다. 도메인:

- 의뢰, 계약, 정산, 고객, 견적, 프로젝트, Todo, 실무자, 멤버
- 폴더, 커스텀 필드, Presigned URL, 호출 로그

각 tool은 OpenAPI 스펙의 description을 그대로 사용. Tool 사용 가능 여부는
비즈니스 플랜에 따라 다를 수 있다 (project/worker는 FREE/AGENCY 전용 등).

## Manual install (advanced)

install.sh 대신 직접 등록하려면 — wrapper 명령어:

```bash
uvx --from "git+https://github.com/postoo-io/pluuug-openapi-mcp.git" pluuug-openapi-mcp
```

`claude_desktop_config.json` 예시:

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

> ⚠️ **OS 환경변수(`launchctl setenv` / `export` / Windows 사용자 변수)로는
> 안 된다.** Claude Desktop은 MCP 서브프로세스 환경을 자체 구성하므로 OS
> 환경변수가 전달되지 않는다. `env` 블록만 안정적으로 전달된다.
>
> **보안:** `env` 블록은 secret을 평문으로 저장한다. 파일 권한(`chmod 600`)
> · 백업 · 스크린샷 유출에 주의한다.

설정 변경 후 Claude Desktop을 **완전히 종료(메뉴바 트레이 포함) 후
재시작**한다.

## 다른 MCP 클라이언트 (Cursor, Continue 등)

MCP 표준 stdio 프로토콜을 따르므로 MCP 지원 클라이언트 어디서든 사용 가능.
install.sh는 Claude Desktop config 자동 등록만 다루므로, 다른 클라이언트는
각자 설정 파일에 위 Manual install의 wrapper 명령어를 등록.

## 라이선스

MIT.
