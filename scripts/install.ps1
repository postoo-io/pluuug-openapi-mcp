# pluuug MCP installer (Windows)
# ─────────────────────────────────────────────────────────────────────────────
# 이 스크립트는 다음 작업을 자동으로 수행합니다:
#   1. Windows / Claude Desktop / Python / git 환경 점검
#   2. uv 자동 설치 (이미 있으면 건너뜀)
#   3. PLUUUG_API_KEY / PLUUUG_SECRET_KEY 대화형 입력
#   4. %APPDATA%\Claude\claude_desktop_config.json 백업 + 'pluuug' 서버 등록
#   5. wrapper 받아오기 + 동작 검증
#   6. Claude Desktop 재기동 안내 (수동)
#
# 사용:
#   irm https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.ps1 | iex
#
# 검증 후 실행을 원한다면:
#   iwr https://raw.githubusercontent.com/postoo-io/pluuug-openapi-mcp/main/scripts/install.ps1 -OutFile install.ps1
#   Get-FileHash -Algorithm SHA256 install.ps1   # 게시된 hash와 대조
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# 소스: https://github.com/postoo-io/pluuug-openapi-mcp/blob/main/scripts/install.ps1
# ─────────────────────────────────────────────────────────────────────────────

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ── 설정 ─────────────────────────────────────────────────────────────────────
$RepoUrl = 'git+https://github.com/postoo-io/pluuug-openapi-mcp.git'
$Cfg = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
$ServerName = 'pluuug'

# ── 출력 헬퍼 ────────────────────────────────────────────────────────────────
function Write-Step { param([int]$N, [string]$Title)
    Write-Host ''
    Write-Host ("[{0}/6] {1}" -f $N, $Title) -ForegroundColor Cyan
}
function Write-Info { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor DarkGray }
function Write-Ok   { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-WarnLine { param([string]$Msg) Write-Host "  ! $Msg" -ForegroundColor Yellow }
function Write-Fail {
    param([string]$Msg)
    foreach ($line in ($Msg -split "`n")) {
        Write-Host "  ✗ $line" -ForegroundColor Red
    }
    exit 1
}

# ── 시작 배너 ────────────────────────────────────────────────────────────────
Write-Host ('━' * 46) -ForegroundColor White
Write-Host '     pluuug MCP installer  (Windows)' -ForegroundColor White
Write-Host ('━' * 46) -ForegroundColor White
Write-Host 'Claude Desktop에 pluuug MCP 서버를 등록합니다.' -ForegroundColor DarkGray

# ── [1/6] OS + Claude Desktop + Python + git ────────────────────────────────
Write-Step 1 '환경 점검'

# OS 확인 — PS 7+의 $IsWindows + PS 5.1의 $env:OS 둘 다 호환
$onWindows = $false
if (Get-Variable -Name 'IsWindows' -Scope Global -ErrorAction SilentlyContinue) {
    $onWindows = $IsWindows
} elseif ($env:OS -eq 'Windows_NT') {
    $onWindows = $true
}
if (-not $onWindows) {
    Write-Fail "현재 Windows만 지원합니다. (macOS는 install.sh 사용)"
}
Write-Ok 'Windows 확인'

# Claude Desktop 설치 경로 후보 — Windows 빌드/버전마다 다를 수 있어 모두 확인
$claudePaths = @(
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
    (Join-Path ${env:ProgramFiles} 'Claude\Claude.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Claude\Claude.exe')
)
$claudeFound = $false
foreach ($p in $claudePaths) {
    if ($p -and (Test-Path $p)) { $claudeFound = $true; break }
}
if (-not $claudeFound) {
    Write-Fail "Claude Desktop이 설치돼 있지 않습니다.`n먼저 https://claude.ai/download 에서 다운로드/설치하세요."
}
Write-Ok 'Claude Desktop 확인'

# Python 검증 — py, python, python3 차례로 실 실행
$script:PythonCmd = $null
foreach ($cmd in @('py', 'python', 'python3')) {
    try {
        $out = & $cmd -c "import json; print('ok')" 2>$null
        if ($out -eq 'ok') { $script:PythonCmd = $cmd; break }
    } catch { }
}
if (-not $script:PythonCmd) {
    Write-Fail @"
Python이 설치돼 있지 않습니다.
https://www.python.org/downloads/ 에서 Python 3.10+ 설치 후 다시 실행하세요.
설치 시 'Add Python to PATH' 체크박스를 반드시 켜주세요.
"@
}
$pyVer = & $script:PythonCmd --version 2>&1
Write-Ok "Python 확인 ($pyVer, command: $($script:PythonCmd))"

# git 검증
try {
    $gitVer = git --version 2>$null
    if (-not $gitVer) { throw 'git missing' }
    Write-Ok "git 확인 ($gitVer)"
} catch {
    Write-Fail @"
git이 설치돼 있지 않습니다.
https://git-scm.com/download/win 에서 Git for Windows 설치 후 다시 실행하세요.
"@
}

# ── [2/6] uv ─────────────────────────────────────────────────────────────────
Write-Step 2 'uv 확인'
if (Get-Command uv -ErrorAction SilentlyContinue) {
    $uvVer = (uv --version 2>&1 | Select-Object -First 1)
    Write-Ok "uv 이미 설치됨 ($uvVer)"
} else {
    Write-Info 'uv가 없습니다. 자동 설치합니다... (astral.sh/uv 공식 스크립트)'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression

    # uv 공식 installer는 $env:USERPROFILE\.local\bin 또는 $env:USERPROFILE\.cargo\bin에 둠
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"

    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Fail '새 PowerShell 창을 열고 다시 시도하세요 (PATH 적용 필요).'
    }
    Write-Ok "uv 설치 완료 ($(uv --version 2>&1 | Select-Object -First 1))"
}

# ── [3/6] 키 입력 ────────────────────────────────────────────────────────────
Write-Step 3 'API Key 입력'
Write-Info 'pluuug 어드민에서 발급받은 키 2개를 입력하세요.'
Write-Info 'Secret Key는 보안상 입력이 화면에 표시되지 않습니다.'

$ApiKey = Read-Host '  PLUUUG_API_KEY'
if ([string]::IsNullOrWhiteSpace($ApiKey)) { Write-Fail 'API Key가 비어있습니다.' }

$SecretSecure = Read-Host '  PLUUUG_SECRET_KEY (입력 안 보임)' -AsSecureString
$SecretKey = [System.Net.NetworkCredential]::new('', $SecretSecure).Password
if ([string]::IsNullOrWhiteSpace($SecretKey)) { Write-Fail 'Secret Key가 비어있습니다.' }
Write-Ok '키 입력 완료'

# ── [4/6] config 백업 + 병합 ─────────────────────────────────────────────────
Write-Step 4 'Claude Desktop 설정 업데이트'
$cfgDir = Split-Path $Cfg -Parent
if (-not (Test-Path $cfgDir)) {
    New-Item -ItemType Directory -Path $cfgDir | Out-Null
}

# 환경변수로 Python heredoc에 전달 (셸 quoting 회피)
$env:_PLUUUG_CFG = $Cfg
$env:_PLUUUG_SERVER = $ServerName

# 기존 pluuug 서버 등록 여부 검사
$Exists = & $script:PythonCmd -c @"
import json, os, pathlib
p = pathlib.Path(os.environ['_PLUUUG_CFG'])
if not p.exists():
    print('no_file'); raise SystemExit
try:
    d = json.loads(p.read_text(encoding='utf-8'))
except Exception:
    print('invalid'); raise SystemExit
servers = (d.get('mcpServers') or {}) if isinstance(d.get('mcpServers'), dict) else {}
print('exists' if os.environ['_PLUUUG_SERVER'] in servers else 'absent')
"@ 2>$null

switch ($Exists) {
    'invalid' {
        Write-Fail "기존 config가 유효한 JSON이 아닙니다: $Cfg`n먼저 수동 정리하거나 백업 후 삭제하세요."
    }
    'no_file' { }
    'absent'  { }
    'exists'  {
        Write-WarnLine "이미 '$ServerName' 서버가 등록돼 있습니다."
        $answer = Read-Host '  덮어쓸까요? (기존 설정은 자동 백업됩니다) [y/N]'
        if ($answer -notmatch '^[yY]') { Write-Fail '취소되었습니다.' }
    }
    default {
        # Python 호출이 비정상 종료되어 EXISTS가 비어있거나 예상 외 값.
        # [1/6]의 실 실행 검증으로 거의 잡히지만 race 대비 default.
        Write-Fail "config 상태 확인 실패 (응답: '$Exists')`nPython이 정상 동작하는지 확인 후 다시 시도하세요."
    }
}

if (Test-Path $Cfg) {
    $backup = "$Cfg.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $Cfg $backup
    Write-Ok "기존 config 백업: $(Split-Path $backup -Leaf)"
}

# JSON 안전 병합 (다른 MCP 서버는 보존)
$env:_PLUUUG_API_KEY = $ApiKey
$env:_PLUUUG_SECRET_KEY = $SecretKey
$env:_PLUUUG_REPO_URL = $RepoUrl
try {
    & $script:PythonCmd -c @"
import json, os, pathlib
p = pathlib.Path(os.environ['_PLUUUG_CFG'])
d = json.loads(p.read_text(encoding='utf-8')) if p.exists() else {}
if not isinstance(d.get('mcpServers'), dict):
    d['mcpServers'] = {}
d['mcpServers'][os.environ['_PLUUUG_SERVER']] = {
    'command': 'uvx',
    'args': ['--from', os.environ['_PLUUUG_REPO_URL'], 'pluuug-openapi-mcp'],
    'env': {
        'PLUUUG_API_KEY':    os.environ['_PLUUUG_API_KEY'],
        'PLUUUG_SECRET_KEY': os.environ['_PLUUUG_SECRET_KEY'],
    },
}
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"@
} finally {
    # 환경변수 정리 (secret이 자식 프로세스로 새지 않도록)
    Remove-Item Env:\_PLUUUG_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\_PLUUUG_SECRET_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\_PLUUUG_REPO_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\_PLUUUG_CFG -ErrorAction SilentlyContinue
    Remove-Item Env:\_PLUUUG_SERVER -ErrorAction SilentlyContinue
}
Write-Ok "'$ServerName' 서버 등록 완료"

# ── [5/6] wrapper 받아오기 + 동작 검증 ───────────────────────────────────────
Write-Step 5 'wrapper 받아오기 (20~40초 소요)'
Write-Info 'git에서 wrapper를 받고 Python 의존성을 설치합니다. 잠시만 기다려주세요...'
$dryRun = (& uvx --from $RepoUrl pluuug-openapi-mcp --help 2>$null; $LASTEXITCODE)
if ($LASTEXITCODE -eq 0) {
    Write-Ok 'wrapper 정상 동작'
} else {
    Write-Fail @"
wrapper 실행 실패. 네트워크 또는 Python 환경을 확인하세요.
문제 지속 시: https://github.com/postoo-io/pluuug-openapi-mcp/issues
"@
}

# ── [6/6] 재기동 안내 ────────────────────────────────────────────────────────
Write-Step 6 'Claude Desktop 재기동'

Write-Host ''
Write-Host '✓ 설치 완료!' -ForegroundColor Green
Write-Host ''
Write-Host '이제 Claude Desktop을 완전히 재기동하세요:' -ForegroundColor White
Write-Host ''
Write-Host '  1) ' -NoNewline; Write-Host '작업 표시줄 우측 시스템 트레이' -NoNewline -ForegroundColor White; Write-Host '의 ' -NoNewline; Write-Host '^ 아이콘' -NoNewline -ForegroundColor White; Write-Host ' 클릭 →'
Write-Host '     Claude 아이콘 우클릭 → ' -NoNewline; Write-Host '[Quit / 종료]' -ForegroundColor White
Write-Host '     ⚠ 창의 X 버튼만 누르면 안 됩니다 — 트레이에 살아있으면 적용 안 됨.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  2) 시작 메뉴 또는 바탕화면에서 ' -NoNewline; Write-Host 'Claude 다시 실행' -ForegroundColor White
Write-Host ''
Write-Host '  3) 새 대화창에서 다음과 같이 입력해보세요:'
Write-Host '     "pluuug에서 최근 의뢰 5건 보여줘"' -ForegroundColor Cyan
Write-Host ''
Write-Host '문제가 있다면: https://docs.openapi.pluuug.com/integrations/mcp' -ForegroundColor DarkGray
Write-Host ''
