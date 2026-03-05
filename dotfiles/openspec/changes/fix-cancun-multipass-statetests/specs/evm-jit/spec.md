## ADDED Requirements
### Requirement: Multipass gas metering parity
The system SHALL ensure multipass JIT execution with gas metering enabled matches Cancun opcode gas accounting and observable state/log outcomes.

#### Scenario: Static call and precompile execution
- **WHEN** multipass executes Cancun STATICCALL/CALL/CALLCODE/DELEGATECALL to precompiles
- **THEN** it SHALL charge the correct gas costs and produce the same state root and logs as the reference execution

#### Scenario: SSTORE and refund behavior
- **WHEN** multipass executes Cancun SSTORE operations with gas metering enabled
- **THEN** it SHALL apply the correct gas and refund semantics and preserve expected post-state

