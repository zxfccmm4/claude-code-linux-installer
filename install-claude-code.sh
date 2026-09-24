#!/usr/bin/env bash
# Claude Code Linux 一键安装与自定义 API 配置脚本
# 默认使用 npm 安装；也可使用 Anthropic 官方原生安装器。
set -Eeuo pipefail

PROGRAM_NAME="$(basename "$0")"
NATIVE_INSTALL_URL="https://claude.ai/install.sh"
NODE_MAJOR_REQUIRED=22

BASE_URL="${CLAUDE_BASE_URL:-${ANTHROPIC_BASE_URL:-}}"
AUTH_MODE="${CLAUDE_AUTH_MODE:-auth-token}"
API_SECRET="${CLAUDE_API_KEY:-}"
MODEL="${CLAUDE_MODEL:-${ANTHROPIC_MODEL:-}}"
INSTALL_METHOD="${CLAUDE_INSTALL_METHOD:-npm}"
VERSION="${CLAUDE_VERSION:-latest}"
CONFIG_MODE="${CLAUDE_CONFIG_MODE:-shell}"

AUTH_MODE_EXPLICIT=0
[[ -z "${CLAUDE_AUTH_MODE:-}" ]] || AUTH_MODE_EXPLICIT=1
NON_INTERACTIVE=0
SKIP_NODE=0
SKIP_INSTALL=0
FORCE_INSTALL=0
DRY_RUN=0

log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
用法：
  bash install-claude-code.sh [选项]

选项：
  --base-url URL              自定义 Anthropic Messages API 兼容地址
  --api-key KEY               API Key/Token（也可使用 --token）
  --token TOKEN               --api-key 的别名
  --auth-mode MODE            auth-token 或 api-key，默认 auth-token
                              auth-token -> Authorization: Bearer TOKEN
                              api-key    -> X-Api-Key: KEY
  --model MODEL               可选，设置 ANTHROPIC_MODEL
  --install-method METHOD     npm 或 native，默认 npm
  --version VERSION           npm: latest 或具体版本；native: latest/stable/具体版本
  --config-mode MODE          shell 或 settings，默认 shell
                              shell: 安全写入独立 env 文件，由 bash/zsh 配置加载
                              settings: 合并到 ~/.claude/settings.json
  --skip-node                 不检测/安装 Node.js（仅 npm 安装模式有效）
  --skip-install              不安装 Claude Code，只更新 API 配置
  --force-install             即使检测到 Claude Code，也备份旧入口并重新安装
  --non-interactive           非交互模式，缺少 Base URL/Token 时直接报错
  --dry-run                   只显示操作，不安装或写文件
  -h, --help                  显示帮助

交互式：
  bash install-claude-code.sh

非交互式：
  bash install-claude-code.sh \
    --base-url "https://gateway.example.com" \
    --token "sk-xxxx" \
    --auth-mode auth-token \
    --non-interactive

也可用环境变量：
  CLAUDE_BASE_URL="https://gateway.example.com" \
  CLAUDE_API_KEY="sk-xxxx" \
  CLAUDE_AUTH_MODE="auth-token" \
  bash install-claude-code.sh --non-interactive
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      [[ $# -ge 2 ]] || die "--base-url 缺少参数"
      BASE_URL="$2"; shift 2 ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    --api-key|--token)
      [[ $# -ge 2 ]] || die "$1 缺少参数"
      API_SECRET="$2"; shift 2 ;;
    --api-key=*|--token=*) API_SECRET="${1#*=}"; shift ;;
    --auth-mode)
      [[ $# -ge 2 ]] || die "--auth-mode 缺少参数"
      AUTH_MODE="$2"; AUTH_MODE_EXPLICIT=1; shift 2 ;;
    --auth-mode=*) AUTH_MODE="${1#*=}"; AUTH_MODE_EXPLICIT=1; shift ;;
    --model)
      [[ $# -ge 2 ]] || die "--model 缺少参数"
      MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#*=}"; shift ;;
    --install-method)
      [[ $# -ge 2 ]] || die "--install-method 缺少参数"
      INSTALL_METHOD="$2"; shift 2 ;;
    --install-method=*) INSTALL_METHOD="${1#*=}"; shift ;;
    --version|--channel)
      [[ $# -ge 2 ]] || die "$1 缺少参数"
      VERSION="$2"; shift 2 ;;
    --version=*|--channel=*) VERSION="${1#*=}"; shift ;;
    --config-mode)
      [[ $# -ge 2 ]] || die "--config-mode 缺少参数"
      CONFIG_MODE="$2"; shift 2 ;;
    --config-mode=*) CONFIG_MODE="${1#*=}"; shift ;;
    --skip-node) SKIP_NODE=1; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --force-install) FORCE_INSTALL=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（使用 --help 查看帮助）" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "此脚本仅适用于 Linux/WSL。"
case "$(uname -m)" in
  x86_64|amd64|aarch64|arm64) ;;
  *) die "不支持的 CPU 架构：$(uname -m)；仅支持 x64 和 ARM64。" ;;
esac

case "$AUTH_MODE" in
  auth-token|api-key) ;;
  *) die "--auth-mode 只能是 auth-token 或 api-key" ;;
esac
case "$INSTALL_METHOD" in
  npm|native) ;;
  *) die "--install-method 只能是 npm 或 native" ;;
esac
case "$CONFIG_MODE" in
  shell|settings) ;;
  *) die "--config-mode 只能是 shell 或 settings" ;;
esac
[[ "$VERSION" =~ ^(latest|stable|[0-9]+\.[0-9]+\.[0-9]+)$ ]] || \
  die "--version 必须是 latest、stable 或具体版本号（例如 2.1.198）"
if [[ "$INSTALL_METHOD" == "npm" && "$VERSION" == "stable" ]]; then
  die "npm 安装模式不使用 stable 频道；请改用 --version latest/具体版本，或 --install-method native。"
fi

# 命令行参数解析完毕后，再按最终认证方式读取对应的官方环境变量。
if [[ -z "$API_SECRET" ]]; then
  if [[ "$AUTH_MODE" == "api-key" ]]; then
    API_SECRET="${ANTHROPIC_API_KEY:-}"
  else
    API_SECRET="${ANTHROPIC_AUTH_TOKEN:-}"
  fi
fi

prompt_read() {
  local target_var="$1"
  local prompt="$2"
  local silent="${3:-0}"
  local value=""

  # curl ... | bash 会占用标准输入来读取脚本本身，因此交互输入必须从控制终端读取。
  # 没有控制终端时，要求调用方改用非交互参数，避免误把后续脚本源码当成答案。
  if [[ ! -r /dev/tty ]]; then
    die "当前没有可用的交互终端；请使用 --non-interactive，并传入 --base-url 和 --token/--api-key。"
  fi
  if [[ "$silent" == "1" ]]; then
    if ! IFS= read -r -s -p "$prompt" value </dev/tty; then
      die "无法从终端读取输入；请改用 --non-interactive。"
    fi
  else
    if ! IFS= read -r -p "$prompt" value </dev/tty; then
      die "无法从终端读取输入；请改用 --non-interactive。"
    fi
  fi
  printf -v "$target_var" '%s' "$value"
}

if [[ $NON_INTERACTIVE -eq 0 ]]; then
  printf '\nClaude Code Linux 一键安装/配置\n'
  printf '%s\n' '--------------------------------'

  if [[ -z "$BASE_URL" ]]; then
    prompt_read BASE_URL "Base URL（例如 https://gateway.example.com）: "
  fi
  if [[ -z "$API_SECRET" ]]; then
    prompt_read API_SECRET "API Key/Token（输入不会显示）: " 1
    printf '\n'
  fi
  if [[ $AUTH_MODE_EXPLICIT -eq 0 ]]; then
    printf '认证方式：\n'
    printf '  1) auth-token -> Authorization: Bearer（代理网关常用，默认）\n'
    printf '  2) api-key    -> X-Api-Key（Anthropic 官方 API 常用）\n'
    auth_choice=""
    prompt_read auth_choice "请选择 [1]: "
    case "${auth_choice:-1}" in
      1) AUTH_MODE="auth-token" ;;
      2) AUTH_MODE="api-key" ;;
      *) die "无效选择：$auth_choice" ;;
    esac
  fi
  if [[ -z "$MODEL" ]]; then
    prompt_read MODEL "默认模型（可留空）: "
  fi
fi

[[ -n "$BASE_URL" ]] || die "缺少 Base URL；请使用 --base-url 或 CLAUDE_BASE_URL。"
[[ "$BASE_URL" =~ ^https?://[^[:space:]]+$ ]] || die "Base URL 必须以 http:// 或 https:// 开头，且不能包含空格。"
BASE_URL="${BASE_URL%/}"
[[ -n "$API_SECRET" ]] || die "缺少 API Key/Token；请使用 --token/--api-key 或 CLAUDE_API_KEY。"
if [[ "$BASE_URL" != https://* ]]; then
  warn "当前 Base URL 使用明文 HTTP；生产环境请改用 HTTPS。"
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    die "此操作需要 root 权限，但系统没有 sudo；请用 root 运行或先安装依赖。"
  fi
}

install_curl_if_needed() {
  command -v curl >/dev/null 2>&1 && return 0
  log "未检测到 curl，正在安装……"
  if command -v apt-get >/dev/null 2>&1; then
    as_root apt-get update
    as_root apt-get install -y curl ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y curl ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    as_root yum install -y curl ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    as_root apk add --no-cache curl ca-certificates
  elif command -v pacman >/dev/null 2>&1; then
    as_root pacman -Sy --noconfirm curl ca-certificates
  elif command -v zypper >/dev/null 2>&1; then
    as_root zypper --non-interactive install curl ca-certificates
  else
    die "无法识别包管理器；请先手动安装 curl 和 ca-certificates。"
  fi
}

node_major() {
  command -v node >/dev/null 2>&1 || return 1
  node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

node_is_compatible() {
  major="$(node_major 2>/dev/null || true)"
  [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge "$NODE_MAJOR_REQUIRED" ]]
}

install_node() {
  if node_is_compatible; then
    ok "已检测到 Node.js $(node --version)，跳过安装。"
    command -v npm >/dev/null 2>&1 || die "已找到 Node.js，但没有 npm；请先安装 npm。"
    return 0
  fi

  old_node="$(node --version 2>/dev/null || printf '未安装')"
  log "当前 Node.js：${old_node}；npm 版 Claude Code 当前要求 Node.js >= ${NODE_MAJOR_REQUIRED}。"
  install_curl_if_needed

  if command -v apt-get >/dev/null 2>&1; then
    setup_url="https://deb.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x"
    setup_file="$(mktemp)"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '[DRY-RUN] curl -fsSL %q -o <临时文件>\n' "$setup_url"
      printf '[DRY-RUN] sudo bash <临时文件>\n'
      printf '[DRY-RUN] sudo apt-get install -y nodejs\n'
      rm -f "$setup_file"
      return 0
    fi
    curl --proto '=https' --tlsv1.2 -fsSL "$setup_url" -o "$setup_file"
    as_root bash "$setup_file"
    rm -f "$setup_file"
    as_root apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    setup_url="https://rpm.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x"
    setup_file="$(mktemp)"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '[DRY-RUN] curl -fsSL %q -o <临时文件>\n' "$setup_url"
      printf '[DRY-RUN] sudo bash <临时文件>\n'
      printf '[DRY-RUN] sudo %s install -y nodejs\n' "$(command -v dnf >/dev/null 2>&1 && printf dnf || printf yum)"
      rm -f "$setup_file"
      return 0
    fi
    curl --proto '=https' --tlsv1.2 -fsSL "$setup_url" -o "$setup_file"
    as_root bash "$setup_file"
    rm -f "$setup_file"
    if command -v dnf >/dev/null 2>&1; then as_root dnf install -y nodejs; else as_root yum install -y nodejs; fi
  elif command -v apk >/dev/null 2>&1; then
    as_root apk add --no-cache nodejs npm
  elif command -v pacman >/dev/null 2>&1; then
    as_root pacman -Sy --noconfirm nodejs npm
  else
    die "无法自动安装 Node.js。请手动安装 Node.js >= ${NODE_MAJOR_REQUIRED} 和 npm 后重试，或使用 --install-method native。"
  fi

  [[ $DRY_RUN -eq 1 ]] && return 0
  hash -r
  node_is_compatible || die "Node.js 安装后版本仍低于 ${NODE_MAJOR_REQUIRED}：$(node --version 2>/dev/null || printf '未找到')。"
  command -v npm >/dev/null 2>&1 || die "Node.js 已安装，但未找到 npm。"
  ok "Node.js 已就绪：$(node --version)；npm $(npm --version)。"
}

shell_quote() {
  # POSIX shell 安全单引号：abc'def -> 'abc'\''def'
  value="$1"
  printf "'"
  while [[ "$value" == *"'"* ]]; do
    head="${value%%\'*}"
    printf "%s'\\\\''" "$head"
    value="${value#*\'}"
  done
  printf "%s'" "$value"
}

ensure_local_bin_path() {
  bin_dir="$HOME/.local/bin"
  marker="# Claude Code PATH (managed by $PROGRAM_NAME)"
  mkdir_cmd=(mkdir -p "$bin_dir")
  run "${mkdir_cmd[@]}"

  case ":$PATH:" in
    *":$bin_dir:"*) return 0 ;;
  esac

  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [[ $DRY_RUN -eq 1 ]]; then
      log "将把 $bin_dir 加入 $profile 的 PATH。"
    else
      touch "$profile"
      if ! grep -Fq "$marker" "$profile" 2>/dev/null; then
        {
          printf '\n%s\n' "$marker"
          # shellcheck disable=SC2016  # 保留字面量 $PATH，供新 shell 展开。
          printf 'export PATH=%s:"$PATH"\n' "$(shell_quote "$bin_dir")"
        } >> "$profile"
      fi
    fi
  done
  export PATH="$bin_dir:$PATH"
}

install_claude_npm() {
  ensure_local_bin_path

  local_claude="$HOME/.local/bin/claude"
  existing_claude=""
  if [[ -x "$local_claude" ]]; then
    existing_claude="$local_claude"
  elif command -v claude >/dev/null 2>&1; then
    existing_claude="$(command -v claude)"
  fi

  if [[ -n "$existing_claude" && $FORCE_INSTALL -eq 0 ]]; then
    if existing_version="$($existing_claude --version 2>/dev/null)"; then
      ok "已检测到 Claude Code ${existing_version:-$existing_claude}，跳过重复安装。"
      log "如需强制更新/重装，请重新运行并添加 --force-install。"
      return 0
    fi
    warn "检测到无法正常运行的 Claude Code 入口：$existing_claude；将继续安装。"
  fi

  [[ $SKIP_NODE -eq 1 ]] || install_node
  if [[ $DRY_RUN -eq 0 ]]; then
    command -v node >/dev/null 2>&1 || die "未找到 Node.js；请取消 --skip-node 或先手动安装。"
    command -v npm >/dev/null 2>&1 || die "未找到 npm；请取消 --skip-node 或先手动安装。"
  fi

  # npm 遇到原生安装器或旧安装遗留的同名入口时会报 EEXIST。
  # 不直接删除用户文件，而是先备份，便于需要时恢复。
  if [[ -e "$local_claude" || -L "$local_claude" ]]; then
    backup_path="${local_claude}.backup.$(date +%Y%m%d-%H%M%S).$$"
    warn "发现冲突入口 $local_claude，将备份为 $backup_path。"
    run mv "$local_claude" "$backup_path"
  fi

  package="@anthropic-ai/claude-code@$VERSION"
  log "正在通过 npm 安装 ${package}……"
  run npm install --global --prefix "$HOME/.local" "$package"
}

install_claude_native() {
  install_curl_if_needed
  log "正在通过 Anthropic 官方原生安装器安装 Claude Code（${VERSION}）……"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[DRY-RUN] curl -fsSL %q -o <临时文件>\n' "$NATIVE_INSTALL_URL"
    printf '[DRY-RUN] bash <临时文件> %q\n' "$VERSION"
    return 0
  fi
  temp_dir="$(mktemp -d)"
  installer="$temp_dir/claude-install.sh"
  curl --proto '=https' --tlsv1.2 -fsSL "$NATIVE_INSTALL_URL" -o "$installer"
  [[ -s "$installer" ]] || { rm -rf "$temp_dir"; die "官方安装脚本下载失败或内容为空。"; }
  bash "$installer" "$VERSION"
  rm -rf "$temp_dir"
}

write_shell_config() {
  config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code"
  env_file="$config_dir/env"
  marker="# Claude Code custom API (managed by $PROGRAM_NAME)"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "将写入 ${env_file}，并让 ~/.bashrc、~/.bash_profile、~/.zshrc 加载它。"
    return 0
  fi

  mkdir -p "$config_dir"
  chmod 700 "$config_dir"
  umask 077
  {
    printf '%s\n' "$marker"
    # 让“source env”同时刷新 Claude Code 的用户级安装路径，避免当前 shell 找不到命令。
    # shellcheck disable=SC2016  # 变量需保留到用户 source 配置时再展开。
    printf '%s\n' 'case ":${PATH:-}:" in' '  *:"$HOME/.local/bin":*) ;;' '  *) export PATH="$HOME/.local/bin:${PATH:-}" ;;' 'esac'
    printf 'export ANTHROPIC_BASE_URL=%s\n' "$(shell_quote "$BASE_URL")"
    if [[ "$AUTH_MODE" == "auth-token" ]]; then
      printf 'export ANTHROPIC_AUTH_TOKEN=%s\n' "$(shell_quote "$API_SECRET")"
      printf 'unset ANTHROPIC_API_KEY\n'
    else
      printf 'export ANTHROPIC_API_KEY=%s\n' "$(shell_quote "$API_SECRET")"
      printf 'unset ANTHROPIC_AUTH_TOKEN\n'
    fi
    if [[ -n "$MODEL" ]]; then
      printf 'export ANTHROPIC_MODEL=%s\n' "$(shell_quote "$MODEL")"
    else
      printf 'unset ANTHROPIC_MODEL\n'
    fi
  } > "$env_file"
  chmod 600 "$env_file"

  for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    touch "$profile"
    if ! grep -Fq "$marker" "$profile" 2>/dev/null; then
      {
        printf '\n%s\n' "$marker"
        printf '[ -f %s ] && . %s\n' "$(shell_quote "$env_file")" "$(shell_quote "$env_file")"
      } >> "$profile"
    fi
  done
  ok "API 配置已保存到 ${env_file}（权限 600），并已接入 bash/zsh。"
}

write_settings_config() {
  settings_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  settings_file="$settings_dir/settings.json"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "将合并配置到 ${settings_file}，并将权限设为 600。"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    warn "未找到 python3，无法安全合并 JSON；自动改用 shell 配置。"
    write_shell_config
    return 0
  fi

  mkdir -p "$settings_dir"
  chmod 700 "$settings_dir" 2>/dev/null || true
  umask 077
  CLAUDE_CFG_BASE_URL="$BASE_URL" \
  CLAUDE_CFG_SECRET="$API_SECRET" \
  CLAUDE_CFG_AUTH_MODE="$AUTH_MODE" \
  CLAUDE_CFG_MODEL="$MODEL" \
  python3 - "$settings_file" <<'PY'
import json
import os
import pathlib
import sys
import tempfile

path = pathlib.Path(sys.argv[1]).expanduser()
if path.exists() and path.stat().st_size:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"现有配置不是有效 JSON，未做修改：{path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"现有配置根节点不是 JSON 对象，未做修改：{path}")
else:
    data = {}

env = data.setdefault("env", {})
if not isinstance(env, dict):
    raise SystemExit(f"现有配置中的 env 不是 JSON 对象，未做修改：{path}")
env["ANTHROPIC_BASE_URL"] = os.environ["CLAUDE_CFG_BASE_URL"]
secret = os.environ["CLAUDE_CFG_SECRET"]
if os.environ["CLAUDE_CFG_AUTH_MODE"] == "auth-token":
    env["ANTHROPIC_AUTH_TOKEN"] = secret
    env.pop("ANTHROPIC_API_KEY", None)
else:
    env["ANTHROPIC_API_KEY"] = secret
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
model = os.environ.get("CLAUDE_CFG_MODEL", "")
if model:
    env["ANTHROPIC_MODEL"] = model
else:
    env.pop("ANTHROPIC_MODEL", None)

path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix="settings.", suffix=".json", dir=str(path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    os.chmod(path, 0o600)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
  ok "API 配置已合并到 ${settings_file}（权限 600）。"
}

mark_onboarding_complete() {
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    state_file="${CLAUDE_CONFIG_DIR}/.claude.json"
  else
    state_file="$HOME/.claude.json"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "将把 hasCompletedOnboarding=true 安全合并到 ${state_file}，以便自定义 API 首次启动时跳过账户登录页。"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    CLAUDE_STATE_FILE="$state_file" python3 - <<'PY_STATE'
import json
import os
import pathlib
import tempfile

path = pathlib.Path(os.environ["CLAUDE_STATE_FILE"]).expanduser()
if path.exists() and path.stat().st_size:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"现有 Claude 状态文件不是有效 JSON，未做修改：{path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"现有 Claude 状态文件根节点不是 JSON 对象，未做修改：{path}")
else:
    data = {}

data["hasCompletedOnboarding"] = True
path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".claude-state.", suffix=".json", dir=str(path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    os.chmod(path, 0o600)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY_STATE
    ok "已标记 Claude Code 首次引导完成：${state_file}。"
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    CLAUDE_STATE_FILE="$state_file" node <<'NODE_STATE'
const fs = require('fs');
const path = require('path');
const target = process.env.CLAUDE_STATE_FILE;
let data = {};
if (fs.existsSync(target) && fs.statSync(target).size > 0) {
  data = JSON.parse(fs.readFileSync(target, 'utf8'));
  if (!data || Array.isArray(data) || typeof data !== 'object') {
    throw new Error(`现有 Claude 状态文件根节点不是 JSON 对象：${target}`);
  }
}
data.hasCompletedOnboarding = true;
fs.mkdirSync(path.dirname(target), { recursive: true });
const tmp = `${target}.tmp.${process.pid}`;
fs.writeFileSync(tmp, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(tmp, target);
fs.chmodSync(target, 0o600);
NODE_STATE
    ok "已标记 Claude Code 首次引导完成：${state_file}。"
    return 0
  fi

  if [[ ! -e "$state_file" ]]; then
    umask 077
    printf '{\n  "hasCompletedOnboarding": true\n}\n' > "$state_file"
    chmod 600 "$state_file"
    ok "已创建 Claude Code 首次引导状态：${state_file}。"
  else
    warn "缺少 python3/node，无法安全合并 ${state_file}；首次启动时可能仍显示账户登录页。"
  fi
}

if [[ $SKIP_INSTALL -eq 0 ]]; then
  if [[ "$INSTALL_METHOD" == "npm" ]]; then
    install_claude_npm
  else
    install_claude_native
    ensure_local_bin_path
  fi
else
  log "已跳过 Claude Code 安装。"
fi

if [[ "$CONFIG_MODE" == "shell" ]]; then
  write_shell_config
else
  write_settings_config
fi
mark_onboarding_complete

if [[ $DRY_RUN -eq 0 ]]; then
  claude_bin="$(command -v claude 2>/dev/null || true)"
  if [[ -z "$claude_bin" && -x "$HOME/.local/bin/claude" ]]; then
    claude_bin="$HOME/.local/bin/claude"
  fi
  printf '\n'
  if [[ -n "$claude_bin" ]]; then
    version_output="$($claude_bin --version 2>/dev/null || true)"
    ok "Claude Code 已就绪：${version_output:-$claude_bin}"
  elif [[ $SKIP_INSTALL -eq 0 ]]; then
    warn "安装已执行，但当前 shell 未找到 claude；请打开新终端后运行 claude --version。"
  fi
  printf '立即在当前终端生效：\n'
  if [[ "$CONFIG_MODE" == "shell" ]]; then
    printf '  source %q\n' "${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/env"
  fi
  printf '然后进入项目并运行：\n  cd your-project-folder\n  claude\n'
else
  ok "Dry-run 完成，未修改系统。"
fi
