---
description: DTVM repository structure and navigation guide
globs: []
alwaysApply: true
---

# Repository Map

- `src/` — core runtime, compiler, execution engines
  - `src/vm/` — DTVM core implementation and wrapped host interface
  - `src/runtime/` — Execution environments and instance management for EVM
  - `src/compiler/` — dMIR (deterministic Middle IR) compiler:
    - `evm_frontend/` — EVM bytecode to dMIR translation
    - `mir/` — Middle Intermediate Representation core
    - `cgir/` — Code generation IR and optimization passes
  - `src/evm/` — EVM interpreter and opcode handlers
  - `src/action/` — Module loading, instantiation, and bytecode visiting
  - `src/common/` — Shared utilities, error handling, type definitions
- `tests/` — Test suites (`tests/evm_spec_test` for EVM spec tests)
- `docs/` — Build and usage guides (`docs/start.md`, `docs/user-guide.md`)
- `specs/` — SSOT module specifications and feature workflow documents
- `evmc/` — EVM compatibility components
- `rust_crate/` — Rust bindings
- `tools/` — Helper scripts and utilities
