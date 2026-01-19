# Change: Optimize U256 Arithmetic Operations in IR Layer

## Why
Currently, EVM multipass JIT uses runtime function calls to the intx library for U256 arithmetic operations (MUL, DIV, SDIV, MOD, SMOD, ADDMOD, MULMOD). This introduces significant performance overhead due to:
- Function call overhead (parameter passing, stack frame setup, return value handling)
- Missed optimization opportunities at the IR and code generation levels
- Inability to leverage IR-level optimizations like constant folding and instruction fusion

By implementing these operations directly in the IR layer, we can reduce runtime overhead and improve execution performance for arithmetic-heavy EVM workloads.

## What Changes
- Implement IR-level U256 arithmetic operations for MUL, DIV, SDIV, MOD, SMOD, ADDMOD, MULMOD
- Replace runtime function calls with direct IR instruction sequences
- Leverage intx library algorithms as implementation reference
- Add IR-level optimizations for common patterns (e.g., division by constant)
- Maintain full EVM specification compliance and correctness

## Impact
- **Affected specs**: evm-jit
- **Affected code**:
  - `src/compiler/evm_frontend/evm_mir_compiler.cpp` - Replace `handleMul`, `handleDiv`, `handleMod`, `handleSDiv`, `handleSMod`, `handleAddMod`, `handleMulMod` implementations
  - `src/compiler/evm_frontend/evm_imported.{h,cpp}` - Runtime functions remain for backward compatibility but may be deprecated
- **Performance impact**: Expected 10-30% performance improvement for arithmetic-heavy workloads (e.g., fibonacci, cryptographic operations)
- **Testing requirements**: All EVM state tests must pass; performance validation using `perf/fibr.evm.hex` benchmark
- **Build configuration**: Requires `-DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_EVM=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo`
