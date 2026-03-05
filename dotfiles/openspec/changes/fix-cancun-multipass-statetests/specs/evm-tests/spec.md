## ADDED Requirements
### Requirement: Cancun static state test execution
The system SHALL execute Cancun static state tests from `tests/evm_spec_test/static/state_tests` and validate post-state and logs.

#### Scenario: Multipass execution with gas metering
- **WHEN** the test harness runs in multipass mode with gas metering enabled
- **THEN** it SHALL execute Cancun static state tests and verify state root and log hash results

#### Scenario: Interpreter parity reference
- **WHEN** the same static state tests are executed in interpreter mode
- **THEN** the harness SHALL produce results that match the Cancun expected outputs

