# DTVMDotfiles Sync Script

这个脚本用于在 DTVM 和 DTVM/DTVMDotfiles 仓库之间进行双向同步。

**注意**: DTVMDotfiles 现在是 DTVM 的子目录，已添加到 `.git/info/exclude` 中，不会被提交到主仓库。

## 功能

同步以下文件和目录：
- `.claude/` - Claude Code 配置和命令
- `dotfiles/exclude.map.sh` - `.git/info/exclude` 的持久化 map
- `dotfiles/skills.map.sh` + `dotfiles/.agents/skills/` - 仅同步托管的本地 skill
- `init.sh` - 初始化脚本
- `CLAUDE.md` - Claude 开发指南
- `perf/record_erc20_perf.sh` - ERC20 workload perf record 脚本
- `perf/record_fibr_perf.sh` - fibr workload perf record 脚本

## 安装

脚本已位于项目根目录：`/workspaces/DTVM/sync_dotfiles.sh`

## 使用方法

### 同步到 DTVMDotfiles（从 DTVM 推送）
```bash
./sync_dotfiles.sh to-dotfiles
# 或
./sync_dotfiles.sh push
```

### 从 DTVMDotfiles 同步（拉取更新）
```bash
./sync_dotfiles.sh from-dotfiles
# 或
./sync_dotfiles.sh pull
```

### 查看同步状态
```bash
./sync_dotfiles.sh status
# 或
./sync_dotfiles.sh check
```

## 工作流程

### 本地开发流程
1. 在 DTVM 中修改 `.claude/`、`CLAUDE.md` 等文件
2. 运行 `./sync_dotfiles.sh to-dotfiles` 同步到 DTVMDotfiles
3. 提交更改到 DTVMDotfiles 仓库

### 从 DTVMDotfiles 更新
1. 在 DTVMDotfiles 仓库中更新文件
2. 运行 `./sync_dotfiles.sh from-dotfiles` 同步回 DTVM
3. 验证更改

## 目录结构

```
DTVM/
├── DTVMDotfiles/         # 同步的 dotfiles 仓库
│   └── dotfiles/
│       ├── .claude/      # Claude Code 配置
│       ├── .agents/skills/
│       ├── exclude.map.sh
│       ├── skills.map.sh
│       ├── init.sh       # 初始化脚本
│       └── CLAUDE.md     # 开发指南
├── sync_dotfiles.sh      # 同步脚本
├── .git/
│   └── exclude           # 包含 DTVMDotfiles/ 的排除规则
└── ...
```

## 注意事项

- 脚本会**覆盖**目标位置的文件，请确保先备份重要更改
- `.git/info/exclude` 现在由 `exclude.map.sh` 生成，store 时会自动压缩冗余路径
- 只有 `skills.map.sh` 中标记为 `managed` 的 skill 会被同步
- 目录同步时会删除目标目录中的所有文件
- 建议在同步前运行 `status` 命令检查变更

## 常见问题

### Q: 同步会删除文件吗？
是的，目录同步时会删除目标目录中的所有现有文件。对于单个文件同步，只会覆盖该文件。

### Q: 如何避免意外覆盖？
运行 `./sync_dotfiles.sh status` 先检查将要同步的文件。

### Q: 可以选择性地同步某些文件吗？
可以。常规文件编辑 `lib/sync_common.sh` 里的 `MIRRORED_ITEMS`，技能编辑 `dotfiles/skills.map.sh`。

## 自定义

编辑 `lib/sync_common.sh` 中的 `MIRRORED_ITEMS` 来修改常规同步内容：

```bash
declare -agr MIRRORED_ITEMS=(
    ".claude"
    "init.sh"
    "CLAUDE.md"
    "perf/record_erc20_perf.sh"
    "perf/record_fibr_perf.sh"
)
```

技能同步则由 `dotfiles/skills.map.sh` 控制：
```bash
declare -Ag DTVM_SKILLS_MAP=(
    ["local-skill"]="managed"
    ["shared-skill"]="external"
)
```
