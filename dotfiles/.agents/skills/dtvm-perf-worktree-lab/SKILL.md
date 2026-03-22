---
name: dtvm-perf-worktree-lab
description: Set up, maintain, and clean a local DTVM EVM performance lab with branch worktrees, detached baseline worktrees, and one active evmone-for-test checkout. Use when Codex needs to prepare or prune local perf experiment environments, swap `libdtvmapi.so` into evmone, or keep worktree and evmone clones under control during repeated optimization work.
---

# DTVM Perf Worktree Lab

Keep the local performance environment minimal and reproducible.

Use this skill for local perf iteration workflow, not CI reproduction. For CI
job flags and `.ci/run_test_suite.sh`, use `dtvm-build-config`.

## Workflow

1. Keep only three long-lived directories unless the user says otherwise:
   - repo root, usually `/home/abmcar/DTVM`
   - one active branch worktree for the optimization branch
   - one active `evmone-for-test` checkout used for external EVMC tests
2. Create detached baseline worktrees only when a comparison requires them.
   Remove them immediately after the comparison is done.
3. Treat `git worktree list` as authoritative for DTVM worktrees.
4. Treat the active `evmone-for-test` checkout as disposable cache, not as a
   place to keep multiple historical variants.
5. Rebuild and copy the current `build/lib/libdtvmapi.so` into the active
   evmone checkout before running evmone-based tests or benchmarks.

## Worktree Rules

- For a branch worktree, use `git worktree add <path> -b <branch-name>`.
- For a detached baseline, use `git worktree add <path> <commit-ish>`.
- Always run `git submodule update --init --recursive` in a fresh DTVM worktree
  before configuring it.
- Prefer short-lived detached worktrees for baseline builds instead of checking
  out the branch tip back and forth in the main worktree.
- Remove detached baselines with `git worktree remove --force <path>` as soon
  as the benchmark comparison is complete.

## evmone Rules

- Keep one active `evmone-for-test` checkout for the current line of work.
- Prefer replacing the shared library in place over cloning a new evmone tree
  for every experiment.
- If multiple `evmone-for-test-*` directories accumulate, delete everything
  except the one tied to the active branch.
- If direct `rm -rf` is blocked by policy, use a small Python `shutil.rmtree`
  cleanup instead of leaving stale directories behind.

## Baseline Build Strategy

- For baseline worktrees, avoid re-downloading third-party sources when a local
  build already has populated `FetchContent` sources.
- Reuse local `FETCHCONTENT_SOURCE_DIR_*` overrides when configuring temporary
  baseline builds.
- If only `dtvmapi` is needed for benchmarking, prefer the smallest build that
  can produce `libdtvmapi.so`.

## Output Requirements

When using this skill, always report:

- which directories are being kept
- which directories are being created temporarily
- which directories are being removed
- which worktree is the active branch worktree
- which evmone checkout is the active test checkout

## References

- Read [references/lab-playbook.md](references/lab-playbook.md) for concrete
  command patterns, cleanup rules, and baseline-build shortcuts.
