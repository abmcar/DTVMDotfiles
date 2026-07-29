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
   zero-delta). Fetch `upstream`, record `BASELINE_COMMIT`, then invoke
   `$dtvm-worktree-bootstrap` with `upstream/main` as the base ref and a fresh
   disposable branch/path. Set `BASE_WT` to the absolute path returned by the
   skill. The skill owns initialization, CI-derived configuration, and the
   `dtvmapi` build gate.
   ```bash
   git fetch -q upstream
   BASELINE_COMMIT="$(git rev-parse upstream/main)"
   # Invoke $dtvm-worktree-bootstrap here and capture its absolute worktree path.
   [ "$(git -C "$BASE_WT" rev-parse HEAD)" = "$BASELINE_COMMIT" ] \
     || { echo "baseline not at upstream/main"; exit 1; }
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
   Both worktrees share the ccache object store and versioned FetchContent
   source cache; third-party binary directories remain build-local.

3. **Run baseline benchmark** — Use `/dtvm-evmone-benchmark` with the baseline library at `$BASE_SO` (the upstream/main worktree build), adding `--benchmark_repetitions=3 --benchmark_out=/tmp/bench-baseline.json --benchmark_out_format=json`.

4. **Run branch benchmark** — Run immediately after step 3 in the same shell session; ~8pp drift between morning and afternoon makes same-window execution a correctness requirement. Use `/dtvm-evmone-benchmark` with the branch library at `build/lib/libdtvmapi.so`, adding `--benchmark_repetitions=3 --benchmark_out=/tmp/bench-branch.json --benchmark_out_format=json`.

5. **Compare** — Parse both JSON outputs, compute per-benchmark speedup and geo mean.
6. **Clean up** — verify `BASE_WT` is the exact registered disposable
   worktree and that tracked, untracked, and recursive-submodule status is
   clean. Then run `git worktree remove --force "$BASE_WT"` and confirm it no
   longer appears in `git worktree list`. The force flag handles initialized
   submodules; it must not discard changes.

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
