---
description: Local EVM test runner. Use when running evmone-unittests, evmone-statetest, ctest, or the evm_asm suite locally via tools/dtvm_local_test.sh — NOT for CI reproduction (see dtvm-build-config.md for that).
paths:
  - "src/**"
  - "tests/**"
---

# DTVM Local Test Commands

Run local correctness tests through `tools/dtvm_local_test.sh`. It wraps the four
local suites against an already-built artifact set, picks suites by touched path,
runs them concurrently, and enforces the guardrails that the raw commands used to
require by hand (correct cwd, artifact existence, non-empty gtest filter, the
right `-k fork_Cancun` per corpus). It does **not** build — see
`.claude/rules/dtvm-build-config.md`. For CI reproduction, also use that rule.

## Primary use

```bash
tools/dtvm_local_test.sh --auto      # pick mode + suites from the branch diff
```

`--auto` diffs against the merge-base with the default branch (whole branch plus
uncommitted work) and selects suites per the touched-path table below. It prints
what it ran and what it skipped, satisfying Rule 1 of
`.claude/rules/ci-test-discipline.md` (never silently skip a required suite).

With no arguments the script behaves as `--auto`.

## Manual selection

```bash
tools/dtvm_local_test.sh --mode multipass|interpreter|both \
                         --suite unittests|statetest|ctest|evm_asm|format|all \
                         [--corpus eest|replay|<path>] [--jobs N] [--dry-run]
```

- `--suite` accepts a comma list and may repeat.
- `--corpus eest` (default) runs the EEST `state_tests` with `-k fork_Cancun`;
  `--corpus replay` runs the mainnet-replay corpus with no fork filter.
- `--dry-run` prints the exact commands without running them.

## Test Selection by Touched Path

`--auto` implements this mapping; the script is authoritative. When the diff
touches multiple buckets it runs **all** matching suites.

| Touched path | Suites |
|---|---|
| `src/compiler/` or `src/runtime/` | multipass: unittests + statetest + evm_asm |
| `src/evm/` | interpreter: unittests + statetest + evm_asm |
| `src/tests/` only | ctest |
| `docs/`- / `.claude/`- / `CLAUDE.md`-only | format check + ctest smoke; evmone skipped |
| Unknown / mixed / cross-module | multipass unittests + statetest (safe default) |

## Prerequisites

- DTVM built: `build/lib/libdtvmapi.so` (evmone suites) and `build/dtvm`
  (evm_asm CLI). Build flags: `.claude/rules/dtvm-build-config.md`.
- evmone pre-built at `~/evmone/build/bin/` (override with `EVMONE_BIN_DIR`).
- EEST fixtures at `tests/fixtures/fixtures/state_tests` — a gitignored EEST
  release download (see `EVM_SPEC_FIXTURES_URL` in `.ci/run_test_suite.sh`), NOT
  a submodule; fresh worktrees must download it first (override with
  `FIXTURES_DIR`).

Other env overrides: `DTVM_SO`, `DTVM_CLI`, `REPLAY_CORPUS`, `CTEST_JOBS`.

## Building `libdtvmapi.so` locally

The script runs tests but does not build. For a local (non-CI) multipass build,
configure and build the library directly:

```bash
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release \
  -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_SPEC_TEST=ON \
  -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON \
  -DLLVM_DIR=<llvm15-prefix>/lib/cmake/llvm
cmake --build build --target dtvmapi -j$(nproc)
```

This produces `build/lib/libdtvmapi.so` (and the `build/dtvm` CLI). For
CI-faithful flag variants (gas register, fallback test, virtual stack), see
`.claude/rules/dtvm-build-config.md`, which maps each CI job's env vars to CMake
options.

## Do not

- Do not run `.ci/run_test_suite.sh` locally — it clones evmone into the CWD and
  copies `.so` files (and enables ASAN when `ENABLE_ASAN=true`), polluting the
  workspace. Use this script instead.
- Do not copy `.so` files into `~/evmone/`; the script passes the build path as
  the EVMC argument.
