# Release & Store Scripts

这两个脚本提供了 DTVMDotfiles 与外部 DTVM 目录之间的双向文件同步机制。

## 脚本说明

### 1. **store.sh** - 存放脚本
位置: `DTVMDotfiles/store.sh`

**功能**: 将外部 DTVM 目录中的配置文件同步到 `dotfiles` 文件夹中

**使用方式**:
```bash
cd DTVMDotfiles
./store.sh
```

**工作流程**:
1. 读取 DTVM 根目录中的文件
2. 将镜像文件复制到 `DTVMDotfiles/dotfiles/` 中
3. 将 `.git/info/exclude` 归一化后写入 `dotfiles/exclude.map.sh`
4. 仅同步 `dotfiles/skills.map.sh` 中标记为 `managed` 的 `.agents/skills`

### 2. **release.sh** - 释放脚本
位置: `DTVMDotfiles/release.sh`

**功能**: 将 `DTVMDotfiles/dotfiles` 中的文件释放回 DTVM 外部目录

**使用方式**:
```bash
./release.sh
```

**工作流程**:
1. 将 `DTVMDotfiles/dotfiles/` 中的镜像文件复制到 DTVM 根目录
2. 根据 `dotfiles/exclude.map.sh` 生成 `.git/info/exclude`
3. 仅释放 `dotfiles/skills.map.sh` 中标记为 `managed` 的 `.agents/skills`
4. 将 `.claude/commands` 同步到 `~/.codex/prompts`

## 同步的文件

两个脚本都同步以下文件和目录：

| 文件/目录 | 说明 |
|---------|------|
| `.claude/` | Claude Code 配置和命令 |
| `dotfiles/exclude.map.sh` | `.git/info/exclude` 的持久化 map，会在 store 时压缩冗余路径 |
| `dotfiles/skills.map.sh` | `.agents/skills` 的同步策略，`managed` 会同步，`external` 会跳过 |
| `dotfiles/.agents/skills/` | 仅保存当前仓库自己管理的 skill |
| `init.sh` | 初始化脚本 |
| `CLAUDE.md` | 开发指南 |
| `perf/record_erc20_perf.sh` | ERC20 workload perf record 脚本 |
| `perf/record_fibr_perf.sh` | fibr workload perf record 脚本 |

## 使用场景

### 场景 1: 在外部修改文件后存放到 dotfiles
```bash
# 1. 修改 DTVM 根目录中的文件（如 CLAUDE.md 等）
# 2. 进入 DTVMDotfiles 目录
cd DTVMDotfiles

# 3. 执行存放脚本
./store.sh

# 4. 提交更改到 DTVMDotfiles 仓库
git add .
git commit -m "Store changes from DTVM"
```

### 场景 2: 从 dotfiles 释放文件到外部
```bash
# 1. 从远程拉取 DTVMDotfiles 的最新更改（假设已经在另一个环境修改）
git pull

# 2. 运行释放脚本
./release.sh

# 3. 检查外部文件是否已更新
(cd .. && git status)

# 4. 根据需要提交到 DTVM 仓库
(cd .. && git add CLAUDE.md init.sh && git commit -m "Release changes from DTVMDotfiles")
```

### 场景 3: 完整的双向同步流程
```bash
# 场景 3.1: 在外部修改后存放到 dotfiles
# 修改外部文件
nano CLAUDE.md

# 进入 DTVMDotfiles 并存放
cd DTVMDotfiles
./store.sh
git add .
git commit -m "Store latest changes"

# 场景 3.2: 从 dotfiles 拉取后释放到外部
# 拉取最新更改
git pull

# 释放回外部
./release.sh

# 返回上层目录并提交
(cd .. && git add CLAUDE.md init.sh && git commit -m "Release changes from DTVMDotfiles")
```

## 工作原理

```
┌─────────────────────────────────────────────┐
│         DTVM (Main Repository)               │
│  ┌──────────────────────────────────────┐   │
│  │ External Files:                      │   │
│  │ - .claude/                           │   │
│  │ - .git/info/exclude                  │   │
│  │ - .agents/skills/                    │   │
│  │ - init.sh                            │   │
│  │ - CLAUDE.md                          │   │
│  └──────────────────────────────────────┘   │
│           ↕ (via release.sh & store.sh)     │
│  ┌──────────────────────────────────────┐   │
│  │ DTVMDotfiles/dotfiles/               │   │
│  │ - .claude/                           │   │
│  │ - exclude.map.sh                     │   │
│  │ - skills.map.sh                      │   │
│  │ - .agents/skills/                    │   │
│  │ - init.sh                            │   │
│  │ - CLAUDE.md                          │   │
│  └──────────────────────────────────────┘   │
│  (Separate Git Repository)                  │
└─────────────────────────────────────────────┘
```

## 注意事项

1. **覆盖操作**: 两个脚本都会**覆盖**目标位置的文件。请在运行前确保已备份重要内容。

2. **目录同步**: 目录（如 `.claude/`）同步时会完全删除目标目录后重新创建，不会保留目标目录中的额外文件。

3. **Exclude 压缩**: `store.sh` 会把 `.git/info/exclude` 存成 map，并自动去掉 `aaa/bbb/ccc` 这类已被 `aaa/bbb` 覆盖的冗余项。

4. **Skills 分层**: 只有 `dotfiles/skills.map.sh` 中标记为 `managed` 的 skill 会被同步；`external` 或未列出的 skill 不会被 DTVMDotfiles 触碰。

5. **Bash 版本**: 脚本依赖 Bash 4.3 或更新版本。macOS 自带的 `/bin/bash` 3.2 不支持，需要自行安装更新版本的 Bash。

6. **权限**: 两个脚本都需要执行权限。如果权限丢失，运行:
   ```bash
   chmod +x release.sh
   chmod +x DTVMDotfiles/store.sh
   ```

7. **路径要求**:
   - `store.sh` 应在 `DTVMDotfiles` 目录中运行
   - `release.sh` 应在 `DTVMDotfiles` 目录中运行

8. **环境变量**:
   - `DTVMDOTFILES_PARENT_DIR`: 覆盖默认父目录，便于测试或自定义工作区
   - `DTVMDOTFILES_CODEX_PROMPTS_DIR`: 覆盖 `.claude/commands` 的目标目录

## 与 sync_dotfiles.sh 的区别

| 脚本 | 位置 | 用途 | 执行位置 |
|------|------|------|---------|
| `sync_dotfiles.sh` | DTVM 根目录 | 通用双向同步工具 | DTVM 根目录 |
| `release.sh` | DTVMDotfiles | 从 dotfiles 释放并同步 | DTVMDotfiles 目录 |
| `store.sh` | DTVMDotfiles | 存放外部文件到 dotfiles | DTVMDotfiles 目录 |

- `sync_dotfiles.sh`: 更加灵活，可选择 push/pull 方向
- `release.sh` + `store.sh`: 针对特定工作流，自动化程度更高，都位于 DTVMDotfiles 中

## 故障排除

### Q: 运行 store.sh 时提示权限不足
```bash
chmod +x DTVMDotfiles/store.sh
```

### Q: release.sh 没有找到 store.sh
确保 `DTVMDotfiles/store.sh` 存在且有执行权限

### Q: 文件没有被同步
检查路径是否在 `lib/sync_common.sh` 的 `MIRRORED_ITEMS` 中，或技能是否在 `dotfiles/skills.map.sh` 中标记为 `managed`

### Q: 想添加新的同步文件
编辑 `lib/sync_common.sh` 中的 `MIRRORED_ITEMS`：
```bash
declare -agr MIRRORED_ITEMS=(
    ".claude"
    "init.sh"
    "CLAUDE.md"
    "new_file.txt"
)
```

### Q: 想管理新的 skill
编辑 `dotfiles/skills.map.sh`，将 skill 标记为 `managed`：
```bash
declare -Ag DTVM_SKILLS_MAP=(
    ["existing-skill"]="managed"
    ["new-local-skill"]="managed"
    ["shared-skill"]="external"
)
```
