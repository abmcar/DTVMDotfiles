---
description: Local DTVM EVM performance lab with branch worktrees and the persistent evmone resource. Use when preparing or pruning local perf experiment environments, or keeping worktrees under control during repeated optimization work.
paths:
  - "src/compiler/**"
  - "src/evm/**"
  - "src/runtime/**"
---

# DTVM Perf Worktree Lab

For CI reproduction see `.claude/rules/dtvm-build-config.md`. For evmone
benchmark commands see `.claude/commands/dtvm-evmone-benchmark.md`.

## Permanent Resources (never delete, never recreate)

- `~/evmone` — canonical evmone install (bench, statetest, unittests, evmc CLI).

Long-lived directories kept unless the user says otherwise: DTVM repo root,
`~/evmone`, and one active branch worktree per optimization branch. Never
create additional evmone clones or `evmone-for-test-*` directories; delete any
stale `evmone-for-test-*` if found. Treat `git worktree list` as authoritative.

## Baseline for Comparison

There is no persistent baseline worktree. When a perf comparison needs an
`upstream/main` baseline, produce it on demand and PIN it to `upstream/main`
(branching from the current HEAD would benchmark the branch against itself):
`git worktree add .worktrees/baseline-main -b baseline-main upstream/main`, run
`bash DTVMDotfiles/worktree-init.sh .worktrees/baseline-main`, configure with
the EVM flags from `.claude/rules/dtvm-local-test.md`, build `dtvmapi`, then
verify `git -C .worktrees/baseline-main rev-parse HEAD` equals `upstream/main`
before benchmarking its `build/lib/libdtvmapi.so`. Remove the worktree
afterward. Do not recreate a permanent `~/dtvm-baseline`. See
`.claude/commands/bench-compare.md` for the full recipe.

## Branch Worktrees

- **Create**: use the `worktree-bootstrap` skill, which runs submodule init
  and dotfiles sync via `DTVMDotfiles/worktree-init.sh`. Place worktrees
  under `.worktrees/` (gitignored). Do NOT use raw `git worktree add` +
  manual submodule/dotfiles steps. Never `git checkout -b` an experimental
  branch (perf, algorithm, SPP) in the primary checkout (repo root); create it
  in a `.worktrees/` worktree, even when branching from a clean `main`. Note:
  `worktree-bootstrap` uses `.worktrees/`;
  the `EnterWorktree` tool uses `.claude/worktrees/`. Both are gitignored; this
  rule governs `.worktrees/` created via `worktree-bootstrap`.
- **Remove**: `rm -rf <path> && git worktree prune`.
  Do NOT use `git worktree remove` — fails on worktrees with submodules.

## libdtvmapi.so Rules

- **Filename must be `libdtvmapi.so`** — EVMC loader derives
  `evmc_create_dtvmapi` from the stem; renames break symbol lookup.
- **Reference the .so at its build path** — never copy to `~/evmone/`,
  `/tmp/`, or anywhere else. Pass the path as the EVMC VM string to
  `evmone-bench`.

## Forbidden Artifacts

`.ci/run_test_suite.sh` is for disposable CI containers. **Never run it from
the DTVM root locally.** If run, it leaves:

| Path | Cause |
|------|-------|
| `<repo>/evmone/`, `<repo>/evmone-statetest/` | `run_test_suite.sh` clones evmone here (grep the script for `git clone`) |
| `<repo>/asmjit/` | cloned by the CI workflow's "Clone asmjit" step, **not** by `run_test_suite.sh` — appears only in a full-CI run |
| `~/evmone/libdtvmapi*.so` | stale `.so` from manual copy / older CI (current script moves/copies `build/lib/*` into the cloned evmone dir, not `~/evmone`) |

Delete if present:
```bash
rm -rf evmone/ evmone-statetest/ asmjit/
rm -f ~/evmone/libdtvmapi*.so
```

## Sub-agent Dispatch

When dispatching test/perf sub-agents, tell them to run tests via
`tools/dtvm_local_test.sh` (it enforces the run cwd, artifact existence,
non-empty gtest filter, and the right `-k fork_Cancun` per corpus). Also include:

- Do not run `.ci/run_test_suite.sh` locally.
- Do not copy `.so` files; pass the absolute `$(pwd)/` path as the EVMC argument.
- Create worktrees via the `worktree-bootstrap` skill, not raw `git worktree add`.

## Output Requirements

When using this rule, always report which directories are being kept, created,
removed, and which worktree is the active branch worktree.
