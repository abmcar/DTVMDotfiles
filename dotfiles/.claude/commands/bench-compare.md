---
name: bench-compare
description: Run a quick before/after benchmark comparison between the current branch and an upstream/main baseline built on demand.
---

# Benchmark Comparison

Quick before/after benchmark comparison between current branch and baseline.

## Steps

1. **Prepare the baseline worktree** — there is no persistent baseline; create
   one PINNED to `upstream/main`. Pinning is the correctness step: branching
   from the current HEAD benchmarks the branch against itself (silent
   zero-delta). Create and configure here; step 2 builds branch + baseline
   together for a fair same-window comparison.
   ```bash
   git fetch -q upstream
   BASE_WT=.worktrees/baseline-main
   git worktree add "$BASE_WT" -b baseline-main upstream/main   # start-point = upstream/main
   bash DTVMDotfiles/worktree-init.sh "$BASE_WT"                # submodule init + dotfiles sync
   [ "$(git -C "$BASE_WT" rev-parse HEAD)" = "$(git rev-parse upstream/main)" ] \
     || { echo "baseline not at upstream/main"; exit 1; }
   # configure with the EVM flags from dtvm-local-test.md "Building libdtvmapi.so locally":
   cmake -G Ninja -B "$BASE_WT/build" -S "$BASE_WT" -DCMAKE_BUILD_TYPE=Release \
     -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON -DZEN_ENABLE_MULTIPASS_JIT=ON \
     -DZEN_ENABLE_SPEC_TEST=ON -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON \
     -DLLVM_DIR=<llvm15-prefix>/lib/cmake/llvm
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
