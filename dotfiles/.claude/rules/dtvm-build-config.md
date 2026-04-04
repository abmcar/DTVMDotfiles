---
description: DTVM EVM CI build and test configurations. Use when reproducing CI builds, checking CI job flags, understanding how .ci/run_test_suite.sh maps environment variables to CMake options, or configuring evmtestsuite, evmrealsuite, evmone unit tests, evmone statetests, gas register, JIT fallback, or performance regression builds.
globs: []
alwaysApply: false
---

# DTVM EVM Build Config

Treat the EVM CI as authoritative. Read these files before answering any
question that depends on current CI settings:

- `.github/workflows/dtvm_evm_test_x86.yml`
- `.ci/run_test_suite.sh`

Ignore non-EVM jobs. This rule is EVM-only and CI-focused.

If the user is not asking about CI reproduction, hand off instead of stretching
this rule:

- For local perf worktree and evmone checkout management, see
  `.claude/rules/dtvm-perf-worktree-lab.md`.
- For local evmone benchmark command construction and usage, see
  `.claude/commands/dtvm-evmone-benchmark.md`.
- For multipass JIT log and lowering inspection, see
  `.claude/commands/dtvm-jit-lowering-inspection.md`.

## Workflow

1. Identify the closest CI job family in
   [references/evm-ci-build-matrix.md](references/evm-ci-build-matrix.md).
2. Prefer the `.ci/run_test_suite.sh` interface for CI-faithful local
   reproduction. Use
   [references/evm-env-to-cmake.md](references/evm-env-to-cmake.md) to explain
   how each environment variable changes CMake flags and runtime options.
3. Use raw `cmake` commands only for CI paths that already do that. The main
   special case is the performance baseline build.
4. Derive non-CI variants only when the user explicitly asks for them. Start
   from the nearest CI job and state the delta instead of inventing a brand new
   configuration.
5. Re-read the workflow file if the request mentions a specific job name,
   because the skill references are summaries, not the source of truth.

## Output Requirements

When giving a build config or reproduction command, include:

- whether CI also runs `./tools/format.sh check`
- the exact environment block plus `bash .ci/run_test_suite.sh`, or the exact
  `cmake` command for a direct-CMake job
- the matching CI job name
- the small set of flags that materially change behavior, such as `RUN_MODE`,
  `TestSuite`, `CPU_EXCEPTION_TYPE`, `ENABLE_GAS_METER`,
  `ENABLE_GAS_REGISTER`, and virtual stack behavior
- any important execution-only nuance, such as retries, benchmark matrix mode,
  or cases where the script ignores `EXTRA_EXE_OPTIONS`

## References

- [references/evm-ci-build-matrix.md](references/evm-ci-build-matrix.md):
  canonical EVM CI job matrix and local reproduction recipes
- [references/evm-env-to-cmake.md](references/evm-env-to-cmake.md):
  authoritative environment-to-CMake and environment-to-runtime mapping from
  `.ci/run_test_suite.sh`
