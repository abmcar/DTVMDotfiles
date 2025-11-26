# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Focus
目前我们在实现 EVM JIT 的质量检测方案，具体可见 [qa.md](qa.md)，我们是华师大侧，需要负责异常处理、Gas 计量、安全漏洞、Fuzz 测试、性能检测部分。
目前主要在做JIT的状态测试部分。

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
- **`src/common/`** - Shared utilities, error handling, type definitions

## Build Commands

About build, you can read .vscode/tasks.json, this is my personal tasks.
### Build
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_SPEC_TEST=ON -G Ninja
cmake --build build -j
```

## Testing

### EVM Tests

#### EVM Tests
```bash
# Run EVM State tests (Important)
./build/evmStateTests
```

### TestCase Structure

#### EVM State Test (`tests/evm_spec_test/state_tests`)
其中有json和py文件，json是测试样例文件，是状态测试真正执行的文件，py文件是生产测试样例的文件，其中有具体的测试逻辑，你可以通过查看json文件对应的python文件来获取相应测试样例的测试逻辑。

## Development Tools
- `tools/format.sh check`  - Run clang-check to check code format, it should be run before you finish task
- `tools/format.sh format` - Run clang-format to format code after you modify code

