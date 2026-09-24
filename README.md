# Claude Code Linux 一键安装脚本

此脚本会在 Linux/WSL 上完成：

1. 检查 Node.js；已满足版本要求时自动跳过。
2. Node.js 不存在或版本过低时，在 Debian/Ubuntu、RHEL/Fedora、Alpine、Arch 等系统上尝试自动安装。
3. 使用 npm 安装 Claude Code：`@anthropic-ai/claude-code`。
4. 配置自定义 `ANTHROPIC_BASE_URL` 和 API Key/Token。
5. 将配置接入 `~/.bashrc`、`~/.bash_profile` 和 `~/.zshrc`。

> 截至 2026-09-24，Claude Code 官方 npm 安装文档要求 Node.js 22 或更高。因此脚本检查 **Node.js >= 22**，而不是旧教程中的 >= 18。官方同时更推荐无需 Node.js 的原生安装方式，本脚本也提供 `--install-method native`。

## 一行命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/zxfccmm4/claude-code-linux-installer/main/install-claude-code.sh | bash
```

如果需要传入自定义 Base URL 和 Token，建议先下载再运行，以免密钥出现在命令历史或进程参数中。

## 下载后直接运行

```bash
curl -fLo install-claude-code.sh \
  https://raw.githubusercontent.com/zxfccmm4/claude-code-linux-installer/main/install-claude-code.sh
chmod +x install-claude-code.sh
./install-claude-code.sh
```

脚本会交互询问 Base URL、Token 和认证方式；Token 输入不会回显。

## 非交互安装

适合你给出的 `ANTHROPIC_AUTH_TOKEN + ANTHROPIC_BASE_URL` 用法：

```bash
./install-claude-code.sh \
  --base-url "https://anyrouter.top" \
  --token "sk-xxxx" \
  --auth-mode auth-token \
  --non-interactive
```

为避免 Token 进入 shell 历史，推荐通过环境变量传入：

```bash
CLAUDE_BASE_URL="https://anyrouter.top" \
CLAUDE_API_KEY="sk-xxxx" \
CLAUDE_AUTH_MODE="auth-token" \
./install-claude-code.sh --non-interactive
```

## 认证方式

| 参数 | Claude Code 环境变量 | HTTP 认证形式 | 适用场景 |
|---|---|---|---|
| `--auth-mode auth-token` | `ANTHROPIC_AUTH_TOKEN` | `Authorization: Bearer ...` | 许多代理/中转网关；脚本默认值 |
| `--auth-mode api-key` | `ANTHROPIC_API_KEY` | `X-Api-Key: ...` | Anthropic 官方 API 或要求该请求头的兼容服务 |

请以服务商文档为准。自定义 Base URL 必须兼容 Anthropic Messages API；仅兼容 OpenAI API 并不代表可直接用于 Claude Code。

## 配置保存方式

默认把密钥只保存一份到：

```text
~/.config/claude-code/env
```

权限设为 `600`，然后在以下文件中追加加载语句，而不是把密钥重复写三遍：

```text
~/.bashrc
~/.bash_profile
~/.zshrc
```

安装完成后，可立即执行：

```bash
source ~/.config/claude-code/env
cd your-project-folder
claude
```

也可写入 Claude Code 配置：

```bash
./install-claude-code.sh --config-mode settings
```

这会安全合并到 `~/.claude/settings.json`，不会覆盖已有其他设置。

## 使用官方原生安装器（推荐）

原生安装无需 Node.js：

```bash
./install-claude-code.sh \
  --install-method native \
  --base-url "https://anyrouter.top" \
  --token "sk-xxxx"
```

## 只更新 API 配置

```bash
./install-claude-code.sh \
  --skip-install \
  --base-url "https://anyrouter.top" \
  --token "sk-new" \
  --auth-mode auth-token \
  --non-interactive
```

## 验证

```bash
node --version       # npm 安装模式应为 v22 或更高
claude --version
claude doctor
```

## 常用参数

```text
--base-url URL
--api-key KEY / --token TOKEN
--auth-mode auth-token|api-key
--model MODEL
--install-method npm|native
--version latest|stable|具体版本
--config-mode shell|settings
--skip-node
--skip-install
--non-interactive
--dry-run
```

## 安全提示

- 生产环境请使用 HTTPS Base URL。
- 不要把真实 Token 提交到 Git 仓库或发到聊天群。
- 命令行参数可能进入 shell 历史；环境变量或秘密管理器更安全。
- 第三方网关能够看到你的请求内容和密钥，请只使用可信服务。
