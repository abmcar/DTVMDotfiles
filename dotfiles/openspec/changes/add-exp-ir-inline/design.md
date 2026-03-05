## Context
- Multipass EVM JIT currently lowers EXP to a runtime helper (evmGetExp), which computes exponentiation and charges dynamic gas based on exponent byte size.
- Base EXP gas is still metered via the opcode metrics table. The runtime helper handles only the per-byte gas and the 256-bit exponentiation.
- For perf analysis with Linux perf JIT symbols, keeping EXP work inside the JIT improves visibility and removes runtime call overhead.

## Goals / Non-Goals
- Goals:
  - Inline EXP lowering in multipass MIR without calling the runtime EXP helper.
  - Preserve EVM semantics: (base ^ exponent) mod 2^256 and revision-specific dynamic gas.
  - Add a deterministic EXP-dense Solidity contract fixture to measure perf before/after.
- Non-Goals:
  - No changes to interpreter semantics.
  - No new opcode semantics or EVM revisions.
  - No changes to gas tables beyond matching the existing EXP byte cost rule.

## Decisions
- Decision: Inline EXP using square-and-multiply in MIR.
  - Rationale: Works for variable exponents, uses existing U256 operations (mul, and, shr) already implemented in EVMMirBuilder.
- Decision: Compute exponent byte size in MIR to charge dynamic gas.
  - Rationale: Avoids runtime helper, keeps gas accounting inside JIT.
  - Approach: Inspect the highest non-zero 64-bit limb, compute its significant byte count via clz, and combine with limb index.
- Decision: Keep the runtime EXP helper for other paths.
  - Rationale: Interpreter and any non-multipass paths still rely on existing runtime helpers, avoiding ABI changes.

## Implementation Notes
- Inline exponentiation algorithm:
  - Initialize result = 1, base = Base, exponent = Exponent.
  - Loop while exponent != 0:
    - If (exponent & 1) != 0, result = result * base.
    - base = base * base.
    - exponent = exponent >> 1.
  - Return result as U256.
- Dynamic gas calculation:
  - If exponent == 0, exponent byte size = 0.
  - Else determine the highest non-zero limb among [3..0].
  - For the selected 64-bit limb, compute clz (0..64) and derive significant bytes = 8 - (clz >> 3).
  - Total exponent bytes = limb_index * 8 + significant_bytes.
  - GasPerByte = 10 for pre-Spurious Dragon, 50 otherwise (compile-time constant from context revision).
  - Charge dynamic gas via chargeDynamicGasIR(exponent_bytes * GasPerByte).

## Risks / Trade-offs
- Larger MIR blocks and control flow for EXP may increase code size and register pressure.
- Any mismatch in exponent byte size computation would cause gas regressions; requires careful verification.

## Migration Plan
- No migration required; behavior remains EVM-compatible.

## Open Questions
- None (baseline perf will use default revision and configuration as requested).
