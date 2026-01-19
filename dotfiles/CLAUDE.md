<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# DTVM Development Guide

This file provides guidance to Claude Code and other AI assistants when working with code in this repository.

## Project Overview

DTVM is a deterministic VM with EVM ABI compatibility. Core implementation is in C/C++ under `src/`.

**Key Principles:**
- Preserve determinism - avoid host-specific, non-deterministic behavior
- Prefer touching `third_party/` only when explicitly required
- Keep edits minimal and localized; follow existing patterns
- Update or add tests when behavior changes

## Code Style Guidelines

### General Rules
1. Only include essential comments—avoid excessive documentation. **All comments must be written in English**
2. The last line of the file must contain exactly one blank line—no more, no less
3. Add comments only when necessary, and always write comments in English
4. The code follows clang-format coding style. Follow the LLVM naming conventions strictly:
   - Variable names: `GasCost` (PascalCase)
   - Function names: `calcGasCost` (camelCase)

### License Header
New .h and .cpp files must begin with the following license header:
```cpp
// Copyright (C) 2025 the DTVM authors. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
```

## Commit and PR Guidelines

When creating commits or pull requests, follow the conventions defined in `commitlint.config.js`:

### Commit Message Format
```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Type (required)
- `feat` - A new feature
- `fix` - A bug fix
- `docs` - Documentation only changes
- `style` - Code style changes (formatting, white-space, etc.)
- `refactor` - Code changes that neither fix bugs nor add features
- `perf` - Performance improvements
- `test` - Adding or correcting tests
- `build` - Build system or dependency changes
- `ci` - CI configuration changes
- `chore` - Other changes that don't modify src or test files

### Scope (required)
- `core` - Core engine code
- `runtime` - Runtime library
- `compiler` - Compiler related
- `evm` - EVM interpreter and handlers
- `examples` - Example code
- `docs` - Documentation related
- `tools` - Tool related
- `deps` - Dependency related
- `ci` - CI related
- `test` - Test related
- `other` - Other changes
- `` (empty) - No specific scope

### Rules
- Header must not exceed 100 characters
- Subject must not end with a period
- Type must be lowercase
- Use imperative mood in subject (e.g., "add feature" not "added feature")

### PR Title Format
PR titles should follow the same format as commit messages: `<type>(<scope>): <subject>`

## Project Architecture

### Repository Map
- `src/`: core runtime, compiler, execution engines
  - `src/vm/` - DTVM core implementation and wrapped host interface
  - `src/runtime/` - Execution environments and instance management for EVM
  - `src/compiler/` - dMIR (deterministic Middle IR) compiler:
    - `evm_frontend/` - EVM bytecode to dMIR translation
    - `mir/` - Middle Intermediate Representation core
    - `cgir/` - Code generation IR and optimization passes
  - `src/evm/` - EVM interpreter and opcode handlers
  - `src/action/` - Module loading, instantiation, and bytecode visiting infrastructure
  - `src/common/` - Shared utilities, error handling, type definitions
- `tests/`: Test suites
  - `tests/evm_spec_test` - EVM spec tests
- `docs/`: build and usage guides (`docs/start.md`, `docs/user-guide.md`)
- `evmc/`: EVM compatibility components
- `rust_crate/`: Rust bindings
- `tools/`: helper scripts and utilities
- `openspec/`: spec-driven change proposals and references

## Build Commands

### Multipass JIT (requires LLVM 15, x86-64 only)
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug \
  -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF \
  -DZEN_ENABLE_EVM=ON \
  -DZEN_ENABLE_SPEC_TEST=ON \
  -G Ninja
cmake --build build -j
```

### Build Options
- `-DZEN_ENABLE_SPEC_TEST=ON` - Enable spec tests (required for testing)
- `-DZEN_ENABLE_LINUX_PERF=ON` - Enable for performance testing
- `-DZEN_ENABLE_ASAN=ON` - Enable AddressSanitizer
- `-DZEN_ENABLE_JIT_LOGGING=ON` - Enable JIT logging
- `-DZEN_ENABLE_JIT_BOUND_CHECK=ON` - Enable JIT bounds checking
- `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` - Generate compile_commands.json
- `-DCMAKE_BUILD_TYPE=RelWithDebInfo` - Use instead of `Debug` for performance testing

## Testing

### EVM State Tests

**Built-in EVM state tests:**
```bash
./build/evmStateTests
```

**Evmone State Tests with DTVM VM:**
```bash
# Test specific fork (e.g., Cancun)
/root/evmone/build/bin/evmone-statetest \
  /root/DTVM/tests/evm_spec_test/ALL_STATE_TESTS/ \
  --vm "/root/DTVM/build/lib/libdtvmapi.so,mode=interpreter,enable-evm-gas=1" \
  -k "fork_Cancun"
```

**Run all JSON state tests with GTest output:**
```bash
rg --files -g '*.json' -g '!index.json' /root/DTVM/tests/evm_spec_test/state_tests -0 \
  | xargs -0 /root/evmone/build/bin/evmone-statetest \
    --vm "/root/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable-evm-gas=1" \
    -k "fork_Cancun" \
    --gtest_output=json:/tmp/evmone_all.json
```

### Test Structure

**EVM State Tests (`tests/evm_spec_test/state_tests`):**
- JSON files: Test case specifications executed by the state test runner
- Python files: Test case generators that define the test logic

## Development Tools

### Code Formatting
**IMPORTANT:** Always run format check before finishing a task.

```bash
# Check code format (run before finishing task)
tools/format.sh check

# Format code automatically (run after modifying code)
tools/format.sh format
```

## Performance Profiling

Performance testing and sampling scripts are located in the `perf/` directory:

```bash
# Record callgraph for ERC20 workload (default: interpreter)
./perf/record_erc20_perf.sh [multipass|interpreter]

# Record callgraph for fibr workload (default: interpreter)
./perf/record_fibr_perf.sh [multipass|interpreter]
```

**Note:** Enable `-DZEN_ENABLE_LINUX_PERF=ON` when building for performance testing.

## Documentation Pointers

- Overview: `README.md`
- Build/testing: `docs/start.md`
- Usage details: `docs/user-guide.md`
- Commit conventions: `docs/COMMIT_CONVENTION.md`
