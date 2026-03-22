# EVM CI Build Matrix Reference

## Table of Contents

1. Common Context
2. Interpreter ctest
3. Release multipass ctest
4. Interpreter CLI
5. Debug multipass real suite
6. Release multipass gas register
7. Release multipass gas register ctest
8. evmone unit tests
9. evmone state tests
10. JIT fallback
11. Performance regression

## 1. Common Context

Authoritative sources:

- `.github/workflows/dtvm_evm_test_x86.yml`
- `.ci/run_test_suite.sh`

Common CI context:

- Container: `dtvmdev1/dtvm-dev-x64:main`
- CI runs `./tools/format.sh check` before every EVM build/test job
- All script-driven EVM jobs set `INPUT_FORMAT=evm`

Quick selection table:

| CI job | Interface | TestSuite | Build type | Run mode | Stack modes |
|---|---|---|---|---|---|
| `build_test_evm_interpreter_x86_ctest` | `run_test_suite.sh` | `evmtestsuite` | `Debug` | `interpreter` | `OFF` only |
| `build_test_release_multipass_lazy_evmtestsuite_on_x86_ctest` | `run_test_suite.sh` | `evmtestsuite` | `Release` | `multipass` | `ON` and `OFF` |
| `build_test_evm_interpreter_x86_cli` | `run_test_suite.sh` | `evmrealsuite` | `Debug` | `interpreter` | `OFF` only |
| `build_test_debug_multipass_lazy_evmtestsuite_on_x86` | `run_test_suite.sh` | `evmrealsuite` | `Debug` | `multipass` | `ON` and `OFF` |
| `build_test_release_multipass_gas_register_on_x86` | `run_test_suite.sh` | `evmrealsuite` | `Release` | `multipass` | `ON` and `OFF` |
| `build_test_multipass_gas_register_evmtestsuite_on_x86_ctest` | `run_test_suite.sh` | `evmtestsuite` | `Release` | `multipass` | `ON` and `OFF` |
| `build_test_release_evmone_unittests_on_x86` | `run_test_suite.sh` | `evmonetestsuite` | `Release` | `multipass` build, both modes exercised | `ON` only |
| `build_test_release_evmone_statetests_on_x86` | `run_test_suite.sh` | `evmonestatetestsuite` | `Release` | `multipass` build, both modes exercised | `ON` only |
| `build_test_release_multipass_evmjitfallback_on_x86_ctest` | `run_test_suite.sh` | `evmfallbacksuite` | `Release` | `multipass` | `ON` and `OFF` |
| `performance_regression_check` baseline | direct `cmake` | n/a | `Release` | multipass build for benchmarks | `ON` only |
| `performance_regression_check` PR build | `run_test_suite.sh` | `benchmarksuite` | `Release` | `multipass` build, benchmark mode matrix decides runtime comparison | `ON` only |

## 2. Interpreter ctest

Workflow job: `build_test_evm_interpreter_x86_ctest`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Debug
export ENABLE_ASAN=true
export RUN_MODE=interpreter
export INPUT_FORMAT=evm
export ENABLE_LAZY=true
export ENABLE_MULTITHREAD=true
export TestSuite=evmtestsuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=false

bash .ci/run_test_suite.sh
```

Notes:

- CI also runs `git clone https://github.com/asmjit/asmjit.git` before build.
- `ENABLE_LAZY` and `ENABLE_MULTITHREAD` are inert here because interpreter
  mode does not use multipass runtime flags.
- `evmtestsuite` in interpreter mode skips `test_blob_gas_subtraction`.

## 3. Release multipass ctest

Workflow job: `build_test_release_multipass_lazy_evmtestsuite_on_x86_ctest`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=true
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export TestSuite=evmtestsuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=true

bash .ci/run_test_suite.sh
```

Notes:

- The script rebuilds and reruns tests for both
  `-DZEN_ENABLE_VIRTUAL_STACK=ON` and `OFF`.
- `ENABLE_GAS_METER=true` adds `--enable-evm-gas` to runtime test arguments.
- `ENABLE_MULTITHREAD=true` adds `--num-multipass-threads 16`.

## 4. Interpreter CLI

Workflow job: `build_test_evm_interpreter_x86_cli`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Debug
export ENABLE_ASAN=true
export RUN_MODE=interpreter
export INPUT_FORMAT=evm
export ENABLE_LAZY=true
export ENABLE_MULTITHREAD=true
export TestSuite=evmrealsuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=false

bash .ci/run_test_suite.sh
```

Notes:

- CI wraps `bash .ci/run_test_suite.sh` in a retry loop with up to 3 attempts
  and a 15-second backoff.
- `evmrealsuite` uses `python3 tools/run_evm_tests.py -r build/dtvm`.

## 5. Debug Multipass Real Suite

Workflow job: `build_test_debug_multipass_lazy_evmtestsuite_on_x86`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Debug
export ENABLE_ASAN=true
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export TestSuite=evmrealsuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=true

bash .ci/run_test_suite.sh
```

Notes:

- The script runs both virtual stack variants.
- This job exercises CLI-style real-suite execution, not ctest.

## 6. Release Multipass Gas Register

Workflow job: `build_test_release_multipass_gas_register_on_x86`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=true
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export TestSuite=evmrealsuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=true
export ENABLE_GAS_REGISTER=true

bash .ci/run_test_suite.sh
```

Notes:

- `ENABLE_GAS_REGISTER=true` adds `-DZEN_ENABLE_EVM_GAS_REGISTER=ON`.
- The script still runs both virtual stack variants.

## 7. Release Multipass Gas Register ctest

Workflow job: `build_test_multipass_gas_register_evmtestsuite_on_x86_ctest`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=true
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export TestSuite=evmtestsuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=true
export ENABLE_GAS_REGISTER=true

bash .ci/run_test_suite.sh
```

Notes:

- This is the ctest sibling of the previous job.
- The script runs both virtual stack variants.

## 8. evmone Unit Tests

Workflow job: `build_test_release_evmone_unittests_on_x86`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=true
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export CPU_EXCEPTION_TYPE=cpu
export TestSuite=evmonetestsuite

bash .ci/run_test_suite.sh
```

Notes:

- `evmonetestsuite` forces `-DZEN_ENABLE_VIRTUAL_STACK=ON`.
- The script clones `https://github.com/DTVMStack/evmone.git` on branch
  `for_test`, copies `build/lib/*` into that tree, and runs both multipass and
  interpreter unit-test lists.
- `ENABLE_LAZY`, `ENABLE_MULTITHREAD`, and `ENABLE_GAS_METER` are not exported
  by the workflow and are not required for this path.

## 9. evmone State Tests

Workflow job: `build_test_release_evmone_statetests_on_x86`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=false
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export ENABLE_GAS_METER=true
export CPU_EXCEPTION_TYPE=cpu
export TestSuite=evmonestatetestsuite
export EVMONE_STATETEST_FILTER=fork_Cancun
export EVMONE_MODE_TIMEOUT_SECONDS=5400

bash .ci/run_test_suite.sh
```

Notes:

- `evmonestatetestsuite` forces `-DZEN_ENABLE_VIRTUAL_STACK=ON`.
- CI also configures a Hunter cache. That cache is a CI optimization, not part
  of the build shape.
- The script builds `evmone-statetest`, prepares fixtures if needed, then runs
  both `multipass` and `interpreter` modes via evmone external VM integration.
- In this code path, the statetest runner ignores `EXTRA_EXE_OPTIONS`. Gas
  metering is passed through the evmone VM option
  `enable_gas_metering=true`, not through `--enable-evm-gas`.

## 10. JIT Fallback

Workflow job: `build_test_release_multipass_evmjitfallback_on_x86_ctest`

Job-specific environment:

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=true
export RUN_MODE=multipass
export INPUT_FORMAT=evm
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export TestSuite=evmfallbacksuite
export CPU_EXCEPTION_TYPE=check
export ENABLE_GAS_METER=true

bash .ci/run_test_suite.sh
```

Notes:

- The script runs both virtual stack variants.
- The test path runs `python3 tools/run_evm_tests.py -r build/dtvm` and then
  `./build/evmFallbackExecutionTests`.

## 11. Performance Regression

Workflow job: `performance_regression_check`

This workflow has two build shapes.

### Baseline Build

This step does not use `.ci/run_test_suite.sh`.

```bash
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF \
  -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_EVM=ON \
  -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON \
  -DZEN_ENABLE_CPU_EXCEPTION=ON \
  -DZEN_ENABLE_VIRTUAL_STACK=ON
cmake --build build -j 16
```

Notes:

- CI stashes the PR worktree, checks out the base branch, builds the baseline
  library, copies `build/lib/*` to `/tmp/baseline_lib/`, then restores the PR.
- This is the canonical direct-CMake special case for this skill.

### Current PR Benchmark Build

The current PR build goes through `.ci/run_test_suite.sh`.

```bash
export CMAKE_BUILD_TARGET=Release
export ENABLE_ASAN=false
export RUN_MODE=multipass
export ENABLE_LAZY=false
export ENABLE_MULTITHREAD=true
export TestSuite=benchmarksuite
export CPU_EXCEPTION_TYPE=cpu
export BENCHMARK_MODE=interpreter   # or multipass
export BENCHMARK_THRESHOLD=0.25
export BENCHMARK_BASELINE_CACHE=/tmp/perf_baseline_<mode>.json
export BENCHMARK_BASELINE_LIB=/tmp/baseline_lib
export BENCHMARK_SUMMARY_FILE=/tmp/perf_summary_<mode>.md
export BENCHMARK_REPETITIONS=5

bash .ci/run_test_suite.sh
```

Notes:

- `benchmarksuite` forces `-DZEN_ENABLE_VIRTUAL_STACK=ON`.
- `BENCHMARK_MODE` is the evmone benchmark comparison mode, not the CMake
  `RUN_MODE`.
- The script clones `evmone`, ensures `build/bin/evmone-bench` exists, and runs
  `tools/check_performance_regression.py`.
