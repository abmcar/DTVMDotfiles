# Specification Delta: eip6780-selfdestruct

## Target Spec
`evm-execution`

## ADDED Requirements

### Requirement: EIP-6780 SELFDESTRUCT semantics for Cancun fork
The system SHALL implement EIP-6780 SELFDESTRUCT semantics that only destroy contracts created in the same transaction.

#### Scenario: SELFDESTRUCT on same-transaction contract
- **GIVEN** a contract is created via CREATE or CREATE2 in the current transaction
- **AND** the contract executes SELFDESTRUCT
- **WHEN** the SELFDESTRUCT opcode is executed
- **THEN** the contract account SHALL be fully destroyed
- **AND** the contract's balance SHALL be transferred to the beneficiary
- **AND** the contract code and storage SHALL be deleted

#### Scenario: SELFDESTRUCT on pre-existing contract
- **GIVEN** a contract existed before the current transaction started
- **AND** the contract executes SELFDESTRUCT
- **WHEN** the SELFDESTRUCT opcode is executed
- **THEN** the contract account SHALL NOT be destroyed
- **AND** the contract's balance SHALL be transferred to the beneficiary
- **AND** the contract code and storage SHALL remain intact

#### Scenario: CREATE followed by SELFDESTRUCT in nested calls
- **GIVEN** contract A creates contract B via CREATE
- **AND** contract B is called and executes SELFDESTRUCT
- **WHEN** SELFDESTRUCT is executed in B
- **THEN** contract B SHALL be fully destroyed
- **AND** B's balance SHALL be transferred to the beneficiary

#### Scenario: SELFDESTRUCT with REVERT interaction
- **GIVEN** a contract is created and self-destructs within a call
- **AND** the call subsequently reverts
- **WHEN** the revert occurs
- **THEN** the selfdestruct operation SHALL be reverted
- **AND** the contract SHALL remain in its pre-call state

## MODIFIED Requirements

### Requirement: Execution runtime and instance lifecycle
The system SHALL define runtime configuration inputs and per-execution instance state for EVM execution, including transaction-level contract creation tracking.

#### Scenario: Instance initialization with creation tracking
- **WHEN** an execution instance is created for a transaction
- **THEN** it SHALL initialize gas, memory, stack, and message context from the call parameters
- **AND** it SHALL initialize an empty contract creation tracking set for EIP-6780

#### Scenario: Contract creation registration
- **WHEN** a CREATE or CREATE2 operation successfully creates a contract
- **THEN** the instance SHALL record the new contract's address in the creation tracking set

#### Scenario: Creation tracking query
- **WHEN** SELFDESTRUCT queries whether a contract was created in the current transaction
- **THEN** the instance SHALL return true if the address is in the creation tracking set
- **AND** SHALL return false otherwise
