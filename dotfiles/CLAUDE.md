# DTVM Development Guide

DTVM is a deterministic VM with EVM ABI compatibility. Core implementation is in C/C++ under `src/`.

## Key Principles
- Preserve determinism — avoid host-specific, non-deterministic behavior
- Prefer touching `third_party/` only when explicitly required
- Keep edits minimal and localized; follow existing patterns
- Update or add tests when behavior changes
- Never hype a direction as paper-worthy without rigorous novelty evidence

## Task Routing

### Direct Execution
- Single-file bug fixes or small edits
- Format checks, simple git operations
- Code review or explanation of a specific function

### Delegate to Sub-Agent
- **compiler-agent**: All `src/` code changes
- **perf-agent**: Profiling, benchmark analysis, performance comparison
- **test-agent**: Running test suites, CI reproduction, test result analysis
- **research-agent**: Codebase exploration, web research, information gathering (read-only)
- **doc-agent**: Change document creation/update, module spec maintenance
- Use parallel dispatch when tasks are independent

### Research First (EnterPlanMode)
- New features, architecture changes, or breaking changes
- Ambiguous requirements where scope is unclear
- Multi-file refactors affecting 5+ files
- Performance work requiring profiling before coding

## Development Workflow

The default lifecycle (propose → plan → execute → verify-and-archive) is
driven by the upstream `dev-workflow` skill (`.agents/skills/dev-workflow/`).
Simple bug fixes or single-file edits may skip directly to execute.

For **feature implementation** or explicit `/dev-cycle` invocation, escalate
to the opt-in `dev-cycle` skill (`~/claude-sync/skills/dev-cycle/`) — see its
SKILL.md for the full lifecycle. Do not auto-invoke `/dev-cycle` for routine
fixes.

### DTVM-specific constraints (override or supplement skill defaults)

- **Change documents live in `docs/changes/YYYY-MM-DD-<slug>/README.md`**
  inside this repo. This is a project requirement and **overrides** the
  `~/changes/` SSOT default in `CLAUDE.shared.md` — DTVM change docs are
  project artifacts and ship with the PR, not personal drafts.
  - **Full tier** (`template.md`): cross-module, architecture, new capabilities
  - **Light tier** (`template-light.md`): single-module, well-scoped improvements
- Consult relevant `docs/modules/` specs during planning.
- High-stakes review (paper, plan, PR closure, direction-doc): dispatch Opus +
  Codex as parallel reviewers in separate Agent calls; target 1–2 rounds, hard-
  cap 3, with `model: "opus"` set explicitly. Keep this manual two-Agent dispatch
  for interactive reviews; reach for the Workflow tool only when you need
  deterministic round-cap counting or aggregation across many findings — use one
  or the other, not both.
- After merge: only when the user explicitly asks, use the `archive` skill to
  move the change to `docs/_archive/<YYYY-MM>/`; halt at the local `git mv` —
  never open an archive PR (project convention: merged docs otherwise stay in
  `docs/changes/`).

### Dotfiles Sync Rule
Whenever any file managed by DTVMDotfiles is modified (see `MIRRORED_ITEMS` in
`DTVMDotfiles/lib/sync_common.sh`), you **must** sync before the conversation
ends:
```bash
bash DTVMDotfiles/store.sh
cd DTVMDotfiles && git add -A && git commit -m "<message>" && git push && cd ..
```

**Order matters**: never run `release.sh` before `store.sh`. Manifest mechanism,
what's managed, worktree symlinks, the release.sh overwrite hazard, and the
generated `AGENTS.md`/`GEMINI.md`: see `.claude/rules/dtvm-dotfiles-usage.md`.

## Quality Gates

**Before finishing any code task, verify:**
1. `tools/format.sh check` passes
2. Changed code compiles: `cmake --build build --target <relevant_target>`
3. Relevant tests pass — run `tools/dtvm_local_test.sh --auto`, which selects suites by touched path per `.claude/rules/dtvm-local-test.md`
4. No new compiler warnings in build output

**Before creating commits/PRs:** follow `.claude/rules/commit-conventions.md`.

**After `git push` to a branch with an open PR:** follow the CI-watch loop in `.claude/rules/pr-push-ci-watch.md`.

## Worktrees

Create DTVM worktrees with the `worktree-bootstrap` skill (wraps
`DTVMDotfiles/worktree-init.sh`: submodule init + dotfiles symlink; worktrees
under `.worktrees/`, gitignored). **MUST** use it — not a generic worktree
skill or raw `git worktree add`, which won't init submodules or sync dotfiles —
for any experimental branch (perf, algorithm, SPP), whether or not that branch
already has an open PR or reviewed commits. Never `git checkout -b` an
experimental branch in the primary checkout (repo root): that pins the main
checkout off its integration branch. Branch inside a `.worktrees/` worktree
even when starting fresh from a clean `main`.
Resource and mechanics rules: `.claude/rules/dtvm-perf-worktree-lab.md`.

## Where things live

- Delegate specialized work to sub-agents to reduce context pollution.
- Domain knowledge → `.claude/rules/` (most are path-scoped, load on demand) and `.claude/commands/`; upstream skills → `.agents/skills/`.
- General build: `docs/start.md`
- CI-faithful EVM build: `.claude/rules/dtvm-build-config.md`
- Perf workflows: `.claude/commands/dtvm-evmone-benchmark.md`, `.claude/commands/dtvm-jit-lowering-inspection.md`
- Profiling: `.agents/skills/dtvm-perf-profile/SKILL.md`; compiler analysis: `.agents/skills/dmir-compiler-analysis/SKILL.md`

## Code Style

C/C++ style and the `tools/format.sh format` / `check` workflow:
`.claude/rules/cpp-code-style.md` (path-scoped to `src/**`; loads when you touch C++).
