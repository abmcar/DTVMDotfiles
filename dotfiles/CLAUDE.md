<!-- OPENSPEC:START -->
# Spec Workflow Instructions

These instructions are for AI assistants working in this project.

Always open `@/specs/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/specs/AGENTS.md` to learn:
- How the SSOT and feature workflow are organized
- Which Spec-Kit skills to use
- Project-specific spec, change, and implementation guidelines

Keep this managed block so tooling can refresh the instructions.

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
- `specs/`: SSOT module specifications and feature workflow documents
- `evmc/`: EVM compatibility components
- `rust_crate/`: Rust bindings
- `tools/`: helper scripts and utilities

## Build Configuration

Treat repository docs and build-related skills as authoritative for build
commands and flag combinations.

- For general local build guidance, use `docs/start.md`
- For CI-faithful EVM build and test reproduction, use the `dtvm-build-config`
  skill
- For perf-oriented build variants, use the relevant perf skills instead of
  copying stale flag sets into this file

## Testing and Performance

Detailed EVM state test, evmone benchmark, and perf workflows are maintained in
dedicated skills and repository documentation. Prefer the current skills and
repo scripts over copying old command lines into this file.

## Development Tools

### Code Formatting
**IMPORTANT:** Always run format check before finishing a task.

```bash
# Check code format (run before finishing task)
tools/format.sh check

# Format code automatically (run after modifying code)
tools/format.sh format
```

## Documentation Pointers

- Overview: `README.md`
- Build/testing: `docs/start.md`
- Usage details: `docs/user-guide.md`
- Commit conventions: `docs/COMMIT_CONVENTION.md`
- Spec workflow: `specs/AGENTS.md`
- SSOT overview: `specs/README.md`
