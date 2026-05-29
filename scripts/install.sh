#!/usr/bin/env bash
#
# pluuug MCP installer (macOS)
# ─────────────────────────────────────────────────────────────────────────────
# 이 스크립트는 다음 작업을 자동으로 수행합니다:
#   1. macOS / Claude Desktop 설치 여부 확인
#   2. uv 자동 설치 (이미 있으면 건너뜀)
#   3. PLUUUG_API_KEY / PLUUUG_SECRET_KEY 대화형 입력
#   4. ~/Library/Application Support/Claude/claude_desktop_config.json 백업 + 'pluuug' 서버 등록
#   5. wrapper 받아오기 + 동작 검증
#   6. Claude Desktop 재기동 안내 (수동)
#
# 사용:
#   curl -fsSL https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.sh | bash
#
# 검증 후 실행을 원한다면:
#   curl -O https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.sh
#   shasum -a 256 install.sh           # 게시된 hash와 대조
#   bash install.sh
#
# 소스: https://github.com/postoo-io/pluuug-openapi-mcp/blob/main/scripts/install.sh
# ─────────────────────────────────────────────────────────────────────────────

# `sh`로 실행된 경우 — read -s 등 bash 확장이 필요하므로 명시적 안내
if [ -z "${BASH_VERSION:-}" ]; then
  echo "[!] 이 스크립트는 bash로 실행되어야 합니다." >&2
  echo "    다음과 같이 실행하세요:" >&2
  echo "    curl -fsSL https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.sh | bash" >&2
  exit 1
fi

set -euo pipefail

# ── 설정 ─────────────────────────────────────────────────────────────────────
REPO_URL="git+https://github.com/postoo-io/pluuug-openapi-mcp.git"
CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
SERVER_NAME="pluuug"

# ── ANSI 색상 (TTY에만) ──────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; CYAN=''; RESET=''
fi

step() { printf "\n${BOLD}${CYAN}[%s/6]${RESET} ${BOLD}%s${RESET}\n" "$1" "$2"; }
info() { printf "  ${DIM}%s${RESET}\n" "$1"; }
ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
fail() { printf "  ${RED}✗ %s${RESET}\n" "$1" >&2; exit 1; }

# ── 시작 배너 ────────────────────────────────────────────────────────────────
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD}     pluuug MCP installer  (macOS)${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${DIM}Claude Desktop에 pluuug MCP 서버를 등록합니다.${RESET}\n"

# ── [1/6] OS + Claude Desktop ────────────────────────────────────────────────
step 1 "환경 점검"
[ "$(uname)" = "Darwin" ] || fail "현재 macOS만 지원합니다. Windows/Linux는 추후 지원 예정."
ok "macOS 확인"

if [ ! -d "/Applications/Claude.app" ]; then
  fail "Claude Desktop이 설치돼 있지 않습니다.
       먼저 https://claude.ai/download 에서 다운로드/설치하세요."
fi
ok "Claude Desktop 확인"

# python3 + git (config 병합 + wrapper fetch에 필요)
# macOS는 python3/git의 stub이 PATH에 있어도 실제 호출 시 Command Line Tools(CLT) 설치
# 다이얼로그가 뜨면서 stub이 비정상 종료되어 스크립트가 abort된다. command -v는 통과하므로
# 반드시 실제 코드 실행으로 검증한다.
if ! python3 -c "import json" >/dev/null 2>&1 || ! git --version >/dev/null 2>&1; then
  warn "macOS Command Line Tools가 필요합니다 (python3/git 사용)."
  info "잠시 후 macOS가 설치 다이얼로그를 띄웁니다 — '설치'를 눌러주세요."
  xcode-select --install >/dev/null 2>&1 || true
  fail "CLT 설치 완료(수 분 소요) 후 다시 실행:
       curl -fsSL https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.sh | bash"
fi
ok "python3 확인 ($(python3 --version 2>&1))"
ok "git 확인 ($(git --version 2>&1))"

# ── [2/6] uv ─────────────────────────────────────────────────────────────────
step 2 "uv 확인"
if command -v uv >/dev/null 2>&1; then
  ok "uv 이미 설치됨 ($(uv --version 2>&1 | head -1))"
else
  info "uv가 없습니다. 자동 설치합니다... (astral.sh/uv 공식 스크립트)"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # uv 설치 스크립트는 $HOME/.local/bin 또는 $HOME/.cargo/bin에 둠
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  command -v uv >/dev/null 2>&1 \
    || fail "uv 설치 후 PATH에서 찾을 수 없습니다. 새 터미널을 열고 다시 시도하세요."
  ok "uv 설치 완료 ($(uv --version 2>&1 | head -1))"
fi

# ── [3/6] 키 입력 ────────────────────────────────────────────────────────────
step 3 "API Key 입력"
info "pluuug 어드민에서 발급받은 키 2개를 입력하세요."
info "Secret Key는 보안상 입력이 화면에 표시되지 않습니다."

# stdin이 파이프(curl|bash)일 수 있어 /dev/tty에서 직접 읽음
if [ ! -r /dev/tty ]; then
  fail "터미널 입력을 읽을 수 없습니다. 다음과 같이 다시 시도하세요:
       1) curl -O https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.sh
       2) bash install.sh"
fi

read -r -p "  PLUUUG_API_KEY: " API_KEY < /dev/tty || fail "키 입력이 취소되었습니다."
[ -n "${API_KEY:-}" ] || fail "API Key가 비어있습니다."

read -r -s -p "  PLUUUG_SECRET_KEY (입력 안 보임): " SECRET_KEY < /dev/tty || fail "키 입력이 취소되었습니다."
echo
[ -n "${SECRET_KEY:-}" ] || fail "Secret Key가 비어있습니다."
ok "키 입력 완료"

# ── [4/6] config 백업 + 병합 ─────────────────────────────────────────────────
step 4 "Claude Desktop 설정 업데이트"
mkdir -p "$(dirname "$CFG")"

# 기존 pluuug 서버 등록 여부 검사
EXISTS=$(SERVER="$SERVER_NAME" CFG="$CFG" python3 <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["CFG"])
if not p.exists():
    print("no_file"); raise SystemExit
try:
    d = json.loads(p.read_text())
except Exception:
    print("invalid"); raise SystemExit
servers = (d.get("mcpServers") or {}) if isinstance(d.get("mcpServers"), dict) else {}
print("exists" if os.environ["SERVER"] in servers else "absent")
PY
)

case "$EXISTS" in
  invalid)
    fail "기존 config가 유효한 JSON이 아닙니다: $CFG
         먼저 수동 정리하거나 백업 후 삭제하세요."
    ;;
  no_file|absent|exists) ;;
  *)
    # python3 호출이 비정상 종료(CLT 다이얼로그 등)되어 EXISTS가 비어있거나 예상 외 값.
    # [1/6]의 실 실행 검증으로 거의 잡히지만 race 대비 default.
    fail "config 상태 확인 실패 (응답: '$EXISTS')
         python3가 정상 동작하는지 확인 후 다시 시도하세요."
    ;;
esac

if [ "$EXISTS" = "exists" ]; then
  warn "이미 '$SERVER_NAME' 서버가 등록돼 있습니다."
  printf "  덮어쓸까요? (기존 설정은 자동 백업됩니다) [y/N]: "
  read -r ANSWER < /dev/tty || ANSWER=""
  case "$ANSWER" in
    y|Y|yes|YES) ;;
    *) fail "취소되었습니다." ;;
  esac
fi

if [ -f "$CFG" ]; then
  BACKUP="${CFG}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CFG" "$BACKUP"
  ok "기존 config 백업: $(basename "$BACKUP")"
fi

# JSON 안전 병합 (다른 MCP 서버는 보존)
API_KEY="$API_KEY" SECRET_KEY="$SECRET_KEY" REPO_URL="$REPO_URL" SERVER="$SERVER_NAME" CFG="$CFG" python3 <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["CFG"])
d = json.loads(p.read_text()) if p.exists() else {}
if not isinstance(d.get("mcpServers"), dict):
    d["mcpServers"] = {}
d["mcpServers"][os.environ["SERVER"]] = {
    "command": "uvx",
    "args": ["--from", os.environ["REPO_URL"], "pluuug-openapi-mcp"],
    "env": {
        "PLUUUG_API_KEY":    os.environ["API_KEY"],
        "PLUUUG_SECRET_KEY": os.environ["SECRET_KEY"],
    },
}
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
ok "'$SERVER_NAME' 서버 등록 완료"

# ── [5/6] wrapper 받아오기 + 동작 검증 ───────────────────────────────────────
step 5 "wrapper 받아오기 (20~40초 소요)"
info "git에서 wrapper를 받고 Python 의존성을 설치합니다. 잠시만 기다려주세요..."
if uvx --from "$REPO_URL" pluuug-openapi-mcp --help >/dev/null 2>&1; then
  ok "wrapper 정상 동작"
else
  fail "wrapper 실행 실패. 네트워크 또는 Python 환경을 확인하세요.
       문제 지속 시: https://github.com/postoo-io/pluuug-openapi-mcp/issues"
fi

# ── [6/6] 재기동 안내 ────────────────────────────────────────────────────────
step 6 "Claude Desktop 재기동"

cat <<EOF

${BOLD}${GREEN}✓ 설치 완료!${RESET}

${BOLD}이제 Claude Desktop을 완전히 재기동하세요:${RESET}

  ${BOLD}1)${RESET} 화면 ${BOLD}상단 메뉴바${RESET}의 [Claude] 메뉴 → [Claude 종료]
     ${YELLOW}⚠ 창의 빨간 X 버튼만 누르면 안 됩니다 — 메뉴바 트레이에 살아있으면 적용 안 됨.${RESET}

  ${BOLD}2)${RESET} Spotlight(Cmd+Space) 또는 Launchpad에서 ${BOLD}Claude를 다시 실행${RESET}

  ${BOLD}3)${RESET} 새 대화창에서 다음과 같이 입력해보세요:
     ${CYAN}"pluuug에서 최근 의뢰 5건 보여줘"${RESET}

${DIM}문제가 있다면: https://docs.openapi.pluuug.com/integrations/mcp${RESET}

EOF
