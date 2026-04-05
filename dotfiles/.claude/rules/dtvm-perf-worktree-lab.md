---
description: Local DTVM EVM performance lab with branch worktrees and persistent baseline/evmone resources. Use when preparing or pruning local perf experiment environments, keeping worktrees under control during repeated optimization work, or managing the persistent baseline at /home/abmcar/dtvm-baseline.
globs: []
alwaysApply: false
---

# DTVM Perf Worktree Lab

Keep the local performance environment minimal and reproducible.

Use this rule for local perf iteration workflow, not CI reproduction. For CI
job flags and `.ci/run_test_suite.sh`, see
`.claude/rules/dtvm-build-config.md`. For running evmone benchmarks or
before/after comparisons, see
`.claude/commands/dtvm-evmone-benchmark.md`.

## Permanent Resources (never delete)

These two resources are persistent infrastructure. Do not remove them under
any circumstances, even during cleanup:

- `/home/abmcar/dtvm-baseline` — git worktree tracking `upstream/main`,
  built at `build-baseline/`. Refresh with `git fetch upstream` + checkout;
  rebuild incrementally only when upstream/main has changed.
- `/home/abmcar/evmone` — the single canonical evmone installation
  (bench, statetest, unittests, evmc CLI all built here).

## Workflow

1. Keep the following long-lived directories unless the user says otherwise:
   - `/home/abmcar/DTVM` — repo root
   - `/home/abmcar/dtvm-baseline` — persistent baseline worktree (see above)
   - `/home/abmcar/evmone` — canonical evmone installation
   - one active branch worktree for the current optimization branch
2. Do not create temporary detached baseline worktrees. The persistent
   `/home/abmcar/dtvm-baseline` worktree serves this purpose; refresh it with
   `git fetch upstream && git checkout upstream/main` instead.
3. Treat `git worktree list` as authoritative for DTVM worktrees.
4. Benchmarking passes `libdtvmapi.so` as an EVMC command-line argument.
   Never copy `.so` files into the evmone directory.
5. **The `.so` file must be named `libdtvmapi.so`** — never rename it (e.g.
   `libdtvmapi_loopaware.so`). EVMC loader derives the create-function
   symbol from the filename (`lib` stripped, extensions removed →
   `evmc_create_dtvmapi`). A different filename produces a wrong symbol
   lookup and fails with "EVMC create function not found".
6. **Always reference the `.so` at its original build path** — do not copy
   it to `/tmp/` or anywhere else. The baseline and branch builds live in
   separate worktrees (`dtvm-baseline/build-baseline/lib/libdtvmapi.so`
   vs `<branch>/build/lib/libdtvmapi.so`), so they never collide.
   There is no reason to create intermediate copies.

## Worktree Rules

- For a branch worktree, use `git worktree add <path> -b <branch-name>`.
- Always run `git submodule update --init --recursive` in a fresh DTVM worktree
  before configuring it.
- Remove stale branch worktrees with `rm -rf <path> && git worktree prune`.
  Do not use `git worktree remove` — it fails on worktrees with submodules.
- Never remove `/home/abmcar/dtvm-baseline` — it is a permanent resource.

## evmone Rules

- `/home/abmcar/evmone` is the single canonical evmone installation.
  Do not clone additional evmone copies or create `evmone-for-test-*`
  directories.
- Do not copy `libdtvmapi.so` into the evmone directory. Pass the library
  path as the EVMC VM string argument to `evmone-bench` instead.
- If stale `evmone-for-test-*` directories appear, delete them.

## Baseline Refresh

To update the persistent baseline to the latest upstream/main:

```bash
git -C /home/abmcar/dtvm-baseline fetch upstream
git -C /home/abmcar/dtvm-baseline checkout upstream/main
# Rebuild only if upstream/main changed since the last build:
cmake --build /home/abmcar/dtvm-baseline/build-baseline --target dtvmapi -j$(nproc)
```

For the initial build (e.g., on a fresh machine), see
[references/lab-playbook.md](references/lab-playbook.md).

## Output Requirements

When using this rule, always report:

- which directories are being kept
- which directories are being created
- which directories are being removed
- which worktree is the active branch worktree

## References

- See `.claude/commands/dtvm-evmone-benchmark.md` for benchmark run commands
  and before/after comparison workflow.
