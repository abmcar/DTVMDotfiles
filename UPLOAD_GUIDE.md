# 上传 DTVMDotfiles 到 GitHub 指南

## 快速开始

### 步骤 1: 在 GitHub 创建空仓库

1. 登录 [GitHub](https://github.com)
2. 点击右上角 **+** → **New repository**
3. 填写信息：
   - **Repository name**: `DTVMDotfiles`
   - **Description**: `DTVM Configuration Files Sync (Dotfiles)`
   - **Visibility**: 选择 **Public** 或 **Private**
4. **不要** 初始化任何文件（README、.gitignore 等）
5. 点击 **Create repository**

### 步骤 2: 配置本地 Git

首先检查 Git 是否已配置：

```bash
git config user.name
git config user.email
```

如果没有配置，运行以下命令：

```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

**或** 使用全局配置（对所有仓库生效）：

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### 步骤 3: 提交文件

在 DTVMDotfiles 目录中运行：

```bash
cd /workspaces/DTVM/DTVMDotfiles

# 添加所有文件
git add .

# 创建初始提交
git commit -m "Initial commit: Dotfiles sync infrastructure

- Add release.sh: Release dotfiles to external DTVM
- Add store.sh: Store external DTVM files to dotfiles
- Add RELEASE_STORE_README.md: Complete usage documentation
- Add SYNC_README.md: Sync tools documentation
- Add dotfiles/: Configuration files and directories"
```

### 步骤 4: 添加远程仓库并推送

**使用 HTTPS（推荐）**：

```bash
git remote add origin https://github.com/YOUR_USERNAME/DTVMDotfiles.git
git branch -M main
git push -u origin main
```

**或使用 SSH**（如果已配置 SSH 密钥）：

```bash
git remote add origin git@github.com:YOUR_USERNAME/DTVMDotfiles.git
git branch -M main
git push -u origin main
```

将 `YOUR_USERNAME` 替换为你的 GitHub 用户名。

### 步骤 5: 验证上传成功

访问 `https://github.com/YOUR_USERNAME/DTVMDotfiles`，你应该看到所有文件都已上传。

---

## 详细说明

### GitHub Personal Access Token（推荐）

如果使用 HTTPS 推送，GitHub 不再接受密码认证。你需要使用 Personal Access Token：

1. 登录 GitHub
2. 点击右上角头像 → **Settings**
3. 左侧菜单 → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
4. 点击 **Generate new token (classic)**
5. 给 token 起个名字（如 `DTVMDotfiles`）
6. 选择权限范围：
   - ✓ `repo` - Full control of private repositories
   - ✓ `public_repo` - Access public repositories
7. 点击 **Generate token**
8. **复制 token**（页面关闭后无法再看到）

然后在推送时，当要求输入密码时，粘贴这个 token。

### SSH 密钥（可选但推荐）

如果你经常操作 GitHub，建议配置 SSH：

```bash
# 生成 SSH 密钥（如果还没有）
ssh-keygen -t ed25519 -C "your.email@example.com"

# 一路回车使用默认设置
# 密钥会保存在 ~/.ssh/id_ed25519

# 复制公钥
cat ~/.ssh/id_ed25519.pub
```

然后：
1. 登录 GitHub
2. 点击右上角头像 → **Settings**
3. 左侧菜单 → **SSH and GPG keys**
4. 点击 **New SSH key**
5. 粘贴你复制的公钥
6. 点击 **Add SSH key**

---

## 一键上传脚本

如果你已经完成了步骤 1-2，可以使用以下脚本：

```bash
#!/bin/bash

cd /workspaces/DTVM/DTVMDotfiles

# 配置 Git（如果需要）
# git config user.name "Your Name"
# git config user.email "your.email@example.com"

# 提交文件
git add .
git commit -m "Initial commit: Dotfiles sync infrastructure

- Add release.sh: Release dotfiles to external DTVM
- Add store.sh: Store external DTVM files to dotfiles
- Add RELEASE_STORE_README.md: Complete usage documentation
- Add SYNC_README.md: Sync tools documentation
- Add dotfiles/: Configuration files and directories"

# 添加远程仓库并推送
# 替换 YOUR_USERNAME 为你的 GitHub 用户名
YOUR_USERNAME="your-github-username"

git remote add origin https://github.com/${YOUR_USERNAME}/DTVMDotfiles.git
git branch -M main
git push -u origin main

echo "✓ 上传完成！访问 https://github.com/${YOUR_USERNAME}/DTVMDotfiles"
```

---

## 后续操作

上传成功后，你可以：

### 克隆到其他机器

```bash
git clone https://github.com/YOUR_USERNAME/DTVMDotfiles.git
cd DTVMDotfiles
```

### 更新并推送

当你修改了配置文件后：

```bash
cd /workspaces/DTVM/DTVMDotfiles

# 先执行 store.sh 同步文件
./store.sh

# 提交更改
git add .
git commit -m "Update: Your change description"

# 推送到 GitHub
git push
```

### 从 GitHub 拉取最新更改

```bash
cd /workspaces/DTVM/DTVMDotfiles
git pull
./release.sh  # 释放到外部
```

---

## 常见问题

### Q: 推送时提示 "fatal: 'origin' does not appear to be a 'git' repository"

A: 这说明还没有添加远程仓库。运行：
```bash
git remote add origin https://github.com/YOUR_USERNAME/DTVMDotfiles.git
```

### Q: 推送时提示 "Please make sure you have the correct access rights"

A: 这通常是认证问题。检查：
- 使用 HTTPS 时，是否使用了 Personal Access Token
- 使用 SSH 时，是否添加了公钥到 GitHub

### Q: 如何更改远程 URL？

A: 如果之前用 HTTPS，现在想用 SSH（或反之）：
```bash
git remote set-url origin git@github.com:YOUR_USERNAME/DTVMDotfiles.git
```

### Q: 忘记了 Personal Access Token 怎么办？

A: 可以重新创建一个新的，旧的自动失效。或者改用 SSH。

---

## 需要帮助？

如有问题，请参考：
- [GitHub 官方文档](https://docs.github.com)
- [Git 官方文档](https://git-scm.com/doc)
- [使用 SSH 密钥认证](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
