---
name: dtvm-compile-time-optimize
description: Orchestrate a paired, evidence-gated DTVM compile-time optimization from cold profile through minimum compiler change and isomorphic A/B verification. Use only when the user explicitly invokes this end-to-end optimization workflow.
---

# DTVM Compile-Time Optimize

Run a **paired A/B**. Use `$dtvm-worktree-bootstrap` only when clean initialized
A/B worktrees do not already exist, then invoke
`$dtvm-cold-compile-profile` and `$dtvm-compiler-path-analysis`. Delegate the
resulting `src/**` edit to `compiler-agent`.

## 1. Freeze the comparison contract

Before profiling, record:

- baseline commit and intended candidate ancestry;
- one CMake configure command and build type;
- corpus paths and hashes;
- normalized subject command;
- cold-process definition;
- direct-timing repetition count and run order;
- primary paired statistic, resampling/interval method, and confidence level;
- a minimum practical improvement fixed from timer resolution and baseline
  noise before candidate results are visible;
- perf event, frequency, and call-graph mode;
- correctness tests and quality gates.

Use clean, isolated worktrees. If either is missing, invoke
`$dtvm-worktree-bootstrap` before profiling. Choose at least 20 matched A/B
pairs in balanced interleaved blocks, fixing the order (or randomization seed)
before measurement. Start a fresh subject process for every cold compilation.
Preserve OS cache state rather than using privileged cache drops.

Completion criterion: every comparison dimension has one recorded value shared
by A and B; only commit and resulting binary hash may differ. The acceptance
threshold and uncertainty rule are frozen before candidate timing starts.

## 2. Establish the baseline

Invoke `$dtvm-cold-compile-profile` for one perf-attributed baseline run. Record
the production-equivalent direct wall-time distribution separately; a
`ZEN_ENABLE_LINUX_PERF` build can include synchronous objdump work and cannot
stand in for production timing.

Require the profile skill's completion criterion before continuing.

Completion criterion: a sealed baseline bundle exists, the direct-timing raw
samples are retained, and child-process cost is explicit.

## 3. Find the minimum seam

Invoke `$dtvm-compiler-path-analysis` with the baseline bundle and dominant
compiler symbols. Require its evidence table, source trace, falsifiable
hypotheses, invariants, and minimum seam.

Stop when the dominant cost is measurement distortion or no defensible seam is
available. Report that result as diagnosis, not as an optimization.

Completion criterion: one source seam is supported by measured mechanism and a
falsifier, or the run ends with an evidence-backed `no seam`.

## 4. Delegate the compiler change

Dispatch `compiler-agent` with:

- baseline bundle and evidence table;
- exact file-and-symbol seam;
- expected mechanism and falsifier;
- determinism and semantic invariants;
- a minimal-diff constraint;
- required tests and quality gates.

Keep unrelated refactors outside the candidate. Require the compiler agent to
return the diff, build result, relevant tests, and warning status.

Completion criterion: the candidate contains only the justified seam, compiles,
passes relevant correctness tests, passes `tools/format.sh check` and
`tools/dtvm_local_test.sh --auto`, and introduces no warnings.

## 5. Run the isomorphic A/B

Verify ancestry first:

```bash
git merge-base --is-ancestor "$BASELINE_COMMIT" "$CANDIDATE_COMMIT"
```

Build A and B with the frozen configure command. Verify normalized
`CMakeCache.txt`, corpus hashes, normalized subject command, host, repetition
count, and run order match. Run direct timings in the frozen interleaved order,
then invoke `$dtvm-cold-compile-profile` once for each variant with identical
perf settings.

Retain:

- every raw wall-time sample;
- median, mean, standard deviation, p25, p75, minimum, and maximum;
- every matched-pair absolute and relative delta;
- the predeclared confidence interval for the primary paired statistic;
- both perf bundles and target-symbol attribution;
- child-process shares;
- correctness and quality-gate logs.

Completion criterion: identities match, both distributions have the planned
sample count, both perf bundles pass integrity checks, and all gates are green.

## 6. Make the claim

Call the result a verified optimization only when:

1. the full predeclared confidence interval for the primary paired improvement
   exceeds the frozen minimum practical effect;
2. perf attribution moves in the predicted route or absolute hotspot time;
3. correctness and determinism gates pass;
4. the effect is not explained by changed corpus, config, command, repetitions,
   ancestry, or profiling child work.

If the interval crosses zero or the minimum practical effect, report
inconclusive even when the point estimate is positive. If only the instrumented
objdump branch improves, report a profiling-method change. If evidence
conflicts, name the next discriminating measurement.

Return the comparison contract, distribution table, perf-attribution table,
diff summary, gate results, artifact paths, limitations, and verdict. An
unverified candidate is never reported as faster.
