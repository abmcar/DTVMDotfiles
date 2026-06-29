---
description: Local DTVM EVM performance lab with branch worktrees and the persistent evmone resource. Use when preparing or pruning local perf experiment environments, or keeping worktrees under control during repeated optimization work.
globs: []
alwaysApply: false
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
`upstream/main` baseline, produce it on demand: via the `worktree-bootstrap`
skill create a throwaway worktree on `upstream/main`, build
`cmake --build build --target dtvmapi -j$(nproc)`, benchmark against its
`build/lib/libdtvmapi.so`, then remove the worktree. Do not recreate a
permanent `~/dtvm-baseline`.

## Branch Worktrees

- **Create**: use the `worktree-bootstrap` skill, which runs submodule init
  and dotfiles sync via `DTVMDotfiles/worktree-init.sh`. Place worktrees
  under `.worktrees/` (gitignored). Do NOT use raw `git worktree add` +
  manual submodule/dotfiles steps. Note: `worktree-bootstrap` uses `.worktrees/`;
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

When dispatching test/perf sub-agents, attach the "Common Mistakes" section
of `.claude/rules/dtvm-local-test.md` to the prompt. Also include:

- Do not run `.ci/run_test_suite.sh` locally.
- Do not copy `.so` files; pass the absolute `$(pwd)/` path as the EVMC argument.
- Create worktrees via the `worktree-bootstrap` skill, not raw `git worktree add`.

## Output Requirements

When using this rule, always report which directories are being kept, created,
removed, and which worktree is the active branch worktree.
