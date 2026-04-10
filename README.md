# DTVMDotfiles

DTVM 项目的 AI 辅助开发环境配置管理工具。在多台机器间同步 Claude Code / Codex / Gemini 的配置、规则、hooks、子 agent 定义和性能测试基础设施。

## 它解决什么问题

[DTVM](https://github.com/DTVMStack/DTVM) 是一个具有 EVM ABI 兼容性的确定性虚拟机，核心实现为 C/C++。开发过程中大量依赖 AI 辅助编码（Claude Code 子 agent、自动化 hooks、规则约束等）。这些配置文件不属于 DTVM 主仓库，但需要在不同开发机器间保持同步。

DTVMDotfiles 提供双向同步：
- **release**：将配置从本仓库部署到 DTVM 工作区
- **store**：将工作区中的配置变更收集回本仓库
- **diff**：检测已部署配置与本仓库之间的漂移

## 目录结构

```
DTVMDotfiles/
├── release.sh                  # 部署：dotfiles/ → DTVM 工作区
├── store.sh                    # 收集：DTVM 工作区 → dotfiles/
├── diff.sh                     # 漂移检测
├── setup_from_dotfiles.sh      # 一键 bootstrap（clone + release + init）
├── lib/
│   └── sync_common.sh          # 核心逻辑：MIRRORED_ITEMS 定义、manifest 读写、同步函数
└── dotfiles/                   # 所有受管理的配置文件
    ├── CLAUDE.md               # DTVM 开发指南（权威源）
    ├── CLAUDE.local.md         # 本地机器环境路径
    ├── init.sh                 # 环境初始化（Node.js、Claude Code、Codex、git submodule）
    ├── exclude.map.sh          # .git/info/exclude 的持久化表示
    ├── .claude/
    │   ├── settings.json       # Claude Code hooks 配置
    │   ├── agents/             # 4 个子 agent（compiler、perf、test、research）
    │   ├── commands/           # 7 个斜杠命令（/dotfiles、/session-summary 等）
    │   ├── hooks/              # 5 个 hook 脚本（CI 验证、同步提醒、session 管理）
    │   └── rules/              # 8 条规则（代码风格、CI 纪律、架构约束等）
    └── perf/                   # 性能测试脚本和 EVM 字节码
        ├── record_erc20_perf.sh
        ├── record_fibr_perf.sh
        └── *.evm.hex           # ERC20、fibonacci 测试用字节码
```

## 安装（新机器 Bootstrap）

### 方式一：一键脚本

在 DTVM 仓库的父目录下运行（或在已有的 DTVM 仓库根目录下运行）：

```bash
# 如果 DTVM 仓库已 clone 到当前目录
cd /path/to/DTVM
bash <(curl -s https://raw.githubusercontent.com/abmcar/DTVMDotfiles/main/setup_from_dotfiles.sh)
```

脚本会自动：
1. Clone DTVMDotfiles 到当前目录下
2. 运行 `release.sh` 部署所有配置
3. 运行 `init.sh` 安装依赖（Node.js 22、gh CLI、Claude Code、Codex）

### 方式二：手动安装

```bash
cd /path/to/DTVM
git clone https://github.com/abmcar/DTVMDotfiles.git
cd DTVMDotfiles
bash release.sh     # 部署配置到父目录
bash ../init.sh     # 初始化环境（可选）
```

### 前置要求

- Git
- Bash 4.3+（Linux/WSL 自带；macOS 需 `brew install bash`，系统自带的 3.2 不支持）
- 网络连接（首次 clone 及 init.sh 安装依赖时需要）

## 部署后的效果

运行 `release.sh` 后，DTVM 工作区会得到：

```
DTVM/
├── DTVMDotfiles/              # 本仓库
├── .claude/                   # Claude Code 配置（rules、commands、agents、hooks）
│   └── .dtvm-manifest.json    # manifest 文件，记录所有受管文件的 SHA256 hash
├── CLAUDE.md                  # AI 开发指南（权威源）
├── CLAUDE.local.md            # 本地环境路径配置
├── AGENTS.md                  # CLAUDE.md 的副本（供其他 AI 工具读取）
├── GEMINI.md                  # CLAUDE.md 的副本（供 Gemini 读取）
├── init.sh                    # 环境初始化脚本
├── perf/                      # 性能测试脚本和字节码
└── .git/info/exclude          # 由 exclude.map.sh 生成的 git exclude 规则
```

同时 `.claude/commands/` 会被同步到 `~/.codex/prompts/`（Codex 兼容）。

## 日常使用

### 修改配置后保存

```bash
# 1. 在 DTVM 工作区中修改配置（如 .claude/rules/*.md、CLAUDE.md 等）
# 2. 收集变更回 dotfiles
cd DTVMDotfiles
bash store.sh

# 3. 提交并推送
git add -A && git commit -m "update config" && git push
```

### 从远端拉取更新

```bash
cd DTVMDotfiles
git pull
bash release.sh
```

### 检查漂移

```bash
cd DTVMDotfiles
bash diff.sh
```

输出会显示：locally modified、deleted、new in dotfiles、unmanaged 等分类。

## 核心机制

### Manifest 追踪

`release.sh` 会在 DTVM 工作区生成 `.claude/.dtvm-manifest.json`，记录每个受管文件的路径和内容 hash（SHA256 前 12 位）。`store.sh` 读取这个 manifest 来确定需要收集哪些文件，`diff.sh` 用它来检测漂移。

### MIRRORED_ITEMS

在 `lib/sync_common.sh` 中定义了所有需要同步的文件/目录：

| Item | 说明 |
|------|------|
| `.claude/` | Claude Code 完整配置（settings、rules、commands、agents、hooks） |
| `CLAUDE.md` | DTVM 开发指南 |
| `CLAUDE.local.md` | 本地机器环境路径 |
| `init.sh` | 环境初始化脚本 |
| `perf/*.sh` | 性能分析录制脚本 |
| `perf/*.evm.hex` | EVM 测试字节码 |

要添加新的同步项：编辑 `lib/sync_common.sh` 中的 `MIRRORED_ITEMS` 数组，然后运行 `release.sh`。

### release.sh 的额外行为

- 从 `dotfiles/exclude.map.sh` 渲染 `.git/info/exclude`
- 从 `CLAUDE.md` 生成 `AGENTS.md` 和 `GEMINI.md`
- 将 `.claude/commands/` 同步到 `~/.codex/prompts/`
- 清理旧 manifest 中存在但新 manifest 中已移除的文件

### Hook 自动化

部署后，Claude Code 会自动运行以下 hooks：

| 触发时机 | 功能 |
|---------|------|
| `PreToolUse` (git push) | 在推送前运行完整 CI 流水线（格式检查 + 构建 + 测试） |
| `PostToolUse` (Edit/Write) | 当受管文件被修改时提醒同步到 DTVMDotfiles |
| `PostToolUse` (git push) | 推送后自动监控 CI 运行状态 |
| `SessionStart` | 显示缓存的 housekeeping 报告 |

## 命令速查

| 需求 | 命令 |
|------|------|
| 新机器一键安装 | `bash setup_from_dotfiles.sh` |
| 部署配置到工作区 | `cd DTVMDotfiles && bash release.sh` |
| 收集工作区变更 | `cd DTVMDotfiles && bash store.sh` |
| 检查配置漂移 | `cd DTVMDotfiles && bash diff.sh` |
| 从远端更新 | `cd DTVMDotfiles && git pull && bash release.sh` |
| 保存并推送 | `cd DTVMDotfiles && bash store.sh && git add -A && git commit -m "msg" && git push` |

## 注意事项

- `release.sh` 会覆盖目标目录中的同名文件，建议先 commit 或备份
- `store.sh` 依赖 manifest，首次使用必须先运行 `release.sh`
- 脚本是幂等的，可以重复运行
- `CLAUDE.md` 是唯一的权威源；`AGENTS.md` 和 `GEMINI.md` 是自动生成的副本，不要直接编辑
- `CLAUDE.local.md` 包含机器特定的路径，部署后需要根据本机环境调整
