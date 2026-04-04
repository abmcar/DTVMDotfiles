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
- **compiler-agent**: Changes in `src/compiler/` (CGIR passes, MIR, peephole patterns, x86 codegen)
- **evm-agent**: Changes in `src/evm/`, `src/runtime/`, `src/vm/` (opcode handlers, gas metering, spec tests)
- **perf-agent**: Profiling, benchmark analysis, optimization proposals
- Use parallel dispatch when tasks touch independent domains (e.g., compiler + evm simultaneously)
- Use sequential dispatch when output from one task feeds into another

### Research First (EnterPlanMode)
- New features, architecture changes, or breaking changes
- Ambiguous requirements where scope is unclear
- Multi-file refactors affecting 5+ files
- Performance work requiring profiling before coding

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

When creating a git worktree, always run `tools/worktree-init.sh <path>` after creation
to initialize submodules (`evmc/`, `tests/wast/spec`). Without this, cmake will fail.

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
