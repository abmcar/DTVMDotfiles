# Tasks: implement-eip6780-selfdestruct

## Implementation Tasks

1. Add transaction-level contract creation tracking to EVMInstance
   - Add `std::unordered_set<evmc::address>` field to track created contracts
   - Add methods to register created contracts and query creation status
   - Add method to clear tracking state at transaction boundaries

2. Update CREATE handler to register created contracts
   - Record successful contract creation addresses in tracking set
   - Handle revert scenarios (do not record on revert)

3. Update CREATE2 handler to register created contracts
   - Record successful contract creation addresses in tracking set
   - Handle revert scenarios (do not record on revert)

4. Implement EIP-6780 SELFDESTRUCT semantics
   - Check if contract was created in current transaction
   - Only call `Host->selfdestruct()` for same-transaction creations
   - Transfer balance for pre-existing contracts without destruction

## Validation Tasks

5. Run EVM state tests and verify SELFDESTRUCT test pass rate
   - Execute: `rg --files -g '*.json' -g '!index.json' /root/DTVM/tests/evm_spec_test/ALL_STATE_TESTS -0 | xargs -0 /root/evmone/build/bin/evmone-statetest --vm "lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" -k "fork_Cancun"`
   - Verify pass rate >= 98%

6. Verify no regression in existing tests
   - Run built-in EVM tests: `./build/evmStateTests`
   - Confirm all previously passing tests still pass

7. Run code format check
   - Execute: `tools/format.sh check`
   - Fix any formatting issues if found
