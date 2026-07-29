---
name: dtvm-perf-profile
description: Historical reference retained after the DTVM perf-profile workflow was retired. Never invoke this skill as a workflow entry; use the active DTVM profiling, compiler-path, worktree, and reporting replacements.
---

# Retired DTVM Perf Profile Reference

Keep this directory under `skills/retired/`. Do not publish it, link it into a
skill-discovery directory, or route delegated work here.

## Replacement map

- Use `dtvm-cold-compile-profile` to seal one cold-compilation perf bundle.
- Use `dtvm-compiler-path-analysis` to trace measured compiler symbols through
  current source.
- Use `dtvm-compile-time-optimize` only for an explicitly requested end-to-end
  compile optimization.
- Use `dtvm-worktree-bootstrap` to create and build isolated DTVM worktrees.
- Use `dtvm-write-report` for a reader-facing DTVM performance report.
- Use the deployed perf-agent and current benchmark/JIT-inspection commands for
  repeated-execution runtime work.

Never read or run the repository-tracked historical helper under
`.agents/skills/dtvm-perf-profile`. Static client suppression for that name
must remain enabled.

## Preserved runtime-profile knowledge

Treat runtime execution profiling as distinct from cold compilation:

- Verify the current build cache and command before sampling. A perf-enabled
  build is needed when current DTVM sources gate JIT symbol emission on
  `ZEN_ENABLE_LINUX_PERF`.
- Use enough repeated executions for runtime samples to dominate only when the
  question is runtime cost. Verify current CLI flags from the subject binary;
  do not copy historical iteration flags blindly.
- Retain raw perf data and separate JIT compilation, instance setup, JITted EVM
  blocks, host functions, hashing, allocation, loader/kernel work, and
  instrumentation overhead. Static symbol buckets are leads, not a cost model.
- Treat timer/statistics instrumentation as measured overhead and run an
  uninstrumented comparison when it materially changes the sample.
- Preserve the exact source commit, build cache, corpus, command, perf event,
  frequency, call-graph mode, iteration count, and child-process evidence.

JITted EVM symbols historically used forms such as:

```text
EVMBB<function-index>_MAIN_ENTRY_<pc>
EVMBB<function-index>_JUMPDEST_<pc>
EVMBB<function-index>_SWITCH<index>_<pc>
```

Confirm the current emitter before relying on that grammar. Use the EVM program
counter to cross-reference current disassembly, and annotate a hot symbol only
against the retained perf data from the same run.

This reference preserves interpretation constraints, not the retired script,
its regex summary, remembered source locations, or historical recommendations.
