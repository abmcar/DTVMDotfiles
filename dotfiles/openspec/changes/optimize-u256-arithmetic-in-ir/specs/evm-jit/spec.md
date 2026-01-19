# evm-jit Specification Deltas

## ADDED Requirements

### Requirement: IR-level U256 arithmetic operations
The system SHALL implement U256 arithmetic operations (MUL, DIV, SDIV, MOD, SMOD, ADDMOD, MULMOD) directly in the IR layer instead of runtime function calls.

#### Scenario: Multiplication without runtime call
- **WHEN** EVM MUL opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences for 4x64 multi-precision multiplication
- **AND** the compiler SHALL NOT call the runtime function `evmGetMul`

#### Scenario: Division without runtime call
- **WHEN** EVM DIV opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences for 4x64 multi-precision unsigned division
- **AND** the compiler SHALL handle zero division by returning zero per EVM specification

#### Scenario: Signed division without runtime call
- **WHEN** EVM SDIV opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences for 4x64 multi-precision signed division
- **AND** the compiler SHALL use two's complement conversion for negative operands

#### Scenario: Modulo without runtime call
- **WHEN** EVM MOD opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences for 4x64 multi-precision unsigned modulo
- **AND** the compiler SHALL handle zero divisor by returning zero per EVM specification

#### Scenario: Signed modulo without runtime call
- **WHEN** EVM SMOD opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences for 4x64 multi-precision signed modulo
- **AND** the compiler SHALL preserve dividend sign in the result

#### Scenario: Addmod without runtime call
- **WHEN** EVM ADDMOD opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences using 512-bit intermediate
- **AND** the compiler SHALL compute (a + b) % m without overflow

#### Scenario: Mulmod without runtime call
- **WHEN** EVM MULMOD opcode is compiled in multipass mode
- **THEN** the compiler SHALL generate inline IR instruction sequences using 512-bit intermediate
- **AND** the compiler SHALL compute (a * b) % m without overflow

### Requirement: U256 arithmetic correctness
The system SHALL maintain EVM specification compliance for all U256 arithmetic operations implemented in IR.

#### Scenario: Zero division handling
- **WHEN** divisor is zero in DIV, SDIV, MOD, or SMOD operations
- **THEN** the result SHALL be zero as per EVM specification
- **AND** no exception SHALL be raised

#### Scenario: Overflow and underflow handling
- **WHEN** multiplication or addition results exceed 256 bits
- **THEN** the result SHALL wrap around (modulo 2^256) as per EVM specification

#### Scenario: Signed arithmetic edge cases
- **WHEN** SDIV or SMOD operates on minimum negative value (-2^255)
- **THEN** the result SHALL follow EVM signed arithmetic semantics

#### Scenario: Modulo by zero
- **WHEN** modulus is zero in ADDMOD or MULMOD operations
- **THEN** the result SHALL be zero as per EVM specification

### Requirement: Performance improvement validation
The system SHALL demonstrate performance improvement for arithmetic-heavy workloads when using IR-level U256 operations.

#### Scenario: Reduced runtime function call overhead
- **WHEN** arithmetic operations are implemented in IR
- **THEN** perf profiling SHALL show reduced time spent in runtime function calls
- **AND** execution time SHALL improve by at least 10% for arithmetic-heavy benchmarks

#### Scenario: Benchmark validation
- **WHEN** running fibonacci benchmark (perf/fibr.evm.hex)
- **THEN** execution time SHALL be measurably faster compared to runtime function implementation
- **AND** correctness SHALL be preserved (same output and gas consumption)
