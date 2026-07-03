---
name: u64-range-narrowing-ab-lever-result
description: AB-lever measurement of the u64 range-tag narrowing lowering in DTVM's EVM multipass JIT, run against the lift-boundary-soundness interpreter-fallback fix — confirms small real gains on shift/compare-heavy kernels (sha1_*), overall geomean effect within noise, and near-zero static hit rate for the ADD/SUB/MUL/DIV/MOD range-narrow fast paths on real contracts.
metadata:
  type: project
---

Measured 2026-07-03 in throwaway worktree `.worktrees/u64-ab`, branch
`perf/u64-ab-lever` (commit 474daeb, never pushed), based on
`fix/evm-lift-dynamic-boundary-soundness` @ d7d2e91 — the fix that lets more
real contracts reach the multipass JIT instead of falling back to the
interpreter.

**Why:** determine whether the range-tag-driven u64/u128 narrowing in
`Operand::getRange()` (src/compiler/evm_frontend/evm_mir_compiler.h) and the
cross-block entry-range refinement (src/action/evm_bytecode_visitor.h
~:1090-1098) contributes measurable end-to-end speedup now that the
interpreter-fallback soundness fix lets real workloads actually JIT (previous
measurements, cross-referenced in the shared `u64-fastpath-perf-neutral`
memory, were confounded by most benchmark kernels falling back to the
interpreter and never exercising the narrowing at all).

**Method:** added a diagnostic CMake option
`ZEN_ENABLE_EVM_DISABLE_RANGE_NARROWING` that forces `getRange()` to always
return `U256` and no-ops the entry-range consumer, without touching
`isConstU64`-driven constant fast paths or runtime dual-path checks (DIV/MOD/
ADDMOD high-limbs-zero checks) — conservative-only, verified by full
differential/unittest pass with the lever ON. Two Release build dirs
(`build-narrow` lever OFF, `build-wide` lever ON) differ in exactly one
`ZEN_ENABLE_*` CMakeCache line. evmone-bench, 12 repetitions, evmone's 8-kernel
main suite (14 cases) + 6-kernel micro suite (13 cases).

**Result:**
- Correctness: 46/46 evmDifferentialTests, 223/223 multipass evmone-unittests,
  both on build-wide (lever ON).
- main-suite geomean delta (wide vs narrow, positive = narrowing helps):
  **+1.284%** (14 cases). sha1_divs +4.67%, sha1_shifts +5.12% — the only
  deltas clearly outside noise (IQR-based). Rest are noise-level (±0.7%).
- micro-suite geomean: **-0.232%** (13 cases, pure noise — no arithmetic-heavy
  kernels in this set).
- Static site counts (`[EVM-ARITH-SUMMARY]`, 28 real deployed contracts + the
  8 main kernels, lever OFF): ADD range_u64_narrowed 3/6459 sites (0.05%), SUB
  3/1623 (0.18%), MUL/DIV/MOD 0%. The `bothFitU64`-gated arithmetic fast path
  essentially never fires on real code.
- Important scope limit: `[EVM-ARITH-SUMMARY]` only counts ADD/SUB/MUL/DIV/MOD
  sites — no static counter exists for the AND/OR/XOR/shift/compare narrow
  paths the same lever also gates. sha1_divs/sha1_shifts show zero
  range-narrowed arithmetic sites, so their +5% gain must come from the
  shift/compare side (sha1 is 32-bit word rotation/hashing) — inferred, not
  directly measured by this counter.

**How to apply:** this corroborates the existing `u64-fastpath-perf-neutral`
project memory (different measurement lineage, different fix branch, same
direction and magnitude: ~+1% main-suite geomean, +5% on shift/compare-heavy
kernels, near-zero static arithmetic-narrowing hit rate). Do not re-propose
"widen bothFitU64 coverage" as a high-value optimization without first
targeting the shift/compare narrow paths specifically, since those — not the
arithmetic range fast path — appear to drive the only measurable kernel gains.
Raw JSON/logs: `.worktrees/u64-ab/bench-results/` (deleted if the worktree is
cleaned up — this summary is the durable record).
