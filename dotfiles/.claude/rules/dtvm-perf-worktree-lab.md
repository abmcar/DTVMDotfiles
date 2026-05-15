---
description: Local DTVM EVM performance lab with branch worktrees and persistent baseline/evmone resources. Use when preparing or pruning local perf experiment environments, keeping worktrees under control during repeated optimization work, or managing the persistent baseline at ~/dtvm-baseline.
globs: []
alwaysApply: false
---

# DTVM Perf Worktree Lab

For CI reproduction see `.claude/rules/dtvm-build-config.md`. For evmone
benchmark commands see `.claude/commands/dtvm-evmone-benchmark.md`.

## Permanent Resources (never delete, never recreate)

- `~/dtvm-baseline` — git worktree on `upstream/main`, build dir `build-baseline/`.
  Refresh with `git -C ~/dtvm-baseline fetch upstream && git -C ~/dtvm-baseline checkout upstream/main`;
  rebuild incrementally only when upstream/main changed:
  `cmake --build ~/dtvm-baseline/build-baseline --target dtvmapi -j$(nproc)`.
- `~/evmone` — canonical evmone install (bench, statetest, unittests, evmc CLI).

Long-lived directories kept unless the user says otherwise: DTVM repo root,
`~/dtvm-baseline`, `~/evmone`, and one active branch worktree per optimization
branch. Never create temporary detached baseline worktrees, additional evmone
clones, or `evmone-for-test-*` directories; delete any stale
`evmone-for-test-*` if found. Treat `git worktree list` as authoritative.

## Branch Worktrees

- **Create**: use the `worktree-bootstrap` skill (wraps
  `DTVMDotfiles/worktree-init.sh` — submodule init + dotfiles sync in one
  step). Place worktrees under `.worktrees/` (gitignored). Do NOT use raw
  `git worktree add` + manual submodule/dotfiles steps. See CLAUDE.md
  Worktrees section.
- **Remove**: `rm -rf <path> && git worktree prune`.
  Do NOT use `git worktree remove` — fails on worktrees with submodules.
  Never remove `~/dtvm-baseline` — it is a permanent resource.

## libdtvmapi.so Rules

- **Filename must be `libdtvmapi.so`** — EVMC loader derives
  `evmc_create_dtvmapi` from the stem; renames break symbol lookup. (Full
  rationale in `.claude/commands/dtvm-evmone-benchmark.md`.)
- **Reference the .so at its build path** — never copy to `~/evmone/`,
  `/tmp/`, or anywhere else. Pass the path as the EVMC VM string to
  `evmone-bench`.

## Forbidden Artifacts

`.ci/run_test_suite.sh` is for disposable CI containers. **Never run it from
the DTVM root locally.** If run, it leaves:

| Path | Cause |
|------|-------|
| `<repo>/evmone/`, `<repo>/evmone-statetest/`, `<repo>/asmjit/` | CI clone/submodule |
| `~/evmone/libdtvmapi*.so` | CI `cp build/lib/*` pattern |
| `<baseline-worktree>/build/` | wrong build dir name (should be `build-baseline/`) |

Delete if present:
```bash
rm -rf evmone/ evmone-statetest/ asmjit/
rm -f ~/evmone/libdtvmapi*.so
```

## Sub-agent Dispatch

When dispatching test/perf sub-agents, attach `.claude/rules/dtvm-local-test.md`
"Common Mistakes" section to the prompt — those bullets (don't run
`.ci/run_test_suite.sh`, don't copy `.so` files, use absolute `$(pwd)/` for
the .so path) are the same warnings agents need. Add one extra reminder
specific to this rule: in baseline worktree use `build-baseline/` not
`build/`, and create worktrees via the `worktree-bootstrap` skill rather
than raw `git worktree add`.

## Output Requirements

When using this rule, always report which directories are being kept, created,
removed, and which worktree is the active branch worktree.
