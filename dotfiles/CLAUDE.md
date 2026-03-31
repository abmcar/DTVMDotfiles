<!-- OPENSPEC:START -->
# Spec Workflow Instructions

These instructions are for AI assistants working in this project.

Always open `@/specs/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/specs/AGENTS.md` to learn:
- How the SSOT and feature workflow are organized
- Which Spec-Kit skills to use
- Project-specific spec, change, and implementation guidelines

Keep this managed block so tooling can refresh the instructions.

<!-- OPENSPEC:END -->

# DTVM Development Guide

## Project Overview

DTVM is a deterministic VM with EVM ABI compatibility. Core implementation is in C/C++ under `src/`.

**Key Principles:**
- Preserve determinism - avoid host-specific, non-deterministic behavior
- Prefer touching `third_party/` only when explicitly required
- Keep edits minimal and localized; follow existing patterns
- Update or add tests when behavior changes

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

## Quality Gates

**Before finishing any code task, verify:**
1. `tools/format.sh check` passes
2. Changed code compiles: `cmake --build build --target <relevant_target>`
3. Relevant tests pass (EVM spec tests for evm/runtime changes, unit tests for compiler)
4. No new compiler warnings introduced
5. Comments are in English, naming follows LLVM conventions

**Before creating commits/PRs:**
- Follow conventions in `.claude/rules/commit-conventions.md`
- PR description includes what changed and why

## Build & Test

Treat repository docs and skills as authoritative:
- General build: `docs/start.md`
- CI-faithful EVM build: `dtvm-build-config` skill
- Perf-oriented builds: relevant perf skills

To use a skill, Read `.agents/skills/<name>/SKILL.md` and follow its workflow.
Available skills: `dtvm-build-config`, `dtvm-evmone-benchmark`, `dtvm-perf-worktree-lab`,
`dtvm-jit-lowering-inspection`, `dtvm-perf-profile`, `dmir-compiler-analysis`.

## Code Style

Detailed rules auto-loaded from `.claude/rules/cpp-code-style.md` for C++ files.
Run `tools/format.sh format` after modifying code, `tools/format.sh check` before finishing.

## Documentation Pointers

- Overview: `README.md`
- Build/testing: `docs/start.md`
- Usage details: `docs/user-guide.md`
- Commit conventions: `docs/COMMIT_CONVENTION.md`
- Spec workflow: `specs/AGENTS.md`
- SSOT overview: `specs/README.md`
