# DTVMDotfiles Sync Script

这个脚本用于在 DTVM 和 DTVM/DTVMDotfiles 仓库之间进行双向同步。

**注意**: DTVMDotfiles 现在是 DTVM 的子目录，已添加到 `.git/exclude` 中，不会被提交到主仓库。

## 功能

同步以下文件和目录：
- `.claude/` - Claude Code 配置和命令
- `.git/exclude` - Git 排除规则
- `qa.md` - QA 文档
- `init.sh` - 初始化脚本
- `CLAUDE.md` - Claude 开发指南

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
1. 在 DTVM 中修改 `.claude/`、`qa.md` 等文件
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
│       ├── .git/
│       │   └── exclude   # Git 排除规则
│       ├── qa.md         # QA 文档
│       ├── init.sh       # 初始化脚本
│       └── CLAUDE.md     # 开发指南
├── sync_dotfiles.sh      # 同步脚本
├── .git/
│   └── exclude           # 包含 DTVMDotfiles/ 的排除规则
└── ...
```

## 注意事项

- 脚本会**覆盖**目标位置的文件，请确保先备份重要更改
- `.git/exclude` 文件不包含在 Git 跟踪中（根据 git 惯例）
- 目录同步时会删除目标目录中的所有文件
- 建议在同步前运行 `status` 命令检查变更

## 常见问题

### Q: 同步会删除文件吗？
是的，目录同步时会删除目标目录中的所有现有文件。对于单个文件同步，只会覆盖该文件。

### Q: 如何避免意外覆盖？
运行 `./sync_dotfiles.sh status` 先检查将要同步的文件。

### Q: 可以选择性地同步某些文件吗？
目前脚本同步所有定义的项目。如需选择性同步，可手动编辑脚本中的 `SYNC_ITEMS` 数组。

## 自定义

编辑脚本中的 `SYNC_ITEMS` 数组来修改同步内容：

```bash
SYNC_ITEMS=(
    ".claude:dotfiles/.claude"
    ".git/exclude:dotfiles/.git/exclude"
    "qa.md:dotfiles/qa.md"
    "init.sh:dotfiles/init.sh"
    "CLAUDE.md:dotfiles/CLAUDE.md"
    # 添加更多项目...
)
```
