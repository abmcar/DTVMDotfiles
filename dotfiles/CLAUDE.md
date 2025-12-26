# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Focus

Current tasks focus on:
- Research gas implementation optimization mechanisms in evmjit
- Integrate dtvm into evmone's statetest logic
- Analyze runtime performance bottlenecks through interpreter profiling

## Code Style Guidelines (Important)
1. Only include essential comments—avoid excessive documentation. All comments must be written in English
2. The last line of the file must contain exactly one blank line—no more, no less
3. New .h and .cpp files must begin with the following license header:
```
// Copyright (C) 2025 the DTVM authors. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
```
4. The code follows clang-format coding style. Follow the LLVM naming conventions strictly. For example, variable names should be written as `GasCost`, and function names should be written as `calcGasCost`.
5. Add comments only when necessary, and always write comments in English

## Project Architecture

### Core Module Structure

- **`src/vm/`** - DTVM core implementation and wrapped host interface
- **`src/runtime/`** - Execution environments and instance management for EVM
- **`src/compiler/`** - dMIR (deterministic Middle IR) compiler:
  - **`evm_frontend/`** - EVM bytecode to dMIR translation
  - **`mir/`** - Middle Intermediate Representation core
  - **`cgir/`** - Code generation IR and optimization passes
- **`src/evm/`** - EVM interpreter and opcode handlers
- **`src/action/`** - Module loading, instantiation, and bytecode visiting infrastructure
- **`src/common/`** - Shared utilities, error handling, type definitions

## Build Commands

### Build
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_SPEC_TEST=ON -G Ninja
cmake --build build -j
```

### Build Options
- `-DZEN_ENABLE_LINUX_PERF=ON` - Enable for performance testing
- `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` - Enable when changing build parameters
- `-DCMAKE_BUILD_TYPE=RelWithDebInfo` - Use instead of `Debug` for performance testing

## Testing

```bash
./build/evmStateTests
```

### Evmone State Tests With DTVM VM

```bash
/root/evmone/build/bin/evmone-statetest /root/DTVM/tests/evm_spec_test/ALL_STATE_TESTS/ --vm "/root/DTVM/build/lib/libdtvmapi.so,mode=interpreter,enable-evm-gas=1" -k "fork_Cancun"
```

### Run All JSON State Tests With GTest Output

```bash
rg --files -g '*.json' -g '!index.json' /root/DTVM/tests/evm_spec_test/state_tests -0 \
  | xargs -0 /root/evmone/build/bin/evmone-statetest \
    --vm "/root/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable-evm-gas=1" \
    -k "fork_Cancun" \
    --gtest_output=json:/tmp/evmone_all.json
```

### Test Structure

#### EVM State Tests (`tests/evm_spec_test/state_tests`)
Contains JSON and Python files:
- JSON files: Test case specifications executed by the state test runner
- Python files: Test case generators that define the test logic

## Development Tools
- `tools/format.sh check`  - Run clang-check to check code format, it should be run before you finish task
- `tools/format.sh format` - Run clang-format to format code after you modify code

## Performance Profiling

Performance testing and sampling scripts are located in the `perf/` directory:

```bash
# Record callgraph for ERC20 workload (default: interpreter)
./perf/record_erc20_perf.sh [multipass|interpreter]

# Record callgraph for fibr workload (default: interpreter)
./perf/record_fibr_perf.sh [multipass|interpreter]
```

