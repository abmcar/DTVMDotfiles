---
name: dtvm-evmone-benchmark
description: Run local DTVM EVM benchmarks through evmone benchmark tools. Use when Codex needs to run `evmone-bench` with DTVM as an external EVMC VM, choose the right VM argument shape, benchmark suite path, filter, repetition settings, or explain how to benchmark a local DTVM EVM build without reconstructing the evmone command line from scratch.
---

# DTVM evmone Benchmark

Run local DTVM EVM benchmarks through evmone with the right VM argument shape.

Use this skill for local evmone benchmark execution. For CI build reproduction, use
`dtvm-build-config`. For JIT log and spill analysis, use
`dtvm-jit-lowering-inspection`.

## Workflow

1. Rebuild the DTVM library that will be benchmarked.
2. Identify the evmone benchmark entrypoint:
   - `evmone-bench` for the standard benchmark suite
   - `evmc run --bench` only when the user explicitly wants one-off custom
     bytecode timing
3. Construct the EVMC VM argument in the DTVM format:
   `<libdtvmapi.so>,mode=<interpreter|multipass>,enable_gas_metering=<true|false>`
4. Point evmone at the benchmark suite directory.
5. Add filters or repetition flags only if the user asks for them or if the
   benchmark task clearly needs them.

## Benchmark Rules

- Use `evmone-bench` as the default path for local DTVM EVM benchmarking.
- Use the DTVM EVMC option key `enable_gas_metering` with an underscore, not
  `enable-evm-gas`.
- The first positional argument is always the EVMC VM config string.
- The second positional argument is always the benchmark suite directory.
- If the user wants a full external total sweep once, include
  `--benchmark_filter='^external/total/(main|micro)/' --benchmark_repetitions=1`.
- If the user wants one custom microbenchmark bytecode, prefer a dedicated
  helper such as `tools/bench_u256_mul.py` or `evmc run --bench`, but only when
  the benchmark is intentionally custom.

## Output Requirements

When giving a benchmark command, report:

- the exact `libdtvmapi.so` path
- the exact evmone binary path
- the execution mode inside the EVMC config string
- whether gas metering is enabled
- the benchmark suite directory
- any extra filter or repetition flags

If the user is not asking specifically about evmone benchmark usage, do not
force this skill onto broader benchmark-interpretation questions.

## References

- Read [references/benchmark-playbook.md](references/benchmark-playbook.md) for
  canonical evmone benchmark command shapes.
