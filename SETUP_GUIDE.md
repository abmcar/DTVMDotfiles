# setup_from_dotfiles.sh 使用指南

## 概述

`setup_from_dotfiles.sh` 是一个一键安装脚本，可以从 GitHub 克隆 DTVMDotfiles 仓库，释放配置文件，并自动运行初始化脚本。

这对于：
- 🆕 在新机器上快速部署环境
- 📱 跨环境同步配置
- 🔄 自动化设置流程

## 快速开始

### 最简单的使用方法

```bash
# 方法 1: 在当前目录克隆并设置
cd /path/to/your/workspace
bash setup_from_dotfiles.sh

# 方法 2: 指定目标目录
bash setup_from_dotfiles.sh /tmp/new-setup
```

## 详细说明

### 脚本做什么

脚本按顺序执行以下步骤：

1. **克隆仓库**
   ```
   git clone https://github.com/abmcar/DTVMDotfiles.git
   ```
   - 如果仓库已存在，则更新（git pull）
   - 如果不存在，则新建

2. **进入仓库目录**
   ```
   cd DTVMDotfiles
   ```

3. **运行 release.sh**
   ```bash
   ./release.sh
   ```
   - 释放所有配置文件到父目录
   - 包括：.claude/, .git/info/exclude, init.sh, CLAUDE.md, CLAUDE.local.md

4. **执行 init.sh**
   ```bash
   ../init.sh
   ```
   - 运行释放出来的初始化脚本
   - 进行必要的环境配置

### 目录结构

执行完脚本后，会生成以下结构：

```
target-directory/
├── DTVMDotfiles/              # 克隆的仓库
│   ├── .git/                  # Git 仓库数据
│   ├── release.sh             # 释放脚本
│   ├── store.sh               # 存放脚本
│   ├── RELEASE_STORE_README.md
│   └── dotfiles/
│       ├── .claude/
│       ├── exclude.map.sh
│       ├── skills.map.sh     # documentation-only
│       ├── init.sh
│       ├── CLAUDE.md
│       └── CLAUDE.local.md
│
├── .claude/                   # ← 释放出来的配置
├── .git/
│   └── info/
│       └── exclude            # ← 释放出来的文件
├── CLAUDE.md                  # ← 释放出来的文件
├── CLAUDE.local.md            # ← 释放出来的文件
└── init.sh                    # ← 释放出来的文件（已执行）
```

## 使用场景

### 场景 1: 在新主机上设置开发环境

```bash
# 在新主机上
mkdir -p ~/projects/dtvm
cd ~/projects/dtvm

# 从 GitHub 克隆并自动设置
bash ~/setup_from_dotfiles.sh

# 一切就绪！
```

### 场景 2: 在容器或虚拟机中初始化

```bash
# Dockerfile 中
RUN git clone https://github.com/abmcar/DTVMDotfiles.git && \
    bash DTVMDotfiles/../setup_from_dotfiles.sh

# 或直接
RUN bash <(curl -s https://raw.githubusercontent.com/abmcar/DTVMDotfiles/main/setup_from_dotfiles.sh)
```

### 场景 3: 更新现有环境中的配置

```bash
# 在已有 DTVMDotfiles 的目录中
bash setup_from_dotfiles.sh

# 脚本检测到已存在，自动 git pull 更新
# 然后重新释放文件和运行 init.sh
```

## 参数说明

### 用法

```bash
./setup_from_dotfiles.sh [target-directory]
```

### 参数

- `target-directory` (可选)
  - 克隆仓库和释放文件的目标目录
  - 默认值：当前目录 (`.`)
  - 如果不指定，则在当前目录执行
  - 如果指定，则在指定目录执行

### 示例

```bash
# 使用默认目录（当前目录）
./setup_from_dotfiles.sh

# 指定目录
./setup_from_dotfiles.sh /tmp/my-setup
./setup_from_dotfiles.sh ~/new-project
./setup_from_dotfiles.sh /opt/dtvm
```

## init.sh 包含什么

`init.sh` 是释放出来的初始化脚本，可以包含任何你需要的初始化命令。

默认的 `init.sh` 通常包含：
- Git 用户配置
- 环境变量设置
- 必要的目录创建
- 权限配置
- 其他初始化任务

你可以在 DTVMDotfiles 中修改 `dotfiles/init.sh` 来自定义初始化流程。

## 常见用途

### 用途 1: 快速部署

```bash
# 一条命令完成所有设置
bash setup_from_dotfiles.sh /workspace

# 等价于：
# git clone <repo>
# cd DTVMDotfiles && ./release.sh
# cd .. && ./init.sh
```

### 用途 2: 跨机器同步

```bash
# 在机器 A：修改配置
cd DTVMDotfiles
./store.sh && git add . && git commit -m "Update config" && git push

# 在机器 B：获取最新配置
bash setup_from_dotfiles.sh

# 完成！你的配置已同步到机器 B
```

### 用途 3: 自动化部署

```bash
# 在 CI/CD 流程中
- name: Setup from dotfiles
  run: bash setup_from_dotfiles.sh ${{ runner.workspace }}
```

## 故障排除

### 问题 1: 克隆失败

**错误信息**: `fatal: unable to access repository`

**解决方案**:
- 检查网络连接
- 确保 GitHub URL 正确
- 检查 Git 是否已安装
- 如果是私有仓库，检查凭证配置

### 问题 2: release.sh 没有找到

**错误信息**: `Error: release.sh not found`

**解决方案**:
- 确保仓库克隆成功
- 检查仓库内容：`ls DTVMDotfiles/`
- 重新克隆仓库

### 问题 3: init.sh 执行失败

**错误信息**: `Error: init.sh not found`

**解决方案**:
- 检查 release.sh 是否正确释放文件
- 查看释放的文件：`ls -la`
- 检查 init.sh 的权限：`ls -la init.sh`
- 手动运行 init.sh 查看错误：`bash init.sh`

### 问题 4: 权限被拒绝

**错误信息**: `Permission denied`

**解决方案**:
- 添加执行权限：`chmod +x setup_from_dotfiles.sh`
- 检查文件权限：`ls -la *.sh`
- 使用 `bash` 运行而不是直接执行：`bash setup_from_dotfiles.sh`

## 高级用法

### 自定义脚本

如果需要修改克隆的仓库 URL，编辑 `setup_from_dotfiles.sh`：

```bash
# 修改这一行
GITHUB_REPO="https://github.com/your-username/your-repo.git"
```

### 只执行某些步骤

如果只想执行特定步骤，可以：

```bash
# 只克隆
git clone https://github.com/abmcar/DTVMDotfiles.git

# 只释放
cd DTVMDotfiles
./release.sh

# 只初始化
cd ..
bash init.sh
```

### 保存克隆的仓库

默认脚本保留 `DTVMDotfiles` 目录，你可以：

```bash
# 之后更新配置
cd DTVMDotfiles
git pull
./release.sh
```

## 最佳实践

1. **定期更新**
   ```bash
   # 定期运行脚本以获取最新配置
   bash setup_from_dotfiles.sh
   ```

2. **备份配置**
   ```bash
   # 在运行脚本前备份当前配置
   tar czf backup-$(date +%Y%m%d).tar.gz .claude/ CLAUDE.md
   ```

3. **版本控制**
   ```bash
   # 修改后提交
   cd DTVMDotfiles
   git add -A
   git commit -m "Update: description of changes"
   git push
   ```

4. **测试环境**
   ```bash
   # 在容器中测试脚本
   docker run -it ubuntu:latest bash /path/to/setup_from_dotfiles.sh
   ```

5. **本地 skill**
   ```bash
   # skills.map.sh 现在仅作文档参考（documentation-only），不再驱动同步。
   # 新的本地 skill 应放到 .claude/rules/ 或 .claude/commands/ 中，
   # 它们会随 .claude/ 目录自动同步。
   ls .claude/rules/ .claude/commands/
   ```

6. **测试路径覆盖**
   ```bash
   DTVMDOTFILES_PARENT_DIR=/tmp/dtvm-workspace ./release.sh
   DTVMDOTFILES_CODEX_PROMPTS_DIR=/tmp/codex-prompts ./release.sh
   ```

## 相关文件

- `setup_from_dotfiles.sh` - 本脚本
- `DTVMDotfiles/release.sh` - 释放脚本
- `DTVMDotfiles/store.sh` - 存放脚本
- `DTVMDotfiles/dotfiles/init.sh` - 初始化脚本
- `DTVMDotfiles/RELEASE_STORE_README.md` - 详细文档

## 常见问题（FAQ）

**Q: 脚本会删除现有文件吗？**
A: release.sh 会覆盖同名文件，建议先备份重要文件。

**Q: 可以离线使用吗？**
A: 不能，需要从 GitHub 克隆。但一旦克隆完成，可以离线使用 release.sh。

**Q: 支持哪些操作系统？**
A: 支持安装了 Git 和 Bash 4.3+ 的系统。Linux 和 WSL 可以直接使用；macOS 需要安装更新版本的 Bash，不能使用系统自带 `/bin/bash` 3.2。

**Q: 如何禁用某些文件的释放？**
A: 编辑 `DTVMDotfiles/lib/sync_common.sh` 里的 `MIRRORED_ITEMS`。`skills.map.sh` 现在仅作文档参考（documentation-only），不再控制同步。

**Q: 可以在 Docker 中使用吗？**
A: 可以，需要先安装 bash 和 git。

## 获取帮助

如有问题，可以：
1. 查看脚本日志输出
2. 查看 `DTVMDotfiles/RELEASE_STORE_README.md`
3. 查看 GitHub 仓库：https://github.com/abmcar/DTVMDotfiles
