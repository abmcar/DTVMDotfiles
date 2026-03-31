---
name: dtvm-jit-lowering-inspection
description: Inspect DTVM multipass JIT output to understand whether a lowering or register-allocation change really helped. Use when building a JIT-logging variant, capturing MIR/CgIR/assembly for an EVM hot path, counting spills and copies, or explaining why a benchmark delta did or did not happen.
---

# DTVM JIT Lowering Inspection

Use JIT logs to decide whether a performance change is real before rewriting
more lowering code.

## Workflow

1. Build a logging-enabled multipass `dtvmapi` with
   `-DZEN_ENABLE_JIT_LOGGING=ON`.
2. Run one small EVM case that exercises the hot path under study.
3. Capture the complete output to a file.
4. Read three sections in order:
   - `MIR Dump`
   - `CgIR Dump After Register Allocation`
   - `Assembly Dump`
5. Count spill indicators, not just instruction mnemonics.

## What to Look For

- `Frame Objects:` count
- `MOV64mr %stack.` and `MOV64rm %stack.` traffic
- `COPY` chains around hot arithmetic
- `MULX64rr`, `ADCX64rr`, `ADOX64rr`
- `RDX = COPY ...` reload patterns
- whether dead defs or spilled temporaries cluster around the hot block

## Decision Rules

- If frame objects and stack spill/fill traffic drop materially, the schedule
  likely reduced register pressure.
- If the arithmetic looks cleaner but spill traffic rises, the change is
  probably not worth keeping.
- If benchmark gains are tiny and the logs barely change, assume noise.
- If loop-style benchmarks move and spill traffic drops, the change is likely
  real even if single-shot microcases do not move much.

## Output Requirements

For a full analysis, include:

- the build flags used for the logging build
- the exact test case used to trigger the JIT
- frame object count before and after, if comparing two logs
- approximate stack spill/fill count before and after
- the main hot-block instruction pattern in plain words
- the likely reason a schedule change helped or failed

For quick "did spills drop?" questions, a short summary is enough.

## References

- Read [references/jitlog-playbook.md](references/jitlog-playbook.md) for the
  canonical build command, log-capture command, and grep patterns.
