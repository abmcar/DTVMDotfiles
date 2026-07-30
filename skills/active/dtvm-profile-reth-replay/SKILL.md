---
name: dtvm-profile-reth-replay
description: Profile and compare DTVM builds on an already frozen, strict-correct Reth witness block window. Use when measuring real-block end-to-end replay, attributing process-wide CPU samples across the replay host, Reth reference path, DTVM compiler and runtime, adding an optional witness-derived cold-compile diagnostic, or sealing a reproducible baseline–candidate performance report.
---

# Profile frozen Reth replay performance

Start only from one immutable block window that `$dtvm-run-reth-replay` has
strictly replayed and sealed for both variants. This skill owns performance
comparison and attribution; it does not capture witnesses or reinterpret a
failed correctness run as performance evidence.

This package supplies the protocol and a deterministic comparison-contract
validator. It does not supply the experiment runner, statistics analyzer,
perf classifier, or evidence sealer. Reuse approved versions of those tools
or create and test them once, then bind every executable and machine-readable
test harness, complete test log, actual canonical command JSON, and test result
into the contract. Treat this as auditable self-attestation, not proof of
authorship.

Read [references/protocol.md](references/protocol.md) before preparing or
running an experiment. It defines the measurement units, schedules, CPU quiet
gate, perf classification, eligibility rules, and evidence layout.

## 1. Freeze the comparison

Create a JSON contract from the reference schema before inspecting candidate
timings from this attempt. Earlier diagnostic or historical timings do not
prevent a new formal attempt. Bind the exact corpus manifest, approved replayer, two strict-replay
seals, correctness summary, source identities, built libraries, normalized
build/command identity proof, source-relation proof, semantic validator and
result, frozen chain configuration, plus the runner/analyzer/classifier/sealer
tool set and its test result.

Precheck it without writing:

```bash
python3 "$SKILL_ROOT/scripts/validate_replay_perf_contract.py" \
  "$ATTEMPT_DIR/comparison-contract.json"
```

Only after that command reports `status: valid`, create the no-overwrite
attempt-local audit artifact:

```bash
python3 "$SKILL_ROOT/scripts/validate_replay_perf_contract.py" \
  "$ATTEMPT_DIR/comparison-contract.json" \
  --output "$ATTEMPT_DIR/comparison-contract.validation.json"
```

Use `purpose: formal` for a conclusion-bearing benchmark and
`purpose: diagnostic` for a shorter observation. A diagnostic run can locate
large effects and instrumentation faults but cannot establish a performance
effect.

Completion criterion: the validator exits zero, verifies every bound file,
checks the frozen validation schemas, statuses and input digests, and writes a
stable attempt-local contract digest before this attempt's timing starts. It
does not independently re-execute the semantic proof tools.

## 2. Prove correctness before timing

Invoke `$dtvm-run-reth-replay` when the corpus or either variant lacks a
validated evidence seal. Require every block to pass raw binding,
differential execution, pre-state root, post-state root, and receipt/gas
commitments with offline network denial and no recorded credentials.

Use the same corpus and approved replayer for baseline and candidate. Keep
strict-replay wall time out of the performance conclusion unless it was
captured later by this skill's paired schedule.

Completion criterion: the contract binds two successful strict results and
their immutable seals; one correctness failure stops the experiment.

## 3. Measure paired fresh-process runtime

Serialize formal measurement stages. Pass the CPU quiet gate before every
adjacent block-level variant pair, run two unmeasured full-window warmups in
the explicit order `AB`, then `BA`, and execute the frozen measured `AB`/`BA`
schedule. Start a fresh replay process for every block and variant;
aggregate all blocks into one full-window matched pair per round.

Retain raw nanosecond timings, exit status, correctness status, block identity,
variant order, CPU identity, and quiet-gate observation for every sample.
Never drop kernel caches, discard an inconvenient pair, or treat block-level
samples from one round as independent repetitions.

Completion criterion: all planned full-window pairs are complete, both orders
are balanced, every measured sample remains strict-correct, and the
repeatability and predeclared interval rules pass.

## 4. Attribute process-wide CPU cost

Select the highest-gas and lower-median-gas blocks deterministically from the
frozen manifest before viewing candidate profiles. Run separate fresh-process
`perf stat` and `perf record` commands in balanced order. Exclude profiled runs
from the runtime distribution.

Classify all process-wide on-CPU samples at the evidence-backed ownership
layer: replayer, DTVM, kernel, other, inherited child, or unresolved. Report
the denominator and unresolved share. Split witness/state, Reth reference,
compiler, or generated runtime only when explicit phase timers/markers or
defensible call chains support that secondary analysis.

Require the sampled memfd DTVM build ID to match the frozen library exactly
when profiles are produced. Require an attempt-local symfs/build-ID cache and
symbolized self and inclusive reports as post-run gates. Unresolved DTVM
samples block attribution completion. Do not describe sample percentages as
wall-time percentages.

Completion criterion: each representative block has balanced baseline and
candidate profiles, exact DTVM build-ID symbolization and raw perf data are
retained, and ownership shares plus unresolved samples cover the process-wide
denominator without unresolved DTVM samples.

## 5. Add focused diagnostics only when useful

For one-shot compilation cost, select the witness-derived input using the
predeclared rule and invoke `$dtvm-cold-compile-profile` once per variant.
Keep its production-equivalent interleaved timing separate from instrumented
perf cost. Label it a cold-compile diagnostic, not 16-block replay time.

When a compiler symbol is a material hotspot, invoke
`$dtvm-compiler-path-analysis` before proposing a source seam. If the user
explicitly requests the complete implementation loop, hand off to
`$dtvm-compile-time-optimize`; do not silently turn profiling into a source
change.

## 6. Seal and report

Write all results to one new attempt directory. Preserve the validated
contract, schedule, host identity, CPU quiet observations, raw timing samples,
summary statistics, perf data and reports, optional cold-compile bundles,
eligibility result, scripts with hashes, and a sorted `SHA256SUMS`. Refuse
overwrite and seal only after every referenced path and hash revalidates.

Use the bound runner, statistics analyzer, classifier, and sealer exactly.
Their machine-readable tool-validation result must remain `passed`; changing a
tool or test result requires a new contract and attempt.

Invoke `$dtvm-write-report` for reader-facing HTML or Markdown before sealing,
preserve both lint commands and logs, then create the checksum manifest and
seal. Lead with the measured end-to-end result, then explain process-wide
component shares, hotspot movement, limitations, and the next action. Call the
design a paired or interleaved baseline–candidate benchmark, never an A/B
test.

Run the read-only post-run continuity gate:

```bash
python3 "$SKILL_ROOT/scripts/validate_replay_perf_results.py" \
  "$ATTEMPT_DIR"
```

Completion criterion: it exits zero after verifying runtime, host,
eligibility, perf classification, report lint, source/build/corpus identity,
checksum coverage, and evidence-seal continuity.

Only a formal run whose correctness, identity, quietness, completeness,
repeatability, uncertainty, and evidence-seal gates all pass may support a
performance effect claim.
