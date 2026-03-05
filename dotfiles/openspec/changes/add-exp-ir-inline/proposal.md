# Change: Inline EXP in multipass IR and add EXP-dense perf fixture

## Why
Multipass currently lowers EXP to a runtime helper call, which adds call overhead and hides EXP work inside runtime frames during perf analysis. An EXP-dense workload needs a dedicated contract fixture so we can baseline performance, implement IR inlining, and compare before/after results using Linux perf JIT symbols.

## What Changes
- Add an EXP-dense Solidity contract fixture for performance testing under perf/.
- Inline EXP lowering in the multipass EVM MIR builder, including dynamic gas charging based on exponent byte size.
- Update perf/benchmark workflow for dtvm runs with DZEN_ENABLE_LINUX_PERF=ON builds.

## Impact
- Affected specs: evm-jit, evm-tests
- Affected code: EVM MIR lowering, EVM runtime helper usage, Solidity test fixtures
