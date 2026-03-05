# Change: Fix Cancun multipass static state test mismatches

## Why
Cancun static state tests in multipass mode currently produce post-state roots and log hashes that differ from expected results. This blocks correctness validation for the primary multipass execution path and makes it harder to trust JIT output.

## What Changes
- Define parity requirements for multipass execution with gas metering enabled under Cancun.
- Add explicit requirements for Cancun static state tests in the test harness.
- Add a phased fix plan focused on the highest-failure suites (static call/precompile, wallet tests, random tests, SSTORE/logs).

## Impact
- Affected specs: evm-execution, evm-jit, evm-tests.
- Affected code (anticipated): src/evm/, src/runtime/, src/compiler/evm_frontend/, src/vm/, tests/evm_spec_test/.

