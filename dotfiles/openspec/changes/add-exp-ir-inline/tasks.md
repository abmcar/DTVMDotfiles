## 1. EXP-dense fixture and baseline perf
- [x] 1.1 Add a new Solidity contract fixture under perf/exp_dense with an EXP-heavy loop (variable exponent, deterministic output).
- [x] 1.2 Compile exp_dense.sol for dtvm consumption (deploy + runtime bytecode artifacts under perf/).
- [x] 1.3 Build dtvm with perf flags: -DZEN_ENABLE_SPEC_TEST=ON, -DZEN_ENABLE_MULTIPASS_JIT=ON, -DZEN_ENABLE_SINGLEPASS_JIT=OFF, -DZEN_ENABLE_EVM=ON, -DZEN_ENABLE_EVM_GAS_REGISTER=OFF, -DZEN_ENABLE_LIBEVM=ON, -DZEN_ENABLE_JIT_LOGGING=OFF, -DZEN_ENABLE_LINUX_PERF=ON, -DCMAKE_BUILD_TYPE=RelWithDebInfo, -DCMAKE_EXPORT_COMPILE_COMMANDS=ON, -G Ninja.
- [x] 1.4 Run dtvm in EVM multipass mode to deploy and call exp_dense, capture baseline perf timing and perf report (Linux perf JIT dump enabled).

## 2. Inline EXP lowering in multipass MIR
- [x] 2.1 Implement exponent byte-size computation in EVMMirBuilder and charge dynamic gas via chargeDynamicGasIR.
- [x] 2.2 Replace EVMMirBuilder::handleExp runtime call with inline square-and-multiply MIR (U256 ops, loop control blocks).
- [x] 2.3 Keep runtime helper intact for interpreter/other paths; ensure revision-specific gas per byte matches existing rules.

## 3. Validation and perf comparison
- [x] 3.1 Run dtvm with exp_dense in multipass mode to validate deterministic output.
- [x] 3.2 Re-run dtvm perf with identical inputs and collect after-change timing/report.
- [x] 3.3 Record before/after metrics and percent delta in the change summary.
