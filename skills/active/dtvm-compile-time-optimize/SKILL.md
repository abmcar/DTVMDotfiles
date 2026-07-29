---
name: dtvm-compile-time-optimize
description: Orchestrate a paired, evidence-gated DTVM compile-time optimization from cold profile through minimum compiler change and an isomorphic baseline-candidate benchmark. Use only when the user explicitly invokes this end-to-end optimization workflow.
---

# DTVM Compile-Time Optimize

Run a **paired baseline-candidate benchmark**. Use `$dtvm-worktree-bootstrap`
only when clean initialized baseline and candidate worktrees do not already
exist, then invoke
`$dtvm-cold-compile-profile` and `$dtvm-compiler-path-analysis`. After evidence
identifies a source seam, enter `$dtvm-dev-workflow` before any `src/**` edit,
then delegate the accepted change to `compiler-agent`.

## 1. Freeze the comparison contract

Before profiling, record:

- baseline commit and intended candidate ancestry;
- one CMake configure command and build type;
- corpus paths and hashes;
- one structured subject-command manifest per variant;
- cold-process definition;
- direct-timing repetition count and run order;
- primary paired statistic, resampling/interval method, and confidence level;
- a minimum practical improvement fixed from timer resolution and baseline
  noise before candidate results are visible;
- perf event, frequency, and call-graph mode;
- correctness tests and quality gates.

Use clean, isolated worktrees. If either is missing, invoke
`$dtvm-worktree-bootstrap` before profiling. Choose at least 20 matched pairs
in balanced interleaved blocks, fixing the order or randomization seed before
measurement. Start a fresh subject process for every cold compilation. Preserve
OS cache state rather than using privileged cache drops.

Completion criterion: after the allowed root normalization, every comparison
dimension has one recorded value shared by baseline and candidate; only commit
and resulting binary hash may differ. The acceptance threshold and uncertainty
rule are frozen before candidate timing starts.

### Normalization contract

Treat normalization as a narrow equality proof, not a scrubber. Create each
subject-command manifest as JSON:

```json
{
  "schema_version": 1,
  "cwd": {"kind": "worktree_path", "value": "/abs/baseline"},
  "argv": [
    {"kind": "literal", "value": "/opt/evmone/evmone-bench"},
    {"kind": "build_path", "value": "/abs/baseline/build/lib/libdtvmapi.so"},
    {"kind": "literal", "value": "/data/corpus/erc20.hex"}
  ],
  "environment": {"LC_ALL": "C"}
}
```

Use `literal` for flags, corpus operands, external executables, and every other
value whose bytes must match. Use `build_path` for a corresponding built
executable or library operand whose whole value is below the build root. Use
`worktree_path` only when the whole field is an operational path below the
worktree root. Label a path below the build root as `build_path`, never
`worktree_path`.

The comparison helper permits exactly two transformations:

1. replace a standalone, canonical `CMakeCache.txt` path value below the
   declared build or worktree root with `${BUILD}/<relative suffix>` or
   `${WORKTREE}/<relative suffix>`; a path value must have CMake type `PATH` or
   `FILEPATH`, be one of CMake's three root fields, or use the generated
   `*_SOURCE_DIR` / `*_BINARY_DIR` form;
2. make the same replacement for a command field explicitly typed
   `build_path` or `worktree_path`.

It preserves the relative suffix, cache key, and cache type. It never
normalizes substrings, CMake lists, compiler flags, literal command fields,
environment values, corpus paths or hashes, toolchain paths, host identity, or
any path outside the two declared roots. A root path embedded in `-I...` must
therefore remain different. Do not add a broader replacement rule to make a
comparison pass.

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

## 4. Enter the project change workflow

Profiling and read-only source analysis may finish before proposal work because
their evidence determines whether a change is justified. After finding a
defensible seam, complete these gates before any `src/**` edit:

1. Resolve `$dtvm-dev-workflow` through the current skill discovery paths. If
   `$dtvm-dev-workflow` is not discoverable, stop before any `src/**` edit and
   report the missing workflow; do not fall through to `compiler-agent`.
2. Invoke `$dtvm-dev-workflow` for the measured performance improvement. Treat
   an ordinary performance improvement as an enhancement, not a feature, and
   do not invoke `$dtvm-dev-cycle` by default. Escalate only when the accepted
   scope becomes a feature, architecture change, or breaking change under the
   current project escalation rules.
3. Create or update
   `docs/changes/YYYY-MM-DD-<slug>/README.md` at the tier selected by the
   workflow. Carry the baseline bundle, evidence table, mechanism, falsifier,
   minimum seam, invariants, paired-benchmark contract, and quality gates into
   its proposal and implementation plan.
4. Consult the relevant `docs/modules/<module>/spec.md` files. Record affected
   module contracts and required spec updates in the change document; record
   an evidence-based `not affected` result when no module contract changes.
5. Require the change document to reach `Accepted` before implementation.
   Keep it `Accepted` until merge. Never mark an unmerged change
   `Implemented`, including after local implementation, tests, benchmark, or
   report completion.

Use the accepted change document as the implementation and commit declaration
required by the current project workflow. Run its current local declaration
validator before committing the candidate.

Completion criterion: `$dtvm-dev-workflow` is available and invoked, the change
document exists at the project path with status `Accepted`, relevant module
specs have been consulted, and its ordered plan covers the exact seam and
verification gates. If any gate is missing, end without editing `src/**`.

## 5. Delegate the compiler change

Only after the project-workflow completion criterion passes, dispatch
`compiler-agent` with:

- the accepted change-document path and relevant module-spec constraints;
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
The change document remains `Accepted`.

## 6. Run the isomorphic paired benchmark

Verify ancestry first:

```bash
git merge-base --is-ancestor "$BASELINE_COMMIT" "$CANDIDATE_COMMIT"
```

Build the baseline and candidate with the frozen configure command. Verify normalized
`CMakeCache.txt` and structured subject commands with:

```bash
SKILL_DIR="<installed-skill-directory>/dtvm-compile-time-optimize"
python3 "$SKILL_DIR/scripts/compare_paired_identity.py" \
  --baseline-worktree "$BASELINE_WORKTREE" \
  --baseline-build "$BASELINE_BUILD" \
  --baseline-cache "$BASELINE_BUILD/CMakeCache.txt" \
  --baseline-command "$BASELINE_COMMAND_JSON" \
  --candidate-worktree "$CANDIDATE_WORKTREE" \
  --candidate-build "$CANDIDATE_BUILD" \
  --candidate-cache "$CANDIDATE_BUILD/CMakeCache.txt" \
  --candidate-command "$CANDIDATE_COMMAND_JSON" \
  --output "$COMPARISON_DIR/paired-identity.json"
```

Use canonical, existing absolute worktree and build paths; the build must be
below its worktree. The helper exits `0` only when both normalized identities
match, `1` for a comparison mismatch, and `2` for invalid input. It refuses to
overwrite its output. Retain the report, both raw manifests, and both raw
caches.

Separately verify corpus hashes, host, repetition count, and run order match.
Run direct timings in the frozen interleaved order, then invoke
`$dtvm-cold-compile-profile` once for each variant with identical perf settings.

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
The unmerged change document remains `Accepted`.

## 7. Make the claim

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

Invoke `$dtvm-write-report` for the reader-facing result. Return the comparison
contract, distribution table, perf-attribution table, diff summary, gate
results, artifact paths, limitations, and verdict as supporting evidence. An
unverified candidate is never reported as faster, and the report must pass the
report skill's lint before handoff. Keep the change document `Accepted` through
handoff; only the post-merge workflow may change it to `Implemented`.
