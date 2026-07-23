# DTVMDotfiles 安装与迁移指南

## 适用范围

本指南安装两类内容：

1. 部署到本机 DTVM checkout 的项目级 AI 配置；
2. 从 DTVMDotfiles `skills/active/` 发布到用户级 Claude/Codex 发现目录的
   个人 DTVM skills。

个人 skill 源文件只进入 DTVMDotfiles origin，不进入 DTVM origin。

## 前置条件

- 已有一个 DTVM Git checkout；
- Git；
- Bash 4.3 或更高版本；
- `iconv`（用于验证写入 Codex TOML 的 worktree 路径）；
- 首次 clone 和执行 `init.sh` 时可访问网络；
- `init.sh` 使用 `apt`、`sudo` 和 `npm`，因此当前脚本面向 Linux/WSL
  环境。其他系统可以只运行 release，再自行安装依赖。

建议在安装前先确认 DTVM workspace 没有尚未保存的 dotfiles 修改：

```bash
cd /path/to/DTVM
git status --short
```

## 新机器一键安装

在 DTVM checkout 根目录运行：

```bash
cd /path/to/DTVM
bash <(curl -s https://raw.githubusercontent.com/abmcar/DTVMDotfiles/main/setup_from_dotfiles.sh)
```

`setup_from_dotfiles.sh` 会：

1. 在当前目录 clone `DTVMDotfiles/`，若已存在则执行 `git pull`；
2. 运行 `DTVMDotfiles/release.sh`；
3. 仅在缺少 `CLAUDE.local.md` 时从 template 生成本机 skeleton；
4. 运行 release 出来的 `init.sh`。

可将目标 DTVM checkout 的父级位置作为参数传给脚本：

```bash
bash setup_from_dotfiles.sh /absolute/path/to/DTVM
```

目标目录需要满足 DTVMDotfiles release 对父 DTVM checkout 的要求。

## 手动安装

需要分开控制 release 和依赖安装时：

```bash
cd /path/to/DTVM
git clone https://github.com/abmcar/DTVMDotfiles.git

cd DTVMDotfiles
bash release.sh

# 可选；当前脚本会安装系统和 npm 依赖，并初始化 DTVM 测试资源
bash ../init.sh
```

`release.sh` 是正常部署入口。它会部署 manifest 管理的 project
dotfiles，并调用 personal-skill 协调逻辑。无需单独复制 skill 目录。

## 现有机器迁移

如果已经使用旧版 DTVMDotfiles：

```bash
cd /path/to/DTVM/DTVMDotfiles

# 如果曾在 DTVM workspace 中修改受管 CLAUDE.md/.claude 文件，先收回
bash store.sh

# review 并提交/暂存 store.sh 带回的改动后，再更新 DTVMDotfiles
git pull --ff-only
bash release.sh
bash skills.sh check
```

不要在 workspace 有未 store 的受管变更时先运行 release；manifest gate
会中止并提示正确操作。

旧版 DTVMDotfiles 还管理过
`.agents/skills/worktree-bootstrap/SKILL.md`。新版迁移会移除这份本地旧
副本；若它相对旧 manifest 有修改，release 会在任何部署写入前中止。先运行
`store.sh` 保留内容并 review；确认由新 `dtvm-worktree-bootstrap` 取代后，
显式运行 `RELEASE_FORCE=1 bash release.sh`。强制迁移会先生成
`${XDG_STATE_HOME:-$HOME/.local/state}/DTVMDotfiles/release-backups/` 下的
恢复副本，再移除旧文件；若该路径已被 DTVM Git 跟踪则无条件中止。

迁移不会删除或修改 DTVM tracked 的：

```text
.agents/skills/dtvm-perf-profile
.agents/skills/dmir-compiler-analysis
```

新的 personal skills 使用不同名称。Codex 对旧 skill 的禁用通过
`~/.codex/config.toml` 中的 DTVMDotfiles 管理块完成；Claude/AGENTS/Gemini
通过项目指南的正向路由选择新 skill。

## Personal-skill 命令

`skills.sh` 提供一个只读入口和一个写入入口：

```bash
cd /path/to/DTVM/DTVMDotfiles

# 只检查 active links、foreign collision 和 managed config 状态
bash skills.sh check

# 显式协调 links 与 Codex managed config block
bash skills.sh sync
```

日常更新通常直接运行 `release.sh`，因为它会包含 `skills.sh sync` 的协调。
在只修改 personal skill 生命周期、排查冲突或做集成验证时，可以直接使用
`skills.sh`。

## 部署后的文件

### DTVM checkout

```text
DTVM/
├── DTVMDotfiles/
├── .claude/
│   └── .dtvm-manifest.json
├── CLAUDE.md
├── AGENTS.md                  # 从 CLAUDE.md 生成
├── GEMINI.md                  # 从 CLAUDE.md 生成
├── CLAUDE.local.md            # 本机文件，不参与 release/store
├── init.sh
├── perf/
└── tools/
```

实际 manifest 内容以 `lib/sync_common.sh` 的 `MIRRORED_ITEMS` 为准。
`AGENTS.md` 是 DTVM tracked 文件，但 release 只在本地把它刷新为
`CLAUDE.md` 的派生副本；这可能表现为 `M AGENTS.md`，不等于 personal skill
进入 DTVM origin。不要在 DTVM 中 stage/commit/push 该派生文件。

### 用户目录

每个 active skill 有两条链接，目标都是同一个 DTVMDotfiles SSOT：

```text
~/.agents/skills/<skill-name>
    -> /path/to/DTVM/DTVMDotfiles/skills/active/<skill-name>

~/.claude/skills/<skill-name>
    -> /path/to/DTVM/DTVMDotfiles/skills/active/<skill-name>
```

当前发布的名称是：

```text
dtvm-worktree-bootstrap
dtvm-cold-compile-profile
dtvm-compiler-path-analysis
dtvm-compile-time-optimize
```

`~/.codex/config.toml` 中还会出现一个边界明确的 DTVMDotfiles 管理块。它为
Git 当前知道的每个 DTVM worktree 禁用两个旧的 tracked skill 精确路径。
managed block 固定在文件末尾，避免 `[[skills.config]]` 把后续裸键解释为
最后一个 skill 的字段；块之外的用户配置保持原顺序和内容。

marker 精确为：

```toml
# BEGIN DTVMDotfiles managed agent skills
# generated [[skills.config]] entries
# END DTVMDotfiles managed agent skills
```

## 安装后验证

先运行只读检查：

```bash
cd /path/to/DTVM/DTVMDotfiles
bash skills.sh check
```

然后抽查链接：

```bash
readlink "$HOME/.agents/skills/dtvm-cold-compile-profile"
readlink "$HOME/.claude/skills/dtvm-cold-compile-profile"
```

两者都应解析到当前 DTVMDotfiles checkout 的
`skills/active/dtvm-cold-compile-profile`。

检查 Git 当前知道的 worktree：

```bash
git -C /path/to/DTVM worktree list
```

再打开 `~/.codex/config.toml`，只检查 DTVMDotfiles 标记块是否覆盖这些
worktree。不要把整个配置文件粘贴到日志或 issue 中，因为它可能包含其他
机器本地配置。

最后开启新的 Claude/Codex 会话。若新 skill 或禁用状态仍未生效，重启
客户端。

验证 origin 边界：

```bash
git -C /path/to/DTVM diff --cached --quiet
git -C /path/to/DTVM diff -- \
  .agents/skills/dtvm-perf-profile \
  .agents/skills/dmir-compiler-analysis
```

第一条必须无输出并返回 0；第二条必须无输出。`AGENTS.md` 的本地 tracked
diff 是已知派生状态，但不得进入 DTVM commit。

## 生命周期

### 开发 draft

新 skill 先放在：

```text
DTVMDotfiles/skills/incubator/<name>/
```

`incubator` 不会被发布。保持 `SKILL.md` 入口聚焦于触发条件、任务边界和
工作流，把较长资料放入按需读取的 `references/`。

### 发布

评审通过后：

```bash
cd /path/to/DTVM/DTVMDotfiles
git mv skills/incubator/<name> skills/active/<name>
RELEASE_CHECK=1 bash skills.sh sync
bash skills.sh sync
bash skills.sh check
```

确认后将变更提交到 DTVMDotfiles origin。

### 退休

```bash
git mv skills/active/<name> skills/retired/<name>
bash skills.sh sync
```

内容仍在 DTVMDotfiles 历史中，但该 skill 的 DTVMDotfiles-owned 用户级
链接会被移除。

## Worktree 集成

创建 DTVM worktree 时调用 `dtvm-worktree-bootstrap`。它使用项目专用的
初始化入口：

```bash
bash DTVMDotfiles/worktree-init.sh [--minimal] /absolute/path/to/worktree
```

该入口初始化 submodule、链接项目 dotfiles，并在 Git 能看到新 worktree
之后再次协调 personal skills/Codex 配置。不要用裸
`git worktree add` 代替完整初始化。

如果 worktree 已经由其他方式创建，可在完成项目初始化后运行：

```bash
cd /path/to/DTVM/DTVMDotfiles
bash skills.sh sync
```

如果 worktree 被删除或 prune，再运行一次 sync 会让 managed block 回到
当前 Git worktree 集合。

## 冲突处理

### Foreign skill collision

如果预期链接位置已经存在普通文件、目录或指向其他来源的软链接，sync
会 fail closed，不接管该对象。

安全处理步骤：

1. 记录错误中的精确路径；
2. 用 `ls -ld` 和 `readlink` 判断它由谁管理；
3. 若仍需保留，改名或移到备份位置；
4. 重新运行 `bash skills.sh check`；
5. 无冲突后运行 `bash skills.sh sync`。

不要递归删除 `~/.agents/skills` 或 `~/.claude/skills`。这两个目录是多个
系统共享的命名空间。

### DTVMDotfiles checkout 被移动

发现链接使用绝对路径。若仓库从旧位置移动到新位置，协调器不会把指向旧
checkout 的链接自动认作自己所有；它会按 foreign collision 处理。

先用 `readlink` 确认链接精确指向已废弃的
`<old-DTVMDotfiles>/skills/active/<same-name>`，并确认旧 checkout 不再作为
SSOT。然后只删除报错中的那一条软链接，再运行 `bash skills.sh sync`。不要
删除父目录，也不要用新 release 强制接管无法证明所有权的链接。

### Codex managed block 异常

若 config 中出现重复或不完整 marker，协调逻辑不会猜测边界。先备份：

```bash
cp "$HOME/.codex/config.toml" "$HOME/.codex/config.toml.pre-dtvm-skills"
```

只修复 DTVMDotfiles marker 结构，保留块外内容，然后重新运行 check/sync。

### 当前会话仍显示旧 skill

磁盘协调与进程内 skill discovery 是两个阶段。先让
`bash skills.sh check` 通过，再开启新任务或重启客户端。

### release 在中途停止

release 会在写入任何 project dotfile 前预检 personal-skill 目标、Codex
marker 和即将移除的旧 manifest 文件，因此这些错误会直接中止且不产生
release 写入。预检通过后的其他阶段若失败，较早完成的独立步骤可能已经
落盘；修复具体错误后重复运行 release，不需要先清空用户 skill 目录。

## 隔离检查与测试路径

完整 release dry run：

```bash
cd /path/to/DTVM/DTVMDotfiles
RELEASE_CHECK=1 bash release.sh
```

personal-skill 协调器提供以下环境覆盖，供临时 HOME、测试 repo 或沙箱使用：

| 变量 | 覆盖目标 |
|---|---|
| `DTVMDOTFILES_PARENT_DIR` | DTVM Git repo |
| `DTVMDOTFILES_ACTIVE_SKILLS_DIR` | `skills/active` SSOT |
| `DTVMDOTFILES_SKILLS_MAP_FILE` | legacy repo skill map |
| `DTVMDOTFILES_CODEX_SKILLS_DIR` | Codex/Agents skill discovery 目录 |
| `DTVMDOTFILES_CLAUDE_SKILLS_DIR` | Claude skill discovery 目录 |
| `DTVMDOTFILES_CODEX_CONFIG_FILE` | Codex TOML config |

`RELEASE_CHECK=1 bash skills.sh sync` 也会完成预检和变更计算，但不会创建
目录、链接或 config。`tests/agent_skills_test.sh` 覆盖协调/release/worktree
边界，`tests/profile_cold_compile_test.sh` 覆盖 sealed bundle 和 identity
guards；两者都使用临时状态，不应触碰真实用户配置。

## 更新与回滚

更新：

```bash
cd /path/to/DTVM/DTVMDotfiles
git pull
bash release.sh
bash skills.sh check
```

若要停止发布某个 personal skill，将它移动到 `retired/` 后执行 sync。若要
完全回滚这套机制，应先在仍有新协调脚本的版本中退役 active skills，再只
移除 `~/.codex/config.toml` 的 DTVMDotfiles 标记块，最后回退
DTVMDotfiles。只删除能通过 `readlink` 证明目标位于当前或明确废弃的
`DTVMDotfiles/skills/active/`、且名称一致的精确软链接。

DTVM origin 无需回滚，因为 personal skill 从未进入其中。

## 命令速查

| 目标 | 命令 |
|---|---|
| 完整 bootstrap | `bash setup_from_dotfiles.sh [DTVM-path]` |
| 部署 project dotfiles 和 personal skills | `bash DTVMDotfiles/release.sh` |
| 只读检查 personal-skill 派生状态 | `bash DTVMDotfiles/skills.sh check` |
| 显式协调 personal-skill 派生状态 | `bash DTVMDotfiles/skills.sh sync` |
| 收回 project dotfiles | `bash DTVMDotfiles/store.sh` |
| 检查 project dotfiles 漂移 | `bash DTVMDotfiles/diff.sh` |
| 初始化 worktree | `bash DTVMDotfiles/worktree-init.sh <path>` |
