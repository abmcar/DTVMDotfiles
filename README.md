# DTVMDotfiles

DTVM 的个人 AI 开发环境配置仓库。它管理项目级 Claude/Codex/Gemini
规则、hooks、子 agent、测试辅助文件，以及不会进入 DTVM origin 的个人
DTVM skills。

## 所有权边界

这里有两个不同的 Git 所有权域：

- **DTVMDotfiles origin**：保存个人工作流、项目级 AI 配置和
  `skills/` SSOT；这些内容可以在 DTVMDotfiles 中提交和推送。
- **DTVM origin**：保存 DTVM 产品代码和仓库自带的 skills；本仓库不会把
  个人 skill 源文件提交或推送到 DTVM。

`release.sh` 会像过去一样在本机 DTVM checkout 中部署配置，并从
`CLAUDE.md` 刷新本地 `AGENTS.md`。后者是 DTVM tracked 文件，因此
checkout 可能显示 `M AGENTS.md`；脚本不会 stage、commit 或 push 它。这是
本地派生状态，不改变上述 Git 所有权边界。

## 两类同步模型

| 内容 | SSOT | 部署/收集方向 |
|---|---|---|
| 项目 dotfiles | `DTVMDotfiles/dotfiles/` | `release.sh` 部署到 DTVM；若先在 DTVM 中编辑，必须先用 `store.sh` 收回 |
| 个人 DTVM skills | `DTVMDotfiles/skills/` | 直接编辑 SSOT，再用 `release.sh` 协调用户级链接；不从 DTVM 或 home 目录复制回来 |

`diff.sh` 检查 manifest 管理的项目 dotfiles 漂移。个人 skill 的派生状态由
release 协调，不进入 DTVM manifest。

## 目录结构

```text
DTVMDotfiles/
├── release.sh                 # 统一部署入口
├── skills.sh                  # personal-skill check/sync 入口
├── store.sh                   # DTVM workspace → dotfiles/ SSOT
├── diff.sh                    # manifest 管理内容的漂移检查
├── setup_from_dotfiles.sh     # 新机器 bootstrap
├── worktree-init.sh           # DTVM worktree 初始化与状态协调
├── lib/                       # 同步和 personal-skill 协调逻辑
├── skills/                    # 个人 skill SSOT
│   ├── active/                # release 后可被 Claude/Codex 发现
│   ├── incubator/             # 开发中，不发布
│   └── retired/               # 保留历史，不发布
├── docs/changes/              # 跨模块变更设计记录
└── dotfiles/
    ├── CLAUDE.md              # DTVM 项目级 AI 指南 SSOT
    ├── CLAUDE.local.md.template
    ├── init.sh
    ├── exclude.map.sh
    ├── skills.map.sh          # 要在 Codex 中按 worktree 禁用的 legacy repo skills
    ├── .claude/               # rules、commands、agents、hooks、settings
    ├── perf/                  # 性能录制脚本和固定语料
    └── tools/                 # 本地验证工具
```

## 个人 skill 生命周期

只有 `skills/active/<name>/` 的直接子目录会被发布：

```text
~/.agents/skills/<name>
    -> <DTVMDotfiles>/skills/active/<name>

~/.claude/skills/<name>
    -> <DTVMDotfiles>/skills/active/<name>
```

发布是逐 skill 协调，不会替换整个 `~/.agents/skills` 或
`~/.claude/skills`。如果目标名称已经被普通文件、目录或其他来源的软链接
占用，release 会失败并保留该对象；请先确认所有者，再显式解决冲突。

当前个人 DTVM skills：

| Skill | 职责 |
|---|---|
| `dtvm-worktree-bootstrap` | 创建并初始化 DTVM worktree，从 CI SSOT 派生 CMake，并执行 `dtvmapi` 构建硬门槛 |
| `dtvm-cold-compile-profile` | 生成 identity-guarded、integrity-checked 的冷编译 baseline bundle，并单列继承子进程开销 |
| `dtvm-compiler-path-analysis` | 从 bundle 把已测热点映射到当前 EVM → dMIR → CGIR → RA → MC/object 源码路径和最小 seam |
| `dtvm-write-report` | 把技术、性能和实验结果写成结论优先的读者报告，并用确定性 lint 阻止主次失衡、QA 标签泄漏和实验术语误用 |
| `dtvm-compile-time-optimize` | 仅在显式调用时编排 profile → 分析 → compiler-agent 最小实现 → 同条件配对 benchmark 与正确性验证 |

每个 skill 保持单一职责；详细 reference、script 或 asset 只在对应任务需要时
加载。组合流程放在 orchestrator skill 中，不复制各子 skill 的全部正文。

生命周期操作示例：

```bash
cd /path/to/DTVM/DTVMDotfiles

# incubator 中完成并评审后再发布
git mv skills/incubator/example skills/active/example
bash release.sh

# 退休时保留历史，同时移除 DTVMDotfiles 拥有的发现链接
git mv skills/active/example skills/retired/example
bash release.sh
```

目录移动只修改 SSOT；必须运行 `release.sh` 才会协调用户目录中的派生状态。

## 旧 DTVM skills 的处理

DTVM checkout 中现有的以下 tracked skills 不会被修改或删除：

- `.agents/skills/dtvm-perf-profile`
- `.agents/skills/dmir-compiler-analysis`

`release.sh` 只在 `~/.codex/config.toml` 的 DTVMDotfiles 标记块中，为 Git
当前已知的每个 DTVM worktree 写入这两个 skill 的精确禁用路径。为避免 TOML
数组表改变后续裸键的作用域，managed block 固定在文件末尾；块外字节保持原
顺序和内容。

```toml
# BEGIN DTVMDotfiles managed agent skills
# generated [[skills.config]] entries
# END DTVMDotfiles managed agent skills
```

要禁用的 tracked skill 名称由 `dotfiles/skills.map.sh` 中值为
`legacy-repo` 的条目声明。

项目级 `CLAUDE.md`、生成的 `AGENTS.md` 和 `GEMINI.md` 使用正向路由，把
新任务交给上表中的个人 skills。旧 skill 仅可作为编写替代流程时的历史来源，
不再作为工作流入口。

Codex 配置和 skill 发现通常在会话启动时读取。release 成功后，请开启新会话；
如客户端仍显示旧状态，再重启客户端。

## 安装

前置要求：

- Git
- Bash 4.3 或更高版本
- `iconv`
- 首次 clone 和安装工具时可用的网络连接

在已有 DTVM checkout 根目录中运行一键 bootstrap：

```bash
cd /path/to/DTVM
bash <(curl -s https://raw.githubusercontent.com/abmcar/DTVMDotfiles/main/setup_from_dotfiles.sh)
```

或手动安装：

```bash
cd /path/to/DTVM
git clone https://github.com/abmcar/DTVMDotfiles.git
cd DTVMDotfiles
bash release.sh
bash ../init.sh
```

完整说明和冲突处理见 [SETUP_GUIDE.md](SETUP_GUIDE.md)。

## `release.sh` 部署结果

项目 checkout 中会得到 manifest 管理的 `.claude/`、`CLAUDE.md`、
`init.sh`、性能语料和工具等文件，并生成：

- `.claude/.dtvm-manifest.json`
- 从 `CLAUDE.md` 派生的 `AGENTS.md` 和 `GEMINI.md`
- 从 `exclude.map.sh` 派生的 `.git/info/exclude`
- 与 `.claude/commands/` 对应的用户级 Codex prompts

用户目录中还会得到：

- 两套逐 skill 软链接；
- `~/.codex/config.toml` 中唯一的 DTVMDotfiles 管理块。

`CLAUDE.local.md` 是机器本地文件，不在 `MIRRORED_ITEMS` 中。首次 bootstrap
仅在文件不存在时从 template 生成，之后 release/store 都不会触碰它。
其中 `AGENTS.md` 在 DTVM 中是 tracked 文件，但这里只作为本地生成副本更新；
不要在 DTVM checkout 中 stage 或 push 这份派生 diff。

## 日常工作流

### 更新个人 skills 或从远端部署

```bash
cd /path/to/DTVM/DTVMDotfiles
git pull
bash release.sh
```

编辑个人 skill 时直接修改 `skills/` 下的 SSOT，验证后提交到
DTVMDotfiles：

```bash
bash release.sh
bash skills.sh check
git add skills
git commit -m "skills: update DTVM compile workflow"
git push
```

不要把这些文件复制到 DTVM 的 tracked `.agents/skills/` 中。

### 从 DTVM workspace 收回项目 dotfiles

如果修改的是 DTVM workspace 中受 manifest 管理的 `.claude/`、
`CLAUDE.md` 等文件：

```bash
cd /path/to/DTVM/DTVMDotfiles
bash store.sh
git add -A
git commit -m "dotfiles: update DTVM guidance"
git push
```

这里顺序很重要：workspace 中有尚未 store 的变更时，不要先运行
`release.sh`。

### 检查项目 dotfiles 漂移

```bash
cd /path/to/DTVM/DTVMDotfiles
bash diff.sh
```

### 初始化 worktree

优先调用 `dtvm-worktree-bootstrap`。底层入口是：

```bash
bash DTVMDotfiles/worktree-init.sh [--minimal] /absolute/path/to/worktree
```

初始化完成后会再次协调 personal skills 和 Codex 的已知-worktree 精确路径。

需要只检查或只协调 personal-skill 派生状态时：

```bash
bash DTVMDotfiles/skills.sh check  # 只读
bash DTVMDotfiles/skills.sh sync   # 写入 links 和 managed config block
```

## 安全与恢复

- manifest 管理的本地文件若已改变，release 默认中止并提示先
  `store.sh`；即使文件已从新版 manifest 移除，也会先做同样的 hash gate。
  对移除项显式使用 `RELEASE_FORCE=1` 时，release 会先备份到
  `${XDG_STATE_HOME:-$HOME/.local/state}/DTVMDotfiles/release-backups/`
  再删除，个人内容不会留在 DTVM worktree。
- 若待移除路径已被 DTVM Git 跟踪，无论内容 hash 是否匹配都拒绝删除。
- release 在写入项目 dotfiles 前会预检全部 personal-skill 目标和 Codex
  managed block；foreign collision 或 marker 异常不会留下半次 release。
- `RELEASE_CHECK=1 bash release.sh` 会执行完整的 no-write dry run。
- `RELEASE_FORCE=1` 只用于用户明确决定覆盖 manifest 管理的项目文件；它
  不代表可以接管 foreign skill 目标。
- personal-skill 冲突必须由用户确认所有者后处理。不要对共享的
  `~/.agents/skills` 或 `~/.claude/skills` 运行递归删除。
- 如果 DTVMDotfiles checkout 被移动，指向旧绝对路径的链接会被当作 foreign
  collision。确认旧链接确实属于已废弃 checkout 后，只删除该精确链接，再
  运行 `skills.sh sync`；协调器不会自动接管它。
- 预检通过后的其他阶段若失败，之前独立且安全的步骤可能已经完成。修复报告
  的具体问题后重复运行 `release.sh`；协调过程设计为幂等。
- `AGENTS.md` 和 `GEMINI.md` 是 `CLAUDE.md` 的本地派生副本，不要直接编辑；
  发布前后用 `git diff --cached --quiet` 确认 DTVM index 仍为空，并确认
  DTVM tracked `.agents/skills/**` 没有 diff。

## 命令速查

| 需求 | 命令 |
|---|---|
| 新机器 bootstrap | `bash setup_from_dotfiles.sh` |
| 部署全部派生状态 | `cd DTVMDotfiles && bash release.sh` |
| 检查 personal skills | `cd DTVMDotfiles && bash skills.sh check` |
| 协调 personal skills | `cd DTVMDotfiles && bash skills.sh sync` |
| 收回项目 dotfiles | `cd DTVMDotfiles && bash store.sh` |
| 检查项目 dotfiles 漂移 | `cd DTVMDotfiles && bash diff.sh` |
| 更新并发布 | `cd DTVMDotfiles && git pull && bash release.sh` |
| 初始化 DTVM worktree | `bash DTVMDotfiles/worktree-init.sh <path>` |
