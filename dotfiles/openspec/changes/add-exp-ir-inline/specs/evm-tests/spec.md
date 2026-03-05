## ADDED Requirements
### Requirement: EXP-dense Solidity performance fixture
The system SHALL include an EXP-dense Solidity contract fixture under perf/exp_dense to support multipass performance benchmarking.

#### Scenario: Fixture layout
- **WHEN** the performance fixture is prepared
- **THEN** the exp_dense directory SHALL provide exp_dense.sol and compiled bytecode artifacts for dtvm
- **AND** the contract SHALL produce deterministic outputs for validation

#### Scenario: Benchmark execution
- **WHEN** dtvm runs the exp_dense contract in EVM multipass mode
- **THEN** the contract SHALL execute an EXP-heavy loop driven by calldata inputs
- **AND** it SHALL be suitable for repeated performance measurement
