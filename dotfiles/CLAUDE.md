# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Focus
目前我们在实现 EVM JIT 的质量检测方案，具体可见 [qa.md](qa.md)，我们是华师大侧，需要负责异常处理、Gas 计量、安全漏洞、Fuzz 测试、性能检测部分。

### Code Style Guidelines (Important)
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

### ZetaEngine Core Components

- **`src/action/`** - Module loading, instantiation, and bytecode visiting infrastructure
- **`src/runtime/`** - Execution environments and instance management (EVM, WASM)
- **`src/compiler/`** - dMIR (deterministic Middle IR) compiler with multiple frontends:
  - **`evm_frontend/`** - EVM bytecode to dMIR translation
  - **`wasm_frontend/`** - WebAssembly to dMIR translation
  - **`mir/`** - Middle Intermediate Representation core
  - **`cgir/`** - Code generation IR and optimization passes
- **`src/evm/`** - EVM interpreter and opcode handlers
- **`src/host/`** - Host interface implementations (EVM, WASI, spectest)
- **`src/common/`** - Shared utilities, error handling, type definitions

## Build Commands

About build, you can read .vscode/tasks.json, this is my personal tasks.
### Build
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_SPEC_TEST=ON -G Ninja
cmake --build build -j
```

### Essential CMake Options
- `ZEN_ENABLE_SINGLEPASS_JIT=ON` - Enable singlepass JIT
- `ZEN_ENABLE_MULTIPASS_JIT=ON` - Enable multipass JIT with LLVM backend
- `ZEN_ENABLE_SPEC_TEST=ON` - Enable WebAssembly spec tests

## Testing

### EVM Tests

#### EVM Interpreter Tests
(现在基本用不到，主要在测试 JIT 部分)
```bash
# Run EVM interpreter tests
./build/evmInterpTests
# Run Solidity contract tests
./build/solidityContractTests
# Run EVM State tests
./build/evmStateTests
```

#### EVM mir Tests
for evm mir, successful build is all you need, you don't need test them

### TestCase Structure

#### EVM Test Cases (`tests/evm_asm/`)
Each test consists of three files:
- `<test_name>.easm` - EVM assembly source code
- `<test_name>.evm.hex` - Compiled bytecode (you can generate them by running `./tools/easm2bytecode.sh tests/evm_asm/ tests/evm_asm`)
- `<test_name>.expected` - Expected execution result

#### Solidity Contract Tests (`tests/evm_solidity/`)
There have many directories, each directory represent a testcase
Each contract testcase contains:
- `<contract_name>.sol` - Solidity source
- `<contract_name>.json` - Compiled ABI + bytecode(You can generate them by running `./tools/solc_batch_compile.sh tests/evm_solidity`.This will generate compiled JSON files in all subdirectories)
- `test_cases.json` - Test cases with function calls and expected results(You need write them manually, please think hard)

## Development Tools
- `tools/function_selector.py` - Run it to calculate function selector(example:`python3 tools/function_selector.py 'add(uint256,uint256)'`, it may be used when writing testcases writing for `solidityContractTests`)
- `/tools/solc_batch_compile.sh` - Run it to compile sol files(example:`./tools/solc_batch_compile.sh tests/evm_solidity`, it may be used before running `solidityContractTests` to compile latest sol files)
- `compare_mpt.sh` - Run it to check whether the C++ MPT implementation is correct.(example:`./compare_mpt.sh test.json`, `test.json` store the accounts, you can refer the `pre` part in evmStateTest testcases(you can find them in `tests/evm_spec_test/state_tests`))
- `tools/format.sh check`  - Run clang-check to check code format, it should be run before you finish task
- `tools/format.sh format` - Run clang-format to format code after you modify code

# Test modification from store script
