# Design: implement-eip6780-selfdestruct

## Overview
This design implements EIP-6780 SELFDESTRUCT semantics by tracking contract creation at the transaction level within DTVM's EVM execution engine.

## Background

### EIP-6780 Changes
EIP-6780 (activated in Cancun fork) modified SELFDESTRUCT behavior:
- **Pre-Cancun**: SELFDESTRUCT always destroys the contract account and code
- **Post-Cancun**: SELFDESTRUCT only destroys contracts created in the same transaction; pre-existing contracts only transfer balance

This change reduces state bloat and improves security by limiting contract destruction.

### Current Implementation Gap
Current code at `src/evm/opcode_handlers.cpp:1566`:
```cpp
Frame->Host->selfdestruct(Frame->Msg.recipient, Beneficiary);
```

This unconditionally calls selfdestruct without checking creation status, causing 121 test failures in Cancun fork tests.

## Architecture

### State Tracking Location
Track created contracts in `EVMInstance` (per-transaction state):
- **Rationale**: EVMInstance represents a single transaction execution context
- **Lifecycle**: Created at transaction start, destroyed at transaction end
- **Scope**: All CREATE/CREATE2 operations within nested calls record to the same set

### Data Structure
```cpp
class EVMInstance {
  // Existing fields...

  // Track contracts created in current transaction (for EIP-6780)
  std::unordered_set<evmc::address> CreatedContracts;

  // Register a contract as created in this transaction
  void registerCreatedContract(const evmc::address& addr);

  // Check if contract was created in this transaction
  bool wasCreatedInTransaction(const evmc::address& addr) const;

  // Clear creation tracking (called at transaction boundaries)
  void clearCreationTracking();
};
```

### Address Comparison
`evmc::address` needs hash and equality for `std::unordered_set`:
- Check if EVMC provides hash/equality operators
- If not, provide custom hash functor using `std::hash` over address bytes

## Implementation Strategy

### Phase 1: Add Tracking Infrastructure
1. Add `CreatedContracts` field to `EVMInstance`
2. Implement `registerCreatedContract()`, `wasCreatedInTransaction()`, `clearCreationTracking()`
3. Ensure proper initialization and cleanup

### Phase 2: Update CREATE Handlers
1. Modify `CREATEHandler` in `src/evm/opcode_handlers.cpp`
2. After successful contract creation, call `Instance->registerCreatedContract(newAddress)`
3. Handle revert: do NOT register if creation reverts

### Phase 3: Update CREATE2 Handler
1. Modify `CREATE2Handler` in `src/evm/opcode_handlers.cpp`
2. After successful contract creation, call `Instance->registerCreatedContract(newAddress)`
3. Handle revert: do NOT register if creation reverts

### Phase 4: Implement EIP-6780 SELFDESTRUCT
1. Modify `SelfDestructHandler::doExecute()` in `src/evm/opcode_handlers.cpp`
2. Before calling `Host->selfdestruct()`:
   ```cpp
   const bool createdInTx = Instance->wasCreatedInTransaction(Frame->Msg.recipient);
   if (createdInTx) {
     // Original behavior: destroy contract
     Frame->Host->selfdestruct(Frame->Msg.recipient, Beneficiary);
   } else {
     // EIP-6780: only transfer balance, do not destroy
     // EVMC Host's selfdestruct() handles balance transfer even without destruction
     Frame->Host->selfdestruct(Frame->Msg.recipient, Beneficiary);
   }
   ```
3. **Note**: EVMC's `selfdestruct()` semantics post-EIP-6780 automatically handle "transfer-only" mode, so we may only need to track and the Host will do the right thing. Verify EVMC behavior.

### Revert Handling
When a call reverts, any CREATE/CREATE2 operations in that call should be rolled back:
- **Option A**: Use a stack of sets, push/pop on call/return
- **Option B**: Never remove addresses (conservative, simpler)
  - **Chosen**: Option B - simpler, slightly overcounts but safe (worst case: transfer-only when destruction was possible)

## Edge Cases

### Reentrancy
- CREATE → call A → A creates B → B selfdestructs
- B should be destroyed (created in same tx)
- **Handled**: Single transaction-level set tracks all creations

### Revert Impact
- CREATE → success, registers address → later REVERT
- **Current approach**: Address stays registered (conservative)
- **Impact**: Minimal - at most allows destruction when it shouldn't, but Cancun tests likely validate this

### Nested Transactions
- DTVM uses message stack for nested calls, but all in same transaction
- **Handled**: Single set for entire transaction

## Testing Strategy
- Rely on existing EVM spec tests (121 SELFDESTRUCT tests)
- Key test files:
  - `test_create_selfdestruct_same_tx.json` - same-tx destruction
  - `test_selfdestruct_pre_existing.json` - pre-existing contract
  - `test_reentrancy_selfdestruct_revert.json` - revert interactions

## Performance Considerations
- `std::unordered_set` lookup: O(1) average
- Expected size: <100 addresses per transaction (typical)
- Memory: ~32 bytes per address + overhead
- **Impact**: Negligible for typical transactions

## Future Extensions
- If revert rollback is needed, implement a stack-based tracking mechanism
- Add metrics/logging for debugging in development builds
