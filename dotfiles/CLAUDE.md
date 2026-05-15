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
- **doc-agent**: Change document creation/update, module spec maintenance
- Use parallel dispatch when tasks are independent
- Use sequential dispatch when output from one task feeds into another
- Standard pipeline: research-agent → compiler-agent → test-agent → perf-agent
- Builder-Validator: compiler-agent implements, test-agent validates correctness (no Edit/Write), perf-agent validates performance
- Specialized agents (compiler, doc, perf, research, test) cannot spawn sub-agents.
  When a task requires sub-dispatching (e.g., build + test in one agent),
  use `subagent_type: "general-purpose"` with role constraints in the prompt
- Agent worktrees (`isolation: "worktree"`) are auto-bootstrapped by the
  SessionStart hook, which delegates to `DTVMDotfiles/worktree-init.sh`
  (submodule init + dotfiles sync). As fallback, include in the agent
  prompt: "Run `bash DTVMDotfiles/worktree-init.sh .` before any build."

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
  cap 3, with `model: "opus"` set explicitly.
- After merge: use the `archive` skill to move the change to
  `docs/_archive/<YYYY-MM>/`.

### Dotfiles Sync Rule
Whenever any file managed by DTVMDotfiles is modified (see `MIRRORED_ITEMS` in
`DTVMDotfiles/lib/sync_common.sh`), you **must** sync before the conversation
ends:
```bash
bash DTVMDotfiles/store.sh
cd DTVMDotfiles && git add -A && git commit -m "<message>" && git push && cd ..
```

**Hazard**: never run `release.sh` between editing a managed repo-root file
and running `store.sh` — `release.sh` will overwrite your edits with the
`DTVMDotfiles/dotfiles/` SSOT copy. `AGENTS.md` / `GEMINI.md` are generated
from `CLAUDE.md` by `release.sh`; don't edit them directly.

Full architecture (manifest mechanism, what's managed, worktree symlinks): see
`.claude/rules/dtvm-dotfiles-usage.md`.

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

**Before creating commits/PRs:** follow `.claude/rules/commit-conventions.md`.

## Worktrees

Use the `worktree-bootstrap` skill to create DTVM worktrees (under
`.worktrees/`, gitignored). It wraps `DTVMDotfiles/worktree-init.sh` to do
submodule init + dotfiles symlink in one step. Mechanics and detailed rules:
see `.claude/rules/dtvm-perf-worktree-lab.md`.

**Hazard rule**: **MUST** use `worktree-bootstrap` when adding experimental
changes (performance optimizations, algorithm changes, SPP activation, etc.)
on a branch that already has an open PR or reviewed commits. Generic worktree
skills are not a substitute — they don't init submodules or sync dotfiles.

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
