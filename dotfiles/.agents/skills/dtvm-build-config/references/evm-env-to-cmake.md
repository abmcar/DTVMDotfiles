# EVM Env-to-CMake Mapping

Use this file with `.ci/run_test_suite.sh`. The script is authoritative for
every EVM CI build in `.github/workflows/dtvm_evm_test_x86.yml` except the
performance baseline build.

## Table of Contents

1. Base options
2. `RUN_MODE`
3. `TestSuite`
4. `CPU_EXCEPTION_TYPE`
5. Runtime-only toggles
6. Virtual stack loop
7. Direct-CMake special case

## 1. Base Options

Base CMake option assembly:

| Env | Effect |
|---|---|
| `CMAKE_BUILD_TARGET=<type>` | Adds `-DCMAKE_BUILD_TYPE=<type>` |
| `ENABLE_ASAN=true` | Adds `-DZEN_ENABLE_ASAN=ON` |
| `INPUT_FORMAT=evm` | Runs `./tools/easm2bytecode.sh ./tests/evm_asm ./tests/evm_asm` and `./tools/solc_batch_compile.sh` before the build/test loop |

The script always starts from:

```bash
CMAKE_OPTIONS="-DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TARGET"
EXTRA_EXE_OPTIONS="-m $RUN_MODE --format $INPUT_FORMAT"
```

## 2. `RUN_MODE`

`RUN_MODE` changes both CMake flags and runtime arguments.

| `RUN_MODE` | CMake effect | Runtime effect |
|---|---|---|
| `interpreter` | `-DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_MULTIPASS_JIT=OFF` | `-m interpreter --format evm` |
| `multipass` | `-DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_MULTIPASS_JIT=ON` | `-m multipass --format evm`, plus optional lazy/gas/thread flags |

Notes:

- `.ci/run_test_suite.sh` also supports `singlepass`, but current EVM CI does
  not use it.
- `ENABLE_LAZY` only matters when `RUN_MODE=multipass`.
- `ENABLE_GAS_METER` only affects `EXTRA_EXE_OPTIONS`; it does not add a CMake
  flag.
- `ENABLE_MULTITHREAD=true` adds `--num-multipass-threads 16`.
- `ENABLE_MULTITHREAD=false` adds `--disable-multipass-multithread`.

## 3. `TestSuite`

`TestSuite` chooses both the build flags and the execution path.

| `TestSuite` | Added CMake flags | Execution path |
|---|---|---|
| `evmtestsuite` | `-DZEN_ENABLE_SPEC_TEST=ON -DZEN_ENABLE_ASSEMBLYSCRIPT_TEST=ON -DZEN_ENABLE_CHECKED_ARITHMETIC=ON -DZEN_ENABLE_EVM=ON` | `ctest --verbose` |
| `evmrealsuite` | `-DZEN_ENABLE_SPEC_TEST=ON -DZEN_ENABLE_ASSEMBLYSCRIPT_TEST=ON -DZEN_ENABLE_CHECKED_ARITHMETIC=ON -DZEN_ENABLE_EVM=ON` | `python3 tools/run_evm_tests.py -r build/dtvm $EXTRA_EXE_OPTIONS` |
| `evmonetestsuite` | `-DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON` | clone evmone and run both multipass and interpreter unit-test lists |
| `evmonestatetestsuite` | `-DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON` | build evmone-statetest, prepare fixtures, and run both modes through external VM |
| `evmfallbacksuite` | `-DZEN_ENABLE_SPEC_TEST=ON -DZEN_ENABLE_ASSEMBLYSCRIPT_TEST=ON -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON -DZEN_ENABLE_JIT_FALLBACK_TEST=ON` | real-suite runner plus `./build/evmFallbackExecutionTests` |
| `benchmarksuite` | `-DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON -DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON` | clone evmone and run `tools/check_performance_regression.py` |

Important execution nuances:

- `evmtestsuite` repeats `ctest` 20 times in `Release`, or 2 times otherwise.
- `evmtestsuite` in interpreter mode skips `test_blob_gas_subtraction`.
- `evmonetestsuite` and `evmonestatetestsuite` do not consume
  `EXTRA_EXE_OPTIONS` in their main execution path.
- `evmonestatetestsuite` always passes
  `enable_gas_metering=true` through evmone VM options when it runs state
  tests.
- `benchmarksuite` uses `BENCHMARK_MODE` to choose the comparison mode for
  evmone benchmarks. That is separate from `RUN_MODE`.

## 4. `CPU_EXCEPTION_TYPE`

| `CPU_EXCEPTION_TYPE` | Added CMake flag |
|---|---|
| `cpu` | `-DZEN_ENABLE_CPU_EXCEPTION=ON` |
| `check` | `-DZEN_ENABLE_CPU_EXCEPTION=OFF` |

## 5. Runtime-Only Toggles

These toggles do not directly change the build shape unless otherwise noted.

| Env | Effect |
|---|---|
| `ENABLE_GAS_METER=true` | Adds `--enable-evm-gas` to `EXTRA_EXE_OPTIONS` in multipass mode |
| `ENABLE_LAZY=true` | Adds `--enable-multipass-lazy` in multipass mode |
| `ENABLE_MULTITHREAD=true` | Adds `--num-multipass-threads 16` in multipass mode |
| `ENABLE_GAS_REGISTER=true` | Adds `-DZEN_ENABLE_EVM_GAS_REGISTER=ON` |

These options are ignored or partially ignored in some suites:

- `interpreter` mode ignores multipass runtime toggles.
- `evmonetestsuite` does not use `EXTRA_EXE_OPTIONS` for its unit-test calls.
- `evmonestatetestsuite` does not use `EXTRA_EXE_OPTIONS` for statetest
  execution; evmone VM options control runtime mode and gas metering there.

## 6. Virtual Stack Loop

After assembling `CMAKE_OPTIONS`, the script builds and tests once per stack
variant in `STACK_TYPES`.

Default behavior:

```bash
STACK_TYPES=(
  "-DZEN_ENABLE_VIRTUAL_STACK=ON"
  "-DZEN_ENABLE_VIRTUAL_STACK=OFF"
)
```

Overrides:

| Condition | Stack behavior |
|---|---|
| `RUN_MODE=interpreter` | only `-DZEN_ENABLE_VIRTUAL_STACK=OFF` |
| `TestSuite=evmonetestsuite` | only `-DZEN_ENABLE_VIRTUAL_STACK=ON` |
| `TestSuite=evmonestatetestsuite` | only `-DZEN_ENABLE_VIRTUAL_STACK=ON` |
| `TestSuite=benchmarksuite` | only `-DZEN_ENABLE_VIRTUAL_STACK=ON` |

This means:

- multipass `evmtestsuite`, `evmrealsuite`, and `evmfallbacksuite` run twice,
  once with virtual stack enabled and once disabled
- interpreter jobs run only with virtual stack disabled
- evmone and benchmark jobs run only with virtual stack enabled

## 7. Direct-CMake Special Case

The EVM performance baseline build in
`.github/workflows/dtvm_evm_test_x86.yml` does not use `.ci/run_test_suite.sh`.
It directly configures:

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

Treat that command as the canonical answer whenever the user asks for the
performance baseline build configuration.
