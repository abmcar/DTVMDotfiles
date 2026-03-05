# Proposal: implement-eip6780-selfdestruct

## Summary
Implement EIP-6780 SELFDESTRUCT semantics for Cancun fork to fix 121 failing EVM state tests, improving test pass rate from 93.34% to 98%+.

## Problem
DTVM currently fails 121 SELFDESTRUCT-related tests (59% of all failures) because it does not implement EIP-6780 semantics introduced in the Cancun fork. The current implementation unconditionally calls `Host->selfdestruct()` without checking if the contract was created in the same transaction.

**Test Failure Analysis**:
- Total tests: 3078
- Failed tests: 205 (93.34% pass rate)
- SELFDESTRUCT failures: 121 (59.0% of failures)
  - `test_create_selfdestruct_same_tx.json`: 36 failures
  - `test_selfdestruct_pre_existing.json`: 18 failures
  - Other selfdestruct scenarios: 67 failures

## Goals
- Implement EIP-6780 SELFDESTRUCT semantics for Cancun fork
- Track contract creation within the current transaction
- Achieve 98%+ test pass rate on Cancun fork state tests
- Maintain deterministic execution across all execution modes

## Non-Goals
- Backward compatibility with pre-Cancun SELFDESTRUCT behavior (always use new semantics)
- Optimizing tracking overhead (use simple std::unordered_set)
- Modifying Host interface or EVMC integration
- Fixing non-SELFDESTRUCT test failures in this change

## Success Criteria
- EVM state tests pass rate increases from 93.34% to at least 98%
- All SELFDESTRUCT-related test suites pass:
  - `test_create_selfdestruct_same_tx.json` (36 tests)
  - `test_selfdestruct_pre_existing.json` (18 tests)
  - `test_reentrancy_selfdestruct_revert.json` (9 tests)
- No regression in existing passing tests
- Format check passes (`tools/format.sh check`)

## Affected Specs
- `evm-execution`: Update SELFDESTRUCT opcode semantics

## Dependencies
- None

## Risks
- **Medium**: Transaction-level state tracking may introduce memory overhead in long transactions with many CREATE operations
  - Mitigation: Use efficient std::unordered_set, clear on transaction end
- **Low**: Potential edge cases with reentrancy and REVERT interactions
  - Mitigation: Comprehensive test coverage already exists in EVM spec tests

## Alternatives Considered
1. **Host interface extension**: Query Host for "created in same transaction" status
   - Rejected: Requires external Host implementation changes, less control
2. **Hybrid approach**: Internal tracking with Host query fallback
   - Rejected: Added complexity without clear benefit

## Implementation Notes
- Track created contracts in `EVMInstance` using `std::unordered_set<evmc::address>`
- Update CREATE and CREATE2 handlers to record created addresses
- Modify SELFDESTRUCT handler to check creation status before calling `Host->selfdestruct()`
- Clear tracking set at transaction boundaries
