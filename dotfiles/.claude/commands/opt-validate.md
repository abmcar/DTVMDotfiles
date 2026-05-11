---
name: opt-validate
description: Run the standard compiler→test→perf validation pipeline after an optimization change. Dispatches compiler-agent (build), test-agent (correctness), and perf-agent (benchmark) in sequence.
---

# Optimization Validation Pipeline

Run the full validation pipeline for a compiler or runtime optimization.

## Pipeline

Dispatch agents sequentially using the coordinator pattern:

1. **Build** — Spawn **compiler-agent** to build the project (`dtvmapi` target).
2. **Correctness** — Spawn **test-agent** to run evmone-unittests. Stop and report if failures.
3. **Performance** — Spawn **perf-agent** to run `/bench-compare` (branch vs baseline).

## Output

Report a summary table:

| Stage | Result | Details |
|-------|--------|---------|
| Build | PASS/FAIL | warnings count |
| Tests | PASS/FAIL | X/804 passed |
| Perf  | +X.XX% / -X.XX% | geo mean vs baseline |
