---
name: bench-compare
description: Run a quick before/after benchmark comparison between the current branch and an upstream/main baseline built on demand.
---

# Benchmark Comparison

Quick before/after benchmark comparison between current branch and baseline.

## Steps

1. **Prepare the baseline** — there is no persistent baseline worktree; build
   `upstream/main` on demand in a throwaway worktree. Use the
   `worktree-bootstrap` skill to create it on `upstream/main` (it runs
   submodule init + dotfiles sync); do not use raw `git worktree add`.
   ```bash
   git fetch -q upstream
   BASE_WT=.worktrees/baseline-main   # created by worktree-bootstrap on upstream/main
   BASE_SO="$BASE_WT/build/lib/libdtvmapi.so"
   ```

2. **Build** — run parallel builds at half-cores each to avoid CPU thrash:
   ```bash
   J=$(( $(nproc) / 2 ))
   cmake --build build --target dtvmapi -j$J &
   BRANCH_PID=$!
   cmake --build "$BASE_WT/build" --target dtvmapi -j$J
   wait $BRANCH_PID
   ```
   Both worktrees share ccache + FetchContent cache.

3. **Run baseline benchmark** — Use `/dtvm-evmone-benchmark` with the baseline library at `$BASE_SO` (the upstream/main worktree build), adding `--benchmark_repetitions=3 --benchmark_out=/tmp/bench-baseline.json --benchmark_out_format=json`.

4. **Run branch benchmark** — Run immediately after step 3 in the same shell session; ~8pp drift between morning and afternoon makes same-window execution a correctness requirement. Use `/dtvm-evmone-benchmark` with the branch library at `build/lib/libdtvmapi.so`, adding `--benchmark_repetitions=3 --benchmark_out=/tmp/bench-branch.json --benchmark_out_format=json`.

5. **Compare** — Parse both JSON outputs, compute per-benchmark speedup and geo mean.
6. **Clean up** — remove the scratch baseline worktree: `rm -rf "$BASE_WT" && git worktree prune`.

## Output Format

```
Benchmark Comparison: <branch> vs upstream/main
═══════════════════════════════════════════════
Benchmark           Baseline(ns)  Branch(ns)  Change
────────────────────────────────────────────────
snailtracer          XXXXXXX       XXXXXXX    -X.XX%
erc20               XXXXXXX       XXXXXXX    +X.XX%
...
────────────────────────────────────────────────
Geometric Mean                                -X.XX%
```
