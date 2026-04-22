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
    - `wasm_frontend/` — WASM bytecode to dMIR translation
    - `frontend/` — shared frontend scaffolding
    - `mir/` — Middle Intermediate Representation core
    - `cgir/` — Code generation IR and optimization passes
    - `target/` — target-specific lowering (x86 CgIR peephole lives here)
    - `stub/`, `common/`, `utils/`, `llvm-prebuild/` — support code
    - top-level `.cpp`: `compiler.cpp`, `evm_compiler.cpp`, `ircompiler.cpp` orchestrate the pipeline
  - `src/evm/` — EVM interpreter and opcode handlers
  - `src/action/` — Module loading, instantiation, and bytecode visiting
  - `src/common/` — Shared utilities, error handling, type definitions
  - `src/singlepass/` — singlepass JIT path (WASM only; incompatible with `ZEN_ENABLE_EVM`)
  - `src/host/` — host function implementations (`env`, `evm`, `evmabimock`)
  - `src/platform/`, `src/cli/`, `src/entrypoint/`, `src/wni/`, `src/utils/` — supporting subsystems
  - `src/tests/` — C++ unit tests (distinct from top-level `tests/`)
- `tests/` — Test suites (`tests/evm_spec_test` for EVM spec tests)
- `docs/` — Build and usage guides (`docs/start.md`, `docs/user-guide.md`)
- `evmc/` — EVM compatibility components
- `rust_crate/` — Rust bindings
- `tools/` — Helper scripts and utilities
