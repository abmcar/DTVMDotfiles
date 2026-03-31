---
name: dtvm-perf-worktree-lab
description: Set up, maintain, and clean a local DTVM EVM performance lab with branch worktrees and persistent baseline/evmone resources. Use when Codex needs to prepare or prune local perf experiment environments, or keep worktrees under control during repeated optimization work.
---

# DTVM Perf Worktree Lab

Keep the local performance environment minimal and reproducible.

Use this skill for local perf iteration workflow, not CI reproduction. For CI
job flags and `.ci/run_test_suite.sh`, read
`.agents/skills/dtvm-build-config/SKILL.md`. For running evmone benchmarks or
before/after comparisons, read
`.agents/skills/dtvm-evmone-benchmark/SKILL.md`.

## Permanent Resources (never delete)

These two resources are persistent infrastructure. Do not remove them under
any circumstances, even during cleanup:

- `/home/abmcar/dtvm-baseline` — git worktree tracking `upstream/main`,
  built at `build-baseline/`. Refresh with `git fetch upstream` + checkout;
  rebuild incrementally only when upstream/main has changed.
- `/home/abmcar/evmone-bench` — symlink to `evmone-for-test-mulx-adx`,
  the canonical evmone benchmark installation.

## Workflow

1. Keep the following long-lived directories unless the user says otherwise:
   - `/home/abmcar/DTVM` — repo root
   - `/home/abmcar/dtvm-baseline` — persistent baseline worktree (see above)
   - `/home/abmcar/evmone-bench` — persistent evmone benchmark symlink
   - one active branch worktree for the current optimization branch
2. Do not create temporary detached baseline worktrees. The persistent
   `/home/abmcar/dtvm-baseline` worktree serves this purpose; refresh it with
   `git fetch upstream && git checkout upstream/main` instead.
3. Treat `git worktree list` as authoritative for DTVM worktrees.
4. Benchmarking passes `libdtvmapi.so` as an EVMC command-line argument.
   Never copy `.so` files into the evmone directory.

## Worktree Rules

- For a branch worktree, use `git worktree add <path> -b <branch-name>`.
- Always run `git submodule update --init --recursive` in a fresh DTVM worktree
  before configuring it.
- Remove stale branch worktrees with `git worktree remove --force <path>`.
- Never remove `/home/abmcar/dtvm-baseline` — it is a permanent resource.

## evmone Rules

- `/home/abmcar/evmone-bench` is the one canonical evmone installation.
  Do not create topic-named `evmone-for-test-<topic>` directories.
- Do not copy `libdtvmapi.so` into the evmone directory. Pass the library
  path as the EVMC VM string argument to `evmone-bench` instead.
- If stale `evmone-for-test-*` directories accumulate (from old experiments),
  delete them — but never delete `evmone-bench` or `evmone-for-test-mulx-adx`
  (the symlink target).

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

When using this skill, always report:

- which directories are being kept
- which directories are being created
- which directories are being removed
- which worktree is the active branch worktree

## References

- Read [references/lab-playbook.md](references/lab-playbook.md) for concrete
  command patterns and cleanup rules.
- Read `.agents/skills/dtvm-evmone-benchmark/SKILL.md` and its
  `references/benchmark-playbook.md` for benchmark run commands and
  before/after comparison workflow.
