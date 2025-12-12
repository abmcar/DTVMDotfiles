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
2. 将其复制到 `DTVMDotfiles/dotfiles/` 中
3. 覆盖目标目录中的所有内容

### 2. **release.sh** - 释放脚本
位置: `DTVMDotfiles/release.sh`

**功能**: 将 `DTVMDotfiles/dotfiles` 中的文件释放回 DTVM 外部目录

**使用方式**:
```bash
./release.sh
```

**工作流程**:
1. 将 `DTVMDotfiles/dotfiles/` 中的所有文件复制到 DTVM 根目录
2. 完成释放操作

## 同步的文件

两个脚本都同步以下文件和目录：

| 文件/目录 | 说明 |
|---------|------|
| `.claude/` | Claude Code 配置和命令 |
| `.git/info/exclude` | Git 本地排除规则 |
| `qa.md` | QA 文档 |
| `init.sh` | 初始化脚本 |
| `CLAUDE.md` | 开发指南 |
| `perf/record_erc20_perf.sh` | ERC20 workload perf record 脚本 |
| `perf/record_fibr_perf.sh` | fibr workload perf record 脚本 |

## 使用场景

### 场景 1: 在外部修改文件后存放到 dotfiles
```bash
# 1. 修改 DTVM 根目录中的文件（如 qa.md、CLAUDE.md 等）
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
cd ..
git status

# 4. 根据需要提交到 DTVM 仓库
git add CLAUDE.md qa.md init.sh
git commit -m "Release changes from DTVMDotfiles"
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
cd ..
git add CLAUDE.md qa.md init.sh
git commit -m "Release changes from DTVMDotfiles"
```

## 工作原理

```
┌─────────────────────────────────────────────┐
│         DTVM (Main Repository)               │
│  ┌──────────────────────────────────────┐   │
│  │ External Files:                      │   │
│  │ - .claude/                           │   │
│  │ - .git/exclude                       │   │
│  │ - qa.md                              │   │
│  │ - init.sh                            │   │
│  │ - CLAUDE.md                          │   │
│  └──────────────────────────────────────┘   │
│           ↕ (via release.sh & store.sh)     │
│  ┌──────────────────────────────────────┐   │
│  │ DTVMDotfiles/dotfiles/               │   │
│  │ - .claude/                           │   │
│  │ - .git/exclude                       │   │
│  │ - qa.md                              │   │
│  │ - init.sh                            │   │
│  │ - CLAUDE.md                          │   │
│  └──────────────────────────────────────┘   │
│  (Separate Git Repository)                  │
└─────────────────────────────────────────────┘
```

## 注意事项

1. **覆盖操作**: 两个脚本都会**覆盖**目标位置的文件。请在运行前确保已备份重要内容。

2. **目录同步**: 目录（如 `.claude/`）同步时会完全删除目标目录后重新创建，不会保留目标目录中的额外文件。

3. **自动同步**: `release.sh` 执行后会自动调用 `store.sh`，确保文件一致性。

4. **权限**: 两个脚本都需要执行权限。如果权限丢失，运行:
   ```bash
   chmod +x release.sh
   chmod +x DTVMDotfiles/store.sh
   ```

5. **路径要求**:
   - `store.sh` 应在 `DTVMDotfiles` 目录中运行
   - `release.sh` 应在 `DTVMDotfiles` 目录中运行

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
检查文件路径是否在 `SYNC_ITEMS` 数组中定义

### Q: 想添加新的同步文件
编辑相应脚本的 `SYNC_ITEMS` 数组，添加新的同步项:
```bash
SYNC_ITEMS=(
    ".claude:dotfiles/.claude"
    ".git/exclude:dotfiles/.git/exclude"
    "qa.md:dotfiles/qa.md"
    "init.sh:dotfiles/init.sh"
    "CLAUDE.md:dotfiles/CLAUDE.md"
    "new_file.txt:dotfiles/new_file.txt"  # 添加新项
)
```
