# VS Code Snippet for DTVMDotfiles Setup

这个文档说明如何在 VS Code 中配置 snippet，一键部署 DTVMDotfiles。

## 📋 创建 Snippet 的步骤

### 1. 打开 Snippet 配置

- **macOS/Linux**: `Code` → `Preferences` → `User Snippets`
- **Windows**: `File` → `Preferences` → `User Snippets`

或按快捷键：`Ctrl+Shift+P`（或 `Cmd+Shift+P` on macOS）输入 "Snippets"

### 2. 选择或创建 Shell Script Snippets

选择 `shellscript` 或 `bash` snippets 文件

### 3. 添加以下 Snippet

在 `shellscript.json` 或 `bash.json` 文件中，添加以下代码：

```json
"Setup DTVMDotfiles": {
    "prefix": "setup-dtvm",
    "body": [
        "#!/bin/bash",
        "",
        "# One-click setup for DTVMDotfiles",
        "# This script clones DTVMDotfiles, releases files, and runs init",
        "",
        "set -e",
        "",
        "GITHUB_REPO=\"https://github.com/abmcar/DTVMDotfiles.git\"",
        "TARGET_DIR=\"${1:-.}\"",
        "",
        "echo \"╔════════════════════════════════════════════════════════════════╗\"",
        "echo \"║        Setting up DTVMDotfiles                                 ║\"",
        "echo \"╚════════════════════════════════════════════════════════════════╝\"",
        "echo \"\"",
        "",
        "# Clone repository",
        "if [ -d \"$TARGET_DIR/DTVMDotfiles\" ]; then",
        "    echo \"📥 Updating existing DTVMDotfiles...\"",
        "    cd \"$TARGET_DIR/DTVMDotfiles\"",
        "    git pull",
        "else",
        "    echo \"📥 Cloning DTVMDotfiles...\"",
        "    cd \"$TARGET_DIR\"",
        "    git clone \"$GITHUB_REPO\"",
        "    cd DTVMDotfiles",
        "fi",
        "",
        "echo \"✅ Repository ready\"",
        "echo \"\"",
        "",
        "# Release files",
        "echo \"🔓 Releasing configuration files...\"",
        "bash ./release.sh",
        "",
        "echo \"\"",
        "echo \"🚀 Running init.sh...\"",
        "bash ../init.sh",
        "",
        "echo \"\"",
        "echo \"╔════════════════════════════════════════════════════════════════╗\"",
        "echo \"║                  ✅ Setup Complete!                           ║\"",
        "echo \"╚════════════════════════════════════════════════════════════════╝\""
    ],
    "description": "Clone DTVMDotfiles, release files, and run init.sh in one command"
}
```

## 🚀 如何使用 Snippet

### 方式 1: 在任何 Shell Script 文件中

1. 创建一个新的 `.sh` 文件或打开现有的 shell script
2. 输入 `setup-dtvm` 然后按 `Tab` 或 `Enter`
3. Snippet 会自动展开

### 方式 2: 在终端中直接运行

复制整个脚本体：

```bash
#!/bin/bash

set -e

GITHUB_REPO="https://github.com/abmcar/DTVMDotfiles.git"
TARGET_DIR="${1:-.}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Setting up DTVMDotfiles                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Clone repository
if [ -d "$TARGET_DIR/DTVMDotfiles" ]; then
    echo "📥 Updating existing DTVMDotfiles..."
    cd "$TARGET_DIR/DTVMDotfiles"
    git pull
else
    echo "📥 Cloning DTVMDotfiles..."
    cd "$TARGET_DIR"
    git clone "$GITHUB_REPO"
    cd DTVMDotfiles
fi

echo "✅ Repository ready"
echo ""

# Release files
echo "🔓 Releasing configuration files..."
bash ./release.sh

echo ""
echo "🚀 Running init.sh..."
bash ../init.sh

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  ✅ Setup Complete!                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
```

保存为 `setup-dtvm.sh`，然后运行：

```bash
bash setup-dtvm.sh
# 或指定目录
bash setup-dtvm.sh /path/to/target
```

## 📝 Snippet 配置完整示例

如果你的 `shellscript.json` 是新的或为空，使用完整模板：

```json
{
    "Setup DTVMDotfiles": {
        "prefix": "setup-dtvm",
        "body": [
            "#!/bin/bash",
            "",
            "# One-click setup for DTVMDotfiles",
            "# This script clones DTVMDotfiles, releases files, and runs init",
            "",
            "set -e",
            "",
            "GITHUB_REPO=\"https://github.com/abmcar/DTVMDotfiles.git\"",
            "TARGET_DIR=\"${1:-.}\"",
            "",
            "echo \"╔════════════════════════════════════════════════════════════════╗\"",
            "echo \"║        Setting up DTVMDotfiles                                 ║\"",
            "echo \"╚════════════════════════════════════════════════════════════════╝\"",
            "echo \"\"",
            "",
            "# Clone repository",
            "if [ -d \"$TARGET_DIR/DTVMDotfiles\" ]; then",
            "    echo \"📥 Updating existing DTVMDotfiles...\"",
            "    cd \"$TARGET_DIR/DTVMDotfiles\"",
            "    git pull",
            "else",
            "    echo \"📥 Cloning DTVMDotfiles...\"",
            "    cd \"$TARGET_DIR\"",
            "    git clone \"$GITHUB_REPO\"",
            "    cd DTVMDotfiles",
            "fi",
            "",
            "echo \"✅ Repository ready\"",
            "echo \"\"",
            "",
            "# Release files",
            "echo \"🔓 Releasing configuration files...\"",
            "bash ./release.sh",
            "",
            "echo \"\"",
            "echo \"🚀 Running init.sh...\"",
            "bash ../init.sh",
            "",
            "echo \"\"",
            "echo \"╔════════════════════════════════════════════════════════════════╗\"",
            "echo \"║                  ✅ Setup Complete!                           ║\"",
            "echo \"╚════════════════════════════════════════════════════════════════╝\""
        ],
        "description": "Clone DTVMDotfiles, release files, and run init.sh in one command"
    }
}
```

## 💡 使用场景

### 场景 1: 在新环境快速设置

```bash
# 在新机器的终端中
mkdir -p ~/workspace
cd ~/workspace

# 使用 Snippet 或直接运行
bash setup-dtvm.sh
```

### 场景 2: 在 VS Code 中创建脚本文件

1. 新建文件 `setup-dtvm.sh`
2. 输入 `setup-dtvm` + `Tab`
3. 自动填充整个脚本
4. 保存文件
5. 在终端运行：`bash setup-dtvm.sh`

### 场景 3: 指定安装目录

```bash
bash setup-dtvm.sh /opt/my-project
# 会克隆到 /opt/my-project/DTVMDotfiles
# 释放文件到 /opt/my-project
# 运行 /opt/my-project/init.sh
```

## 🎯 Snippet 变量说明

- `${1:-.}` - 第一个参数（目标目录），默认为当前目录 (`.`)
- `$GITHUB_REPO` - DTVMDotfiles GitHub 仓库地址
- `$TARGET_DIR` - 目标安装目录

## ✅ 验证 Snippet 配置

配置完成后，验证：

1. 打开一个 `.sh` 文件
2. 输入 `setup-dtvm` 看是否有自动完成提示
3. 按 `Tab` 或 `Enter` 展开 snippet
4. 检查代码是否正确填充

## 📚 更多 Snippet 技巧

### 自定义 Prefix

如果想用更短的前缀，修改 `prefix`：

```json
"prefix": "dtvm"  // 改为输入 "dtvm" 就能触发
```

### 添加占位符

在 snippet 中添加可编辑的占位符：

```json
"body": [
    "TARGET_DIR=\"${1:./workspace}\"",  // 占位符，可以 Tab 切换编辑
    "echo \"Setting up in ${1}...\""
]
```

### 条件代码片段

创建多个 snippet 用于不同场景：

```json
{
    "Setup DTVMDotfiles Current Dir": {
        "prefix": "setup-dtvm-here",
        "body": ["bash setup-dtvm.sh"],
        "description": "Setup DTVMDotfiles in current directory"
    },
    "Setup DTVMDotfiles Custom Path": {
        "prefix": "setup-dtvm-path",
        "body": ["bash setup-dtvm.sh ${1:path/to/target}"],
        "description": "Setup DTVMDotfiles in specified directory"
    }
}
```

## 🆘 常见问题

**Q: Snippet 没有出现在自动完成中**
A: 确保：
1. 文件保存为正确的格式（JSON）
2. 使用了正确的语言标识符（shellscript 或 bash）
3. VS Code 已重新加载或重启

**Q: 如何修改已有的 Snippet？**
A: 重新打开 Snippets 文件，找到对应的 snippet 编辑即可

**Q: 可以在所有文件类型中使用吗？**
A: 不行，Snippet 只在指定的语言中生效。要在所有文件中使用，需要配置在 `Global Snippets File`（在最后一个选项）

---

现在你可以在任何新环境中，通过输入 `setup-dtvm` snippet 来一键部署整个 DTVMDotfiles 系统！
