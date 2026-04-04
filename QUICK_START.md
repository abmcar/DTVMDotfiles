# DTVMDotfiles 快速开始指南

## 🚀 一句话总结

使用 `setup_from_dotfiles.sh` 一键克隆仓库、释放配置、运行初始化。

## ⚡ 最快的开始方式

### 方式 1: 在当前目录直接运行

```bash
bash /workspaces/DTVM/setup_from_dotfiles.sh
```

### 方式 2: 指定目标目录

```bash
bash /workspaces/DTVM/setup_from_dotfiles.sh /path/to/target
```

### 方式 3: 远程运行（从 GitHub）

```bash
bash <(curl -s https://raw.githubusercontent.com/abmcar/DTVMDotfiles/main/setup_from_dotfiles.sh)
```

## 📋 脚本会自动做什么

1. 🔗 克隆 `DTVMDotfiles` 仓库到本地
2. 🔓 运行 `release.sh` 释放所有配置文件
   - `.git/info/exclude` 会由 `dotfiles/exclude.map.sh` 生成
3. 🚀 执行 `init.sh` 进行初始化设置

## 📂 执行后会有什么

执行脚本后，会在目录中得到：

```
.
├── DTVMDotfiles/          # Git 仓库
│   ├── release.sh
│   ├── store.sh
│   └── dotfiles/
│
├── .claude/               # 配置文件（释放）
├── .git/info/exclude      # Git 配置（释放）
├── CLAUDE.md              # 文档权威源（释放）
├── CLAUDE.local.md        # 本地开发指南（释放）
├── AGENTS.md              # 由 CLAUDE.md 生成的别名（释放）
└── init.sh                # 初始化脚本（释放并执行）
```

## 🎯 几个常见场景

### 场景 1: 在新机器上快速设置

```bash
# 新机器上
cd ~/projects
bash /path/to/setup_from_dotfiles.sh

# 完成！所有配置已设置好
```

### 场景 2: 在 Docker 容器中初始化

```dockerfile
FROM ubuntu:latest

RUN apt-get update && apt-get install -y git bash

COPY setup_from_dotfiles.sh /tmp/

RUN bash /tmp/setup_from_dotfiles.sh /app
```

### 场景 3: 更新已有环境的配置

```bash
# 在现有目录中
bash setup_from_dotfiles.sh

# 脚本自动检测已存在的 DTVMDotfiles，
# 执行 git pull 更新，
# 然后重新释放文件
```

## 📖 详细文档

- **SETUP_GUIDE.md** - 完整的使用指南（包括故障排除）
- **RELEASE_STORE_README.md** - release.sh 和 store.sh 的说明
- **SYNC_README.md** - sync_dotfiles.sh 的说明

## 🛠️ 核心文件说明

| 文件 | 位置 | 作用 |
|------|------|------|
| `setup_from_dotfiles.sh` | DTVM 根目录 | 一键安装脚本 |
| `release.sh` | DTVMDotfiles | 释放配置文件，并从 `CLAUDE.md` 生成 `AGENTS.md` / `GEMINI.md` |
| `store.sh` | DTVMDotfiles | 存放配置文件 |
| `init.sh` | DTVMDotfiles/dotfiles | 初始化脚本 |
| `exclude.map.sh` | DTVMDotfiles/dotfiles | `.git/info/exclude` 的持久化 map |
| `skills.map.sh` | DTVMDotfiles/dotfiles | 历史记录，仅作文档参考（documentation-only） |
| `sync_dotfiles.sh` | DTVM 根目录 | 双向同步工具（可选） |

## 💡 工作流程示意

```
GitHub 仓库（abmcar/DTVMDotfiles）
         ↓ git clone
    本地仓库（DTVMDotfiles/）
         ↓ release.sh
    外部文件（.claude/、CLAUDE.md、CLAUDE.local.md、AGENTS.md 等）
         ↓ init.sh
    环境已初始化 ✓
```

## ✅ 验证安装成功

运行脚本后，检查：

```bash
# 1. 仓库已克隆
ls -d DTVMDotfiles

# 2. 文件已释放
ls -a | grep -E "\.claude|CLAUDE.md|AGENTS.md"

# 3. 初始化已运行
cat init.sh  # 查看初始化脚本内容
```

## 🔄 后续操作

### 修改配置后同步

```bash
cd DTVMDotfiles
./store.sh
git add .
git commit -m "Update config"
git push
```

### 从 GitHub 更新配置

```bash
# 方式 1: 使用 setup 脚本
bash setup_from_dotfiles.sh

# 方式 2: 手动更新
cd DTVMDotfiles
git pull
./release.sh
```

## ⚙️ 常用命令速查

```bash
# 克隆并设置
bash setup_from_dotfiles.sh

# 仅释放文件（无需克隆）
cd DTVMDotfiles && ./release.sh && cd ..

# 存放文件到 dotfiles
cd DTVMDotfiles && ./store.sh

# 仅运行初始化
bash init.sh

# 同步工具（双向）
./sync_dotfiles.sh to-dotfiles    # 推送到 dotfiles
./sync_dotfiles.sh from-dotfiles  # 从 dotfiles 拉取
./sync_dotfiles.sh status         # 查看状态
```

## 📌 重要提示

- ⚠️ `release.sh` 会覆盖同名文件，建议先备份
- ✓ `store.sh` 会自动压缩冗余 exclude，例如 `aaa/bbb` 会覆盖 `aaa/bbb/ccc`
- ✓ `CLAUDE.md` 是文档权威源；`AGENTS.md` 和 `GEMINI.md` 由 `release.sh` 生成
- ✓ 需要 `git` 和 Bash 4.3+
- ✓ Linux 和 WSL 可直接使用；macOS 需安装更新版本的 Bash，不能用系统自带 `/bin/bash` 3.2
- ✓ 首次克隆需要网络连接
- ✓ 脚本是幂等的，可以重复运行

## 🆘 遇到问题？

1. 查看 **SETUP_GUIDE.md** 的故障排除部分
2. 确保 `git` 已安装：`git --version`
3. 检查网络连接：`ping github.com`
4. 查看脚本输出的错误信息

## 📞 获取帮助

- GitHub 仓库：https://github.com/abmcar/DTVMDotfiles
- 仓库的 Issue：提出问题或建议

---

## 快速参考

| 需求 | 命令 |
|------|------|
| 快速设置 | `bash setup_from_dotfiles.sh` |
| 指定目录 | `bash setup_from_dotfiles.sh /path` |
| 更新配置 | `cd DTVMDotfiles && git pull && ./release.sh` |
| 提交配置 | `cd DTVMDotfiles && ./store.sh && git push` |
| 查看帮助 | `cat SETUP_GUIDE.md` |

---

**现在就开始吧！** 🎉

```bash
bash setup_from_dotfiles.sh
```
