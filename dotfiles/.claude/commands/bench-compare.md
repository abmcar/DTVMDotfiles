---
name: bench-compare
description: Run a quick before/after benchmark comparison between the current branch and upstream/main baseline. Auto-refreshes baseline worktree.
---

# Benchmark Comparison

Quick before/after benchmark comparison between current branch and baseline.

## Steps

1. **Decide whether to refresh baseline** — `dtvm-perf-worktree-lab.md`
   "Permanent Resources" has the canonical refresh recipe. This command
   adds a fast-path that skips both checkout and rebuild when the worktree
   is already at `upstream/main` AND a usable `.so` is on disk
   (saves 1–3min incremental, 5–15min cold):
   ```bash
   git -C ~/dtvm-baseline fetch -q upstream
   BASE_HEAD=$(git -C ~/dtvm-baseline rev-parse HEAD)
   UPSTREAM_HEAD=$(git -C ~/dtvm-baseline rev-parse upstream/main)
   BASE_SO=~/dtvm-baseline/build-baseline/lib/libdtvmapi.so
   if [ "$BASE_HEAD" = "$UPSTREAM_HEAD" ] && [ -f "$BASE_SO" ]; then
     NEED_BASELINE_BUILD=0
   else
     git -C ~/dtvm-baseline checkout upstream/main
     NEED_BASELINE_BUILD=1
   fi
   ```
   Assumes `~/dtvm-baseline` is reserved for `upstream/main` per the lab doc;
   if a feature branch was manually parked there at the same SHA, force a
   checkout by deleting `$BASE_SO` first.

2. **Build** — when both sides need to compile, run them in parallel with
   half-cores each so they overlap without `-j$(nproc) × 2` CPU thrash;
   when only the branch needs compiling, use full cores:
   ```bash
   if [ "$NEED_BASELINE_BUILD" = "1" ]; then
     J=$(( $(nproc) / 2 ))
     cmake --build build --target dtvmapi -j$J &
     BRANCH_PID=$!
     cmake --build ~/dtvm-baseline/build-baseline --target dtvmapi -j$J
     wait $BRANCH_PID
   else
     cmake --build build --target dtvmapi -j$(nproc)
   fi
   ```
   Both worktrees share ccache + FetchContent cache.

3. **Run baseline benchmark** — Use `/dtvm-evmone-benchmark` with the baseline library at `~/dtvm-baseline/build-baseline/lib/libdtvmapi.so`, adding `--benchmark_repetitions=3 --benchmark_out=/tmp/bench-baseline.json --benchmark_out_format=json`.

4. **Run branch benchmark** — **Immediately** after step 3, in the same shell session, use `/dtvm-evmone-benchmark` with the branch library at `build/lib/libdtvmapi.so`, adding `--benchmark_repetitions=3 --benchmark_out=/tmp/bench-branch.json --benchmark_out_format=json`. Do not interleave other heavy work between steps 3 and 4 — bench drift on this machine is ~8pp between morning/afternoon, so same-window back-to-back execution is the only way the delta is trustworthy.

5. **Compare** — Parse both JSON outputs, compute per-benchmark speedup and geo mean.

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
