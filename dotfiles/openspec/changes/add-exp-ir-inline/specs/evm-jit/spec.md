## ADDED Requirements
### Requirement: Inline EXP lowering in multipass JIT
The system SHALL lower the EVM EXP opcode to inline MIR in multipass mode without calling the runtime EXP helper, while preserving revision-specific dynamic gas accounting.

#### Scenario: Multipass EXP lowering
- **WHEN** the JIT compiles an EXP opcode in multipass mode
- **THEN** it SHALL emit MIR that computes base^exponent mod 2^256
- **AND** it SHALL charge the EXP dynamic gas based on exponent byte size
- **AND** it SHALL not call the runtime EXP helper for that opcode

#### Scenario: Revision-specific EXP byte cost
- **WHEN** the active revision is pre-Spurious Dragon
- **THEN** the dynamic EXP byte cost SHALL be 10 gas per exponent byte
- **AND** otherwise it SHALL be 50 gas per exponent byte

#### Scenario: Zero exponent handling
- **WHEN** the exponent is zero
- **THEN** the inline EXP result SHALL be 1
- **AND** the dynamic EXP byte cost SHALL be zero
