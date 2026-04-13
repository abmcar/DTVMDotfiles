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
- **compiler-agent**: All `src/` code changes (compiler, EVM interpreter, runtime, VM core)
- **perf-agent**: Profiling, benchmark analysis, performance comparison
- **test-agent**: Running test suites, CI reproduction, test result analysis
- **research-agent**: Codebase exploration, web research, information gathering (read-only)
- Use parallel dispatch when tasks are independent
- Use sequential dispatch when output from one task feeds into another
- Standard pipeline: research-agent → compiler-agent → test-agent → perf-agent
- Builder-Validator: compiler-agent implements, test-agent validates correctness (no Edit/Write), perf-agent validates performance

### Research First (EnterPlanMode)
- New features, architecture changes, or breaking changes
- Ambiguous requirements where scope is unclear
- Multi-file refactors affecting 5+ files
- Performance work requiring profiling before coding

## Development Workflow

All non-trivial changes follow a unified flow that combines the project's `dev-workflow` skill
with superpowers skills. Simple bug fixes or single-file edits may skip to step 3.

### 1. Brainstorm + Propose
- Use `superpowers:brainstorming` to explore intent and requirements
- Output: a change document in `docs/changes/YYYY-MM-DD-<slug>/README.md`
  - **Full tier** (`template.md`): cross-module, architecture, new capabilities
  - **Light tier** (`template-light.md`): single-module, well-scoped improvements

### 2. Plan
- Use `superpowers:writing-plans` to create an implementation plan
- Plan must reference the change doc and consult relevant `docs/modules/` specs
- Write implementation phases back into the change doc (Full tier)

### 3. Execute
- Use `superpowers:executing-plans` or `superpowers:subagent-driven-development`
- Apply `superpowers:test-driven-development` where applicable
- **MUST** use `superpowers:using-git-worktrees` when adding experimental changes
  (performance optimizations, algorithm changes, SPP activation, etc.) on a branch
  that already has an open PR or reviewed commits. Never experiment directly on a
  branch with work you can't afford to lose.
- After each logical unit: build gate → test gate → format gate

### 4. Verify
- Use `superpowers:verification-before-completion` before claiming done
- Run full test suite and benchmark comparison (if perf-related)
- Update change doc status to `Implemented`

### 5. PR + Review
- Use `superpowers:requesting-code-review` to create PR
- Use `superpowers:receiving-code-review` when handling feedback
- Resolve review threads via GraphQL after fixing

### 6. Archive (after merge)
- Use the `archive` skill to move completed change to `docs/_archive/<YYYY-MM>/`
- Clean up branch and worktree

### Dotfiles Sync Rule
Whenever any file managed by DTVMDotfiles is modified (see `MIRRORED_ITEMS` in
`DTVMDotfiles/lib/sync_common.sh` — includes `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`,
`init.sh`, `perf/*.sh`, `perf/*.hex`), you **must** sync before the conversation ends:
```bash
bash DTVMDotfiles/store.sh
cd DTVMDotfiles && git add -A && git commit -m "<message>" && git push && cd ..
```

## Context Management
- Delegate specialized work to reduce context pollution
- Domain knowledge lives in `.claude/rules/` and `.claude/commands/`
- Upstream skills remain in `.agents/skills/`

## Quality Gates

**Before finishing any code task, verify:**
1. `tools/format.sh check` passes
2. Changed code compiles: `cmake --build build --target <relevant_target>`
3. Relevant tests pass (EVM spec tests for evm/runtime changes, unit tests for compiler)
4. No new compiler warnings in build output
5. Comments are in English, naming follows LLVM conventions

**Before creating commits/PRs:**
- Follow conventions in `.claude/rules/commit-conventions.md`
- PR description includes what changed and why

## Worktrees

When creating a git worktree, run `git -C <path> submodule update --init` after creation
to initialize submodules (`evmc/`, `tests/wast/spec`). Without this, cmake will fail.

After submodule init, run `bash DTVMDotfiles/worktree-sync.sh <path>` to symlink
Claude Code configuration (rules, commands, hooks, settings) into the worktree.
Without this, a Claude Code session in the worktree will lack all project rules
and commands.

Worktree directories: use `.worktrees/` (project-local, gitignored).

## Build & Test

Treat repository docs and rules as authoritative:
- General build: `docs/start.md`
- CI-faithful EVM build: `.claude/rules/dtvm-build-config.md`
- Perf workflows: `.claude/commands/dtvm-evmone-benchmark.md`, `.claude/commands/dtvm-jit-lowering-inspection.md`
- Profiling: `.agents/skills/dtvm-perf-profile/SKILL.md` (upstream)
- Compiler analysis: `.agents/skills/dmir-compiler-analysis/SKILL.md` (upstream)

## Code Style

Detailed rules auto-loaded from `.claude/rules/cpp-code-style.md` for C++ files.
Run `tools/format.sh format` after modifying code, `tools/format.sh check` before finishing.
