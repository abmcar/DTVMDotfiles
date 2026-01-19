# Design Document: U256 Arithmetic IR Optimization

## Context
DTVM's EVM multipass JIT compiler represents U256 values as four 64-bit components (`U256Inst[4]`) in little-endian order. Currently, complex arithmetic operations (MUL, DIV, MOD, etc.) call runtime functions that use the intx library. This design document outlines the approach to implement these operations directly in IR.

## Goals
- **Primary**: Reduce runtime function call overhead for U256 arithmetic operations
- **Primary**: Enable IR-level optimizations (constant folding, dead code elimination, instruction fusion)
- **Secondary**: Maintain EVM specification compliance and numerical correctness
- **Secondary**: Improve performance for arithmetic-heavy workloads by 10-30%

## Non-Goals
- Modifying interpreter or singlepass JIT modes (multipass only)
- Implementing EXP operation in IR (complex, low-priority; EXP has dynamic gas costs)
- Optimizing bitwise operations (already implemented in IR: AND, OR, XOR, SHL, SHR, SAR)
- Changing U256 representation (keep 4x64 little-endian)

## Decisions

### Decision 1: Use intx library algorithms as reference
**Rationale**: The intx library provides well-tested, correct implementations of multi-precision arithmetic. We will translate these algorithms to IR instructions rather than designing new algorithms.

**Implementation approach**:
- Study intx source code for MUL, DIV, MOD operations
- Translate C++ operations to equivalent IR instruction sequences
- Use same edge case handling (zero division → 0, overflow handling)

**Alternatives considered**:
- **Custom algorithms**: Higher risk of bugs, longer development time
- **Different multi-precision libraries**: intx is already integrated and proven

### Decision 2: Implement operations as inline IR sequences
**Rationale**: Inlining arithmetic operations in IR enables:
- Better register allocation (LLVM can optimize across operation boundaries)
- Constant propagation and folding
- Dead code elimination (unused components can be optimized away)
- Instruction scheduling and fusion

**Trade-offs**:
- **Pro**: Significant performance gains for hot paths
- **Pro**: Enables LLVM optimization passes
- **Con**: Larger code size (acceptable for multipass JIT)
- **Con**: Longer compilation time (acceptable for eager compilation)

**Alternatives considered**:
- **Call internal IR helper functions**: Still has call overhead, misses optimization opportunities
- **Keep runtime calls**: No performance improvement

### Decision 3: Handle signed operations via two's complement conversion
For SDIV and SMOD, we will:
1. Check sign bits (MSB of highest component)
2. Convert negative operands to positive via two's complement (`(~value) + 1`)
3. Perform unsigned operation
4. Convert result back to signed if needed

**Rationale**: This approach matches intx and EVM semantics, and is straightforward to implement in IR.

### Decision 4: Use 512-bit intermediates for ADDMOD and MULMOD
**Rationale**: To correctly compute `(a + b) % m` and `(a * b) % m` without overflow, we need 512-bit intermediates. We'll represent these as eight 64-bit components.

**Implementation**:
- Extend U256 operands to 512-bit (zero-extend high components)
- Perform 512-bit addition/multiplication
- Compute 512-bit modulo
- Truncate result to 256-bit

### Decision 5: Defer EXP operation optimization
**Rationale**: EXP (exponentiation) is complex and has special gas metering (dynamic cost based on exponent). Runtime call overhead is acceptable for now.

**Future work**: Implement IR-level EXP if profiling shows it's a bottleneck.

## Implementation Details

### Multi-Precision Multiplication (4x64)
```
Result[8] = 0  // 512-bit result for overflow handling
For i in [0..3]:
  Carry = 0
  For j in [0..3]:
    Product = A[i] * B[j] + Result[i+j] + Carry
    Result[i+j] = Product & 0xFFFFFFFFFFFFFFFF
    Carry = Product >> 64
  Result[i+4] += Carry
```

### Multi-Precision Division (4x64)
We'll implement a standard long division algorithm adapted from intx:
1. Normalize divisor (shift left to make MSB = 1)
2. Estimate quotient digits using high components
3. Correct quotient via trial multiplication
4. Handle remainder calculation

### Zero Division Handling
Per EVM specification:
- `DIV(x, 0) = 0`
- `MOD(x, 0) = 0`
- `SDIV(x, 0) = 0`
- `SMOD(x, 0) = 0`

We'll add explicit zero checks at the beginning of each operation.

## Risks and Mitigations

### Risk: Numerical correctness bugs
**Likelihood**: Medium
**Impact**: High (incorrect EVM execution)
**Mitigation**:
- Comprehensive testing with full EVM state tests
- Cross-validate against intx library outputs
- Add unit tests for edge cases (max values, zero, powers of 2)

### Risk: Performance regression for simple cases
**Likelihood**: Low
**Impact**: Medium
**Mitigation**:
- Profile with representative workloads
- Add fast paths for common patterns (division by powers of 2)
- Use LLVM optimization passes to eliminate dead code

### Risk: Increased compilation time
**Likelihood**: Medium
**Impact**: Low (multipass uses eager compilation)
**Mitigation**:
- Acceptable trade-off for runtime performance
- Measure and document compilation time impact

## Validation Plan

### Correctness Validation
**EVM state tests**: All tests must pass
```bash
python3 tools/run_evm_tests.py -r build/dtvm -m multipass --format evm --enable-evm-gas
```

### Performance Validation
1. **Benchmark arithmetic-heavy workload**:
   ```bash
   perf record -g -k 1 ./build/dtvm --format evm -m multipass \
     perf/fibr.evm.hex --gas-limit 0xFFFFFFFFFFFF \
     --calldata c6c2ea170000000000000000000000000000000000000000000000000000000000080003 \
     --enable-evm-gas --enable-statistics
   ```

2. **Compare perf report**: Verify reduction in runtime function call overhead
3. **Measure execution time**: Expect 10-30% improvement for arithmetic ops

## Open Questions
1. Should we keep runtime functions for interpreter mode, or implement IR logic there too?
   - **Resolution**: Keep runtime functions for now; focus on multipass JIT

2. What is the acceptable code size increase?
   - **Resolution**: Code size is not a concern for multipass eager compilation

3. Should we implement EXP in IR?
   - **Resolution**: Defer until profiling proves it's a bottleneck
