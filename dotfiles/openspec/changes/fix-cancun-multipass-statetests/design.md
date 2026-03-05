## Context
Multipass JIT with gas metering enabled diverges from expected Cancun static state test outputs. The current failure distribution is concentrated in static call/precompile paths, wallet tests, random tests, SSTORE/log-related cases, and a smaller tail of other suites. The effort targets only Cancun and only `tests/evm_spec_test/static/state_tests`.

## Goals / Non-Goals
- Goals:
  - Achieve parity between multipass execution and expected Cancun static state test outputs.
  - Preserve determinism and avoid host-specific behavior.
  - Reduce failures in a phased, measurable manner with explicit checkpoints.
- Non-Goals:
  - Expanding coverage to non-Cancun forks.
  - Changing interpreter behavior unless required for consistency.
  - Broad refactors unrelated to the failing suites.

## Decisions
- Decision: Triage by failure cluster and fix in priority order (static call/precompile, wallet tests, random tests, SSTORE/logs, remaining tail).
- Decision: Use interpreter as a reference baseline where needed, but focus fixes on multipass correctness.
- Decision: Keep changes minimal and localized to the affected execution paths.

## Risks / Trade-offs
- Risk: Multiple root causes hidden under the same failure category.
  - Mitigation: Use representative tests per suite and expand only after confirming improvements.
- Risk: Fixes in JIT gas metering may affect performance or code size.
  - Mitigation: Prefer semantic fixes over instrumentation-heavy solutions; measure impact with a subset of tests.

## Migration Plan
- No data migration expected.
- Rollback is reverting the specific fix commits if new regressions appear.

## Open Questions
- Which suite should be the first acceptance gate if full pass is not yet achievable?
- Are there existing debugging hooks for JIT vs interpreter state/log diffs that should be reused?

