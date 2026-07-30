# Frozen Reth replay performance protocol

This reference is the normative procedure for performance experiments that
start from real Ethereum blocks captured as immutable Reth execution-witness
bundles. It separates correctness, end-to-end latency, CPU attribution, and
cold compilation so one number is never asked to answer four questions.

## Contents

1. [Scope and ownership](#scope-and-ownership)
2. [Experiment classes](#experiment-classes)
3. [Preflight and comparison contract](#preflight-and-comparison-contract)
4. [Strict correctness prerequisite](#strict-correctness-prerequisite)
5. [Host and CPU isolation](#host-and-cpu-isolation)
6. [Paired runtime benchmark](#paired-runtime-benchmark)
7. [Statistics and eligibility](#statistics-and-eligibility)
8. [Representative-block perf](#representative-block-perf)
9. [Optional cold compilation](#optional-cold-compilation)
10. [Source trace and optimization handoff](#source-trace-and-optimization-handoff)
11. [Evidence seal](#evidence-seal)
12. [Reporting contract](#reporting-contract)

## Scope and ownership

Use the skills as a composition:

| Question | Owning skill |
|---|---|
| Are two Reth endpoints witness-ready, which canonical blocks were frozen, and did strict offline replay pass? | `dtvm-run-reth-replay` |
| How does one frozen real-block window perform across two DTVM builds, and where are process-wide CPU samples spent? | `dtvm-profile-reth-replay` |
| What costs one isolated DTVM cold compilation? | `dtvm-cold-compile-profile` |
| Which current compiler route owns a measured symbol and what is the minimum source seam? | `dtvm-compiler-path-analysis` |
| Can a measured compile seam be changed and verified end to end? | Explicit-only `dtvm-compile-time-optimize` |
| How should verified evidence become a reader-facing report? | `dtvm-write-report` |

This skill does not download chain data, start Reth, capture witnesses, repair
the adapter, edit `src/**`, or publish a performance report from a correctness
run's incidental wall clock. Its bundled executable validates a frozen
comparison contract; it is not the benchmark runner, statistics analyzer,
perf classifier, evidence sealer, or semantic validator for replay
correctness, paired identity, and source relation.

## Experiment classes

Choose the class before timings for the new attempt begin. Existing results
from another attempt do not prevent a fresh formal contract:

| Class | Minimum measured full-window pairs | Allowed conclusion |
|---|---:|---|
| `diagnostic` | 7 | Locate large effects, variance, or broken instrumentation. Always observational. |
| `formal` | 20 | Estimate a baseline–candidate effect only when all eligibility gates pass. |

A full-window pair is the unit of replication. Sixteen block-level pairs
inside one round share the same host state and are useful for localization,
but they are not sixteen independent experimental repetitions.

Use a fixed historical or finalized window with at least two contiguous
blocks. Prefer 16 or more blocks covering ordinary and high-gas behavior.
Record transaction count, total gas, raw bytes, bytecode count, and any known
fork boundary. Do not cross a fork boundary unless that transition is the
explicit workload.

Derive workload metadata from the frozen manifest and witness bundles, never
from a later replay result:

- `transactionCount` is the sum of raw-block transaction-list lengths;
- `totalGasUsed` is the sum of manifest `gasUsed`;
- `rawBlockBytes` is the sum of decoded raw-block byte lengths;
- `bytecodeCount` is the number of non-empty witness code entries, counting
  entries rather than deduplicating identical byte strings;
- `forkBoundary` is evaluated against the frozen chain configuration for the
  inclusive block range. Its description names the checked boundary or states
  that none occurs.

The contract binds the chain configuration or fork-schedule snapshot as
`evidence.chainConfig`. The semantic correctness role binds both its SHA-256
and the canonical digest of the workload object, then independently recomputes
the fields from those frozen inputs.

## Preflight and comparison contract

Freeze `comparison-contract.json` before timings from this attempt. Earlier
diagnostic or historical timings do not prevent a new formal attempt. The
executable validator
rejects unknown fields, malformed values, missing files, symlinked/noncanonical
artifact paths, content-hash drift, unbalanced schedules, and weak formal-run
settings.

The contract validator verifies bytes, hashes, exact schemas, `passed` status,
and input-digest continuity. It does not independently prove replay semantics,
normalized build identity, or source ancestry/change-set equivalence. Produce
those conclusions with bound, tested semantic tools and consolidate their
machine-readable results in the mandatory `semanticValidation` artifact.
Run a read-only stdout precheck first. Because the final validation artifact
uses exclusive creation, write it only after the precheck is valid; an invalid
written audit path is never repaired or overwritten.

Use this top-level schema:

```json
{
  "schema": "dtvm.reth-replay-performance-contract.v1",
  "purpose": "formal",
  "window": {
    "chainId": "0x1",
    "startBlock": 25625000,
    "endBlock": 25625015,
    "blockCount": 16
  },
  "workload": {
    "transactionCount": 4510,
    "totalGasUsed": 475666236,
    "rawBlockBytes": 2317017,
    "bytecodeCount": 1234,
    "forkBoundary": {
      "crossesKnownBoundary": false,
      "description": "No known fork boundary in the frozen window."
    }
  },
  "evidence": {
    "corpusManifest": {"path": "/absolute/realpath/manifest.json", "sha256": "64-lowercase-hex"},
    "approvedReplayerManifest": {"path": "/absolute/realpath/approved.json", "sha256": "64-lowercase-hex"},
    "approvedReplayerBinary": {"path": "/absolute/realpath/replay-block", "sha256": "64-lowercase-hex"},
    "baselineSeal": {"path": "/absolute/realpath/baseline-seal.json", "sha256": "64-lowercase-hex"},
    "candidateSeal": {"path": "/absolute/realpath/candidate-seal.json", "sha256": "64-lowercase-hex"},
    "correctnessSummary": {"path": "/absolute/realpath/correctness.json", "sha256": "64-lowercase-hex"},
    "chainConfig": {"path": "/absolute/realpath/mainnet-chain-config.json", "sha256": "64-lowercase-hex"},
    "identityProof": {"path": "/absolute/realpath/paired-identity.json", "sha256": "64-lowercase-hex"},
    "sourceRelationProof": {"path": "/absolute/realpath/source-relation.json", "sha256": "64-lowercase-hex"},
    "semanticValidator": {"path": "/absolute/realpath/validate-semantics", "sha256": "64-lowercase-hex"},
    "semanticValidation": {"path": "/absolute/realpath/semantic-validation.json", "sha256": "64-lowercase-hex"}
  },
  "variants": {
    "baseline": {
      "label": "main+required-prs",
      "commit": "40-lowercase-hex",
      "tree": "40-lowercase-hex",
      "library": {"path": "/absolute/realpath/libdtvmapi-baseline.so", "sha256": "64-lowercase-hex"},
      "cmakeCache": {"path": "/absolute/realpath/CMakeCache-baseline.txt", "sha256": "64-lowercase-hex"}
    },
    "candidate": {
      "label": "baseline+candidate-change",
      "commit": "40-lowercase-hex",
      "tree": "40-lowercase-hex",
      "library": {"path": "/absolute/realpath/libdtvmapi-candidate.so", "sha256": "64-lowercase-hex"},
      "cmakeCache": {"path": "/absolute/realpath/CMakeCache-candidate.txt", "sha256": "64-lowercase-hex"}
    }
  },
  "comparison": {
    "sameCorpusRequired": true,
    "sameApprovedReplayerRequired": true,
    "sameCommandAfterRootNormalizationRequired": true,
    "sameBuildConfigAfterRootNormalizationRequired": true,
    "sourceRelationship": "common-base-with-exact-change-set",
    "sourceRelationshipValidationRequired": true,
    "contractFrozenBeforeAttemptTiming": true,
    "allowedDifferences": ["sourceCommit", "sourceTree", "dtvmLibrary"]
  },
  "correctnessRequirements": {
    "requireStrictReplayBothVariants": true,
    "requireAllDifferentialMatches": true,
    "requireAllPreStateRootsVerified": true,
    "requireAllPostStateRootsVerified": true,
    "requireOfflineNetworkDenial": true,
    "requireNoRecordedCredentials": true
  },
  "isolation": {
    "networkDisabled": true,
    "proxyDisabled": true,
    "downloadsDisabled": true,
    "rethStopped": true,
    "formalStagesSerialized": true
  },
  "runtime": {
    "design": "balanced-adjacent-paired-fresh-process",
    "measurementUnit": "full-window-round",
    "processGranularity": "one-block",
    "warmupRounds": 2,
    "warmupSchedule": ["AB", "BA"],
    "measuredRounds": 20,
    "schedule": ["AB", "BA"],
    "cpu": {
      "logicalCpu": 50,
      "smtSiblingPolicy": "idle-or-offline",
      "maxBusyPercent": 5.0,
      "sampleWindowSeconds": 2.0,
      "consecutiveQuietWindows": 2,
      "quietBeforeEachBlockPair": true,
      "quietAfterRun": true
    },
    "networkDisabled": true,
    "dropKernelCaches": false,
    "stopOnCorrectnessFailure": true,
    "retainRawSamples": true,
    "primaryStatistic": "median-paired-full-window-relative-delta",
    "confidence": {
      "method": "paired-bootstrap",
      "level": 0.95,
      "seed": 577,
      "resamples": 10000
    },
    "minimumPracticalEffectPercent": 0.5,
    "maxRoundCvPercent": 5.0
  },
  "profiling": {
    "enabled": true,
    "selectionFrozenBeforeAttemptProfiling": true,
    "representativeBlocks": [
      {"role": "highest-gas", "blockNumber": 25625014, "blockHash": "0x64-lowercase-hex"},
      {"role": "median-gas", "blockNumber": 25625003, "blockHash": "0x64-lowercase-hex"}
    ],
    "statEvents": ["task-clock", "cycles", "instructions", "branches", "branch-misses", "cache-misses", "context-switches", "page-faults"],
    "recordEvent": "cycles",
    "recordEventScope": "user-and-kernel",
    "frequencyHz": 997,
    "callGraph": "dwarf",
    "processWide": true,
    "inheritChildren": true,
    "freshProcess": true,
    "passesPerVariantPerBlock": 2,
    "balancedOrder": true,
    "recordRunsExcludedFromRuntime": true,
    "memfdSymbolizationRequired": true,
    "dtvmBuildIdMatchRequired": true,
    "attemptLocalSymfsRequired": true,
    "symbolizedSelfAndInclusiveReportsRequired": true,
    "unresolvedDtvmAllowed": false,
    "classifications": ["replayer", "dtvm", "kernel", "other", "inherited-child", "unresolved"]
  },
  "coldCompile": {
    "enabled": false,
    "reason": "Runtime attribution is sufficient for this experiment."
  },
  "sourceTrace": {
    "skill": "dtvm-compiler-path-analysis",
    "requiredForCompilerHotspot": true,
    "requiredBeforeSourceEdit": true
  },
  "tooling": {
    "semanticValidator": {
      "executable": {"path": "/absolute/realpath/validate-semantics", "sha256": "64-lowercase-hex"},
      "testCommand": {"path": "/absolute/realpath/test-semantics.command.json", "sha256": "64-lowercase-hex"},
      "testHarness": {"path": "/absolute/realpath/test-semantics.py", "sha256": "64-lowercase-hex"},
      "testLog": {"path": "/absolute/realpath/test-semantics.log", "sha256": "64-lowercase-hex"},
      "testResult": {"path": "/absolute/realpath/test-semantics.json", "sha256": "64-lowercase-hex"}
    },
    "runtimeRunner": {
      "executable": {"path": "/absolute/realpath/run-paired-replay", "sha256": "64-lowercase-hex"},
      "testCommand": {"path": "/absolute/realpath/test-runner.command.json", "sha256": "64-lowercase-hex"},
      "testHarness": {"path": "/absolute/realpath/test-runner.py", "sha256": "64-lowercase-hex"},
      "testLog": {"path": "/absolute/realpath/test-runner.log", "sha256": "64-lowercase-hex"},
      "testResult": {"path": "/absolute/realpath/test-runner.json", "sha256": "64-lowercase-hex"}
    },
    "statisticsAnalyzer": {
      "executable": {"path": "/absolute/realpath/analyze-paired-replay", "sha256": "64-lowercase-hex"},
      "testCommand": {"path": "/absolute/realpath/test-statistics.command.json", "sha256": "64-lowercase-hex"},
      "testHarness": {"path": "/absolute/realpath/test-statistics.py", "sha256": "64-lowercase-hex"},
      "testLog": {"path": "/absolute/realpath/test-statistics.log", "sha256": "64-lowercase-hex"},
      "testResult": {"path": "/absolute/realpath/test-statistics.json", "sha256": "64-lowercase-hex"}
    },
    "perfClassifier": {
      "executable": {"path": "/absolute/realpath/classify-perf", "sha256": "64-lowercase-hex"},
      "testCommand": {"path": "/absolute/realpath/test-classifier.command.json", "sha256": "64-lowercase-hex"},
      "testHarness": {"path": "/absolute/realpath/test-classifier.py", "sha256": "64-lowercase-hex"},
      "testLog": {"path": "/absolute/realpath/test-classifier.log", "sha256": "64-lowercase-hex"},
      "testResult": {"path": "/absolute/realpath/test-classifier.json", "sha256": "64-lowercase-hex"}
    },
    "evidenceSealer": {
      "executable": {"path": "/absolute/realpath/seal-evidence", "sha256": "64-lowercase-hex"},
      "testCommand": {"path": "/absolute/realpath/test-sealer.command.json", "sha256": "64-lowercase-hex"},
      "testHarness": {"path": "/absolute/realpath/test-sealer.py", "sha256": "64-lowercase-hex"},
      "testLog": {"path": "/absolute/realpath/test-sealer.log", "sha256": "64-lowercase-hex"},
      "testResult": {"path": "/absolute/realpath/test-sealer.json", "sha256": "64-lowercase-hex"}
    },
    "validation": {"path": "/absolute/realpath/tooling-validation.json", "sha256": "64-lowercase-hex"}
  },
  "output": {
    "attemptRoot": "/absolute/non-overwritten/experiment-root",
    "attemptId": "fixed16-formal-r20",
    "contractPath": "/absolute/non-overwritten/experiment-root/fixed16-formal-r20/comparison-contract.json",
    "contractValidationPath": "/absolute/non-overwritten/experiment-root/fixed16-formal-r20/comparison-contract.validation.json",
    "refuseOverwrite": true,
    "evidenceSealRequired": true,
    "checksumManifest": "SHA256SUMS",
    "reportSkill": "dtvm-write-report",
    "claimRule": "formal-only-after-all-gates"
  }
}
```

The example abbreviates only the measured schedule; the actual `schedule`
must contain exactly `measuredRounds` entries. It may differ by one `AB`/`BA`
entry only when the count is odd. The two unmeasured full-window warmups are
always explicit `warmupSchedule: ["AB", "BA"]`.

Create `identityProof` by comparing normalized build configuration and
structured subject commands. Normalization may replace corresponding
worktree/build roots while preserving relative suffixes; it must not scrub
flags, toolchains, corpus paths, environment, or literal operands. Record the
exact source relation in `sourceRelationProof`. Use
`candidate-descends-from-baseline` when `git merge-base --is-ancestor` passes.
Use `common-base-with-exact-change-set` for separately assembled variants only
when the proof binds the shared base, shared patches/merges, candidate-only
patch identity, and effective baseline-to-candidate tree diff.

All canonical digests in the proof documents use one byte rule:
`json.dumps(value, sort_keys=True, separators=(",", ":"),
ensure_ascii=True).encode("utf-8")`, with no trailing newline. The semantic
validator log retains the expanded values that were hashed. Construct them as
follows:

- `commandCanonicalSha256`: canonical JSON of exactly
  `{"argv": [strings], "cwd": normalized-string, "environment":
  [[name,value],...]}`. Preserve argv order. Replace only the paired source,
  build, and attempt roots with `<SOURCE_ROOT>`, `<BUILD_ROOT>`, and
  `<ATTEMPT_ROOT>` while retaining relative suffixes. Sort environment pairs
  by name and reject duplicate names.
- `buildConfigCanonicalSha256`: canonical JSON of the sorted list
  `[[cacheKey,cacheType,normalizedValue],...]` parsed from `CMakeCache.txt`.
  Omit only CMake's comment/help lines and the volatile internal keys
  `CMAKE_CACHEFILE_DIR` and `CMAKE_HOME_DIRECTORY`; normalize the same paired
  roots and retain every other entry.
- `environmentCanonicalSha256`: canonical JSON of sorted `[name,value]` pairs
  for the complete subject environment recorded by the runner. Credential
  variables are forbidden rather than redacted into a value.
- `sharedChangeSetSha256` and `candidateOnlyChangeSha256`: canonical JSON of
  ordered `[[commit,tree,stablePatchId],...]` lists. Order by the application
  order recorded in the source proof; compute `stablePatchId` with
  `git show --pretty=format: --patch <commit> | git patch-id --stable`.
- `effectiveDiffSha256`: SHA-256 of the exact stdout bytes from
  `LC_ALL=C TZ=UTC git diff --binary --full-index --no-ext-diff --no-renames
  <baselineTree> <candidateTree> --`, run at the common-base repository root.
  Preserve that stdout as a bound proof-supporting artifact.

No locale-dependent text, pretty JSON, unordered map iteration, or absolute
worktree spelling may feed those digests.

`identityProof` has this exact schema. All digests are lowercase SHA-256; all
commit/tree values are lowercase 40-hex Git object IDs.

```json
{
  "schema": "dtvm.reth-replay-performance-identity-proof.v1",
  "status": "passed",
  "generator": {
    "sha256": "semantic validator executable SHA-256",
    "commandSha256": "canonical semantic validation invocation SHA-256",
    "testHarnessSha256": "semantic validator test-harness SHA-256",
    "testLogSha256": "semantic validator test-log SHA-256",
    "testCases": 3,
    "rerunVerified": true
  },
  "inputs": {
    "approvedReplayerManifestSha256": "64-lowercase-hex",
    "approvedReplayerBinarySha256": "64-lowercase-hex",
    "baselineLibrarySha256": "64-lowercase-hex",
    "candidateLibrarySha256": "64-lowercase-hex",
    "baselineCmakeCacheSha256": "64-lowercase-hex",
    "candidateCmakeCacheSha256": "64-lowercase-hex",
    "baselineCommit": "40-lowercase-hex",
    "baselineTree": "40-lowercase-hex",
    "candidateCommit": "40-lowercase-hex",
    "candidateTree": "40-lowercase-hex"
  },
  "normalized": {
    "commandCanonicalSha256": "64-lowercase-hex",
    "buildConfigCanonicalSha256": "64-lowercase-hex",
    "environmentCanonicalSha256": "64-lowercase-hex"
  },
  "allowedDifferences": ["sourceCommit", "sourceTree", "dtvmLibrary"]
}
```

`sourceRelationProof` has this exact schema:

```json
{
  "schema": "dtvm.reth-replay-performance-source-relation-proof.v1",
  "status": "passed",
  "generator": {
    "sha256": "semantic validator executable SHA-256",
    "commandSha256": "canonical semantic validation invocation SHA-256",
    "testHarnessSha256": "semantic validator test-harness SHA-256",
    "testLogSha256": "semantic validator test-log SHA-256",
    "testCases": 3,
    "rerunVerified": true
  },
  "relationship": "common-base-with-exact-change-set",
  "inputs": {
    "baselineCommit": "40-lowercase-hex",
    "baselineTree": "40-lowercase-hex",
    "candidateCommit": "40-lowercase-hex",
    "candidateTree": "40-lowercase-hex"
  },
  "commonBaseCommit": "40-lowercase-hex",
  "sharedChangeSetSha256": "64-lowercase-hex",
  "candidateOnlyChangeSha256": "64-lowercase-hex",
  "effectiveDiffSha256": "64-lowercase-hex"
}
```

The mandatory semantic result uses this frozen shape:

```json
{
  "schema": "dtvm.reth-replay-performance-semantic-validation.v1",
  "status": "passed",
  "validatorSha256": "semanticValidator SHA-256",
  "inputSetCanonicalSha256": "canonical SHA-256 of the three role input maps",
  "roles": {
    "correctness": {
      "status": "passed",
      "inputs": {
        "corpusManifestSha256": "64-lowercase-hex",
        "chainConfigSha256": "64-lowercase-hex",
        "baselineSealSha256": "64-lowercase-hex",
        "candidateSealSha256": "64-lowercase-hex",
        "correctnessSummarySha256": "64-lowercase-hex",
        "workloadCanonicalSha256": "64-lowercase-hex"
      }
    },
    "identity": {
      "status": "passed",
      "inputs": {
        "identityProofSha256": "64-lowercase-hex",
        "approvedReplayerManifestSha256": "64-lowercase-hex",
        "approvedReplayerBinarySha256": "64-lowercase-hex",
        "baselineLibrarySha256": "64-lowercase-hex",
        "candidateLibrarySha256": "64-lowercase-hex",
        "baselineCmakeCacheSha256": "64-lowercase-hex",
        "candidateCmakeCacheSha256": "64-lowercase-hex"
      }
    },
    "sourceRelation": {
      "status": "passed",
      "relationship": "common-base-with-exact-change-set",
      "inputs": {
        "sourceRelationProofSha256": "64-lowercase-hex",
        "baselineCommit": "40-lowercase-hex",
        "baselineTree": "40-lowercase-hex",
        "candidateCommit": "40-lowercase-hex",
        "candidateTree": "40-lowercase-hex"
      }
    }
  }
}
```

The contract validator requires these exact role input fields:

- correctness: corpus manifest, baseline seal, candidate seal, correctness
  summary SHA-256, and the canonical workload-metadata digest;
- identity: identity proof, approved replayer manifest/binary, both DTVM
  libraries, and both CMake cache SHA-256 values;
- source relation: proof SHA-256 plus both commit and tree IDs.

It recomputes the canonical digest of those three input maps. The bound
semantic validator owns the underlying proof and must also appear in the
tooling validation result. The contract validator also requires the proof
generator metadata to equal the bound semantic-validator test package. It
cannot forensically determine who typed a JSON file; manually asserting
`passed` is a protocol violation, and the executable/harness/log/command/test
bindings make that assertion auditable and fail closed on byte drift.

The baseline and candidate may differ only in the frozen source change and
derived DTVM artifacts. The corpus, approved replayer, host, command, build
type, compiler/toolchain, environment, affinity, and schedule must match.

## Strict correctness prerequisite

Run strict offline replay for the baseline and candidate before performance:

1. verify the exact manifest and every bundle hash;
2. verify raw block and witness binding;
3. verify pre-state root;
4. compare stock Reth and DTVM gas, receipts root, logs bloom, requests hash,
   blob gas, and state changes;
5. verify the post-state root;
6. deny socket and io_uring network paths during replay;
7. prove no credentials were recorded;
8. seal each variant's library, result, corpus, approved replayer, and runner.

Run the state validator supplied by `dtvm-run-reth-replay` and preserve its
output. A later performance sample must run the same strict path. If any
sample fails correctness, stop; do not retain the adjacent partner as an
unpaired timing.

## Host and CPU isolation

Record before and after:

- UTC start/end, hostname, kernel, CPU model and topology;
- microcode, governor, min/max/current frequency policy, turbo/boost state;
- NUMA node, selected logical CPU, its SMT sibling, and affinity;
- memory and swap, load average, thermal state when exposed;
- DTVM/replayer file hashes and build IDs;
- relevant environment variables by name and non-secret value;
- absence of Reth, downloads, proxy traffic, competing builds, and profilers.

Do not mutate governor, turbo, caches, or system services merely to make a run
pass. Record stable existing state. Pin the subject to one selected logical
CPU and keep its SMT sibling idle or offline. Put the observer on a different
physical core.

For every adjacent block-level `A/B` or `B/A` variant pair, including warmups:

1. sample `/proc/stat` for the target core for at least 2 seconds;
2. require target busy time at or below 5%;
3. require two consecutive quiet windows;
4. run both variants without another formal measurement in parallel;
5. retain the quiet observation with the pair.

Also run the gate after the final pair. A failed pre-pair gate delays the pair;
a failed post-run gate makes the affected run observational until repeated as
a new, predeclared attempt. Never silently delete noisy samples after viewing
the effect.

Write `environment/host-stability.json` with this exact schema:

```json
{
  "schema": "dtvm.reth-replay-performance-host-stability.v1",
  "status": "stable",
  "contractCanonicalSha256": "64-lowercase-hex",
  "beforeSnapshotSha256": "environment/before.json SHA-256",
  "afterSnapshotSha256": "environment/after.json SHA-256",
  "quietObservationsSha256": "runtime/quiet-observations.json SHA-256",
  "targetLogicalCpu": 50,
  "smtSiblingPolicy": "idle-or-offline",
  "allQuietGatesPassed": true,
  "stableEnvironment": true
}
```

`status: stable` is valid only when the target CPU equals the frozen contract,
all expected quiet observations exist, and the before/after comparison finds
no material host change.

## Paired runtime benchmark

Pre-hash and read all corpus inputs and both libraries once before warmup so
page-cache treatment is symmetric. Do not run privileged cache drops.

Use two unmeasured full-window warmup rounds in the exact order `AB`, `BA`.
Then alternate measured order at the full-window round level. Within a round:

1. iterate the frozen blocks in canonical order;
2. start one fresh approved replayer process for baseline and one for
   candidate per block;
3. keep the two variants adjacent;
4. reverse pair order according to that round's `AB`/`BA` entry;
5. capture monotonic nanoseconds outside the process;
6. require exit zero and strict correctness;
7. retain stdout/stderr or their hashes.

For every sample record:

- attempt, warmup/measured, round, block number/hash and bundle hash;
- order, variant, commit/tree/library/replayer hashes;
- start/end monotonic nanoseconds and elapsed nanoseconds;
- pinned CPU and quiet-observation identity;
- process exit, signal, correctness, and result hash.

Aggregate block elapsed times into a baseline and candidate total for each
full-window round. Preserve per-block pairs for hotspot localization.

The bound runner and statistics analyzer produce one immutable
`runtime-result.json` with this exact top-level schema:

```json
{
  "schema": "dtvm.reth-replay-performance-runtime-result.v1",
  "status": "complete",
  "attemptId": "fixed16-formal-r20",
  "contractCanonicalSha256": "64-lowercase-hex",
  "contractValidationSha256": "64-lowercase-hex",
  "runnerSha256": "64-lowercase-hex",
  "statisticsAnalyzerSha256": "64-lowercase-hex",
  "hostStabilitySha256": "environment/host-stability.json SHA-256",
  "schedule": {
    "warmup": ["AB", "BA"],
    "measuredScheduleSha256": "64-lowercase-hex",
    "roundsPlanned": 20,
    "roundsCompleted": 20,
    "blockCount": 16,
    "warmupSamplesExpected": 64,
    "warmupSamplesComplete": 64,
    "measuredSamplesExpected": 640,
    "measuredSamplesComplete": 640
  },
  "execution": {
    "freshProcessEverySample": true,
    "strictCorrectEverySample": true,
    "offlineEverySample": true,
    "quietBeforeEveryBlockPair": true,
    "quietAfterRun": true,
    "noConcurrentFormalStage": true,
    "stdoutStderrBound": true,
    "samplesSha256": "64-lowercase-hex",
    "roundsSha256": "64-lowercase-hex",
    "quietObservationsSha256": "64-lowercase-hex"
  },
  "statistics": {
    "pairCount": 20,
    "primaryName": "median-paired-full-window-relative-delta",
    "pointEstimatePercent": -1.25,
    "confidenceLevel": 0.95,
    "confidenceLowerPercent": -1.80,
    "confidenceUpperPercent": -0.70,
    "bootstrapSeed": 577,
    "bootstrapResamples": 10000,
    "minimumPracticalEffectPercent": 0.5,
    "baselineRoundCvPercent": 2.0,
    "candidateRoundCvPercent": 2.1,
    "aggregateCandidateToBaselineRatio": 0.9875
  }
}
```

The expected sample counts are
`warmupRounds * blockCount * 2` and
`measuredRounds * blockCount * 2`. `status: complete` is valid only when
planned and completed counts match, all execution booleans are true, every
digest resolves to attempt-local immutable evidence, and the statistics fields
are recomputed from `roundsSha256`. A runner or analyzer must emit
`status: failed` to a separate diagnostic location rather than forge a
complete attempt result.

## Statistics and eligibility

Compute without post-hoc trimming:

- per variant: count, mean, median, standard deviation, CV, p25, p75, min, max;
- per full-window matched pair: absolute delta
  `candidate - baseline`, relative delta
  `(candidate - baseline) / baseline * 100`, and order;
- primary statistic: median full-window paired relative delta;
- 95% paired bootstrap interval over full-window pairs with the frozen seed
  and at least 10,000 resamples;
- fixed practical-effect threshold: exactly 0.5%;
- secondary: ratio of aggregate candidate time to aggregate baseline time;
- per block: median paired absolute and relative delta, labeled secondary.

Do not bootstrap block pairs as independent observations. Keep the complete
round as the resampling cluster.

A formal effect is eligible only when:

1. every frozen identity and strict correctness check passes;
2. all 20 or more planned full-window pairs exist;
3. `AB` and `BA` counts differ by at most one;
4. each variant's full-window round CV is at most the predeclared cap;
5. all quiet gates pass and host state is stable;
6. the entire confidence interval lies on one side of zero;
7. the interval also clears the predeclared practical-effect threshold in the
   claimed direction;
8. no runtime sample came from `perf`, capture, download, Reth RPC, or cold
   compile;
9. the bound semantic and tooling validations remain passed and byte-identical.

If any item fails, report the point estimate and raw distribution as
observational. State the failed rule; do not call the candidate faster or
slower. A final performance claim additionally requires a verified evidence
seal, so eligibility and sealing do not form a circular self-reference.

The analyzer writes `eligibility.json` with this exact schema:

```json
{
  "schema": "dtvm.reth-replay-performance-eligibility.v1",
  "status": "passed",
  "purpose": "formal",
  "contractCanonicalSha256": "64-lowercase-hex",
  "runtimeResultSha256": "64-lowercase-hex",
  "statisticsAnalyzerSha256": "64-lowercase-hex",
  "gates": {
    "semanticValidation": true,
    "toolingValidation": true,
    "pairedIdentity": true,
    "sourceRelation": true,
    "strictCorrectness": true,
    "fullWindowCompleteness": true,
    "strictAlternatingSchedule": true,
    "repeatability": true,
    "quietness": true,
    "hostStability": true,
    "confidenceDirection": true,
    "practicalThreshold": true,
    "runtimePurity": true
  },
  "conclusionEligibleBeforeSeal": true,
  "reasons": []
}
```

The key set is exact. For a formal attempt, `status: passed`,
`conclusionEligibleBeforeSeal: true`, and an empty `reasons` array are valid
only when every gate is true. Otherwise the status is `observational`, the
conclusion boolean is false, and `reasons` contains a stable identifier for
every failed gate. A diagnostic attempt is always observational even if every
mechanical gate passes.

## Representative-block perf

Choose blocks from the baseline-independent frozen manifest:

- `highest-gas`: maximum `gasUsed`, then lowest block number/hash;
- `median-gas`: lower-median entry after sorting by gas, block number, then
  block hash.

For each selected block and variant, run at least two balanced passes of each:

```bash
perf stat \
  -e task-clock,cycles,instructions,branches,branch-misses,cache-misses,context-switches,page-faults \
  -- <fresh strict replay command>

perf record -e cycles -F 997 --call-graph dwarf -o perf.data \
  -- <fresh strict replay command>
```

Use the exact generic perf event aliases frozen in the contract. If the host
cannot resolve one, formal attribution is blocked; do not silently substitute
an event with different semantics. Use `--inherit` or the equivalent when the
replayer launches synchronous child work. Keep `perf stat` and `perf record`
as different fresh executions.

Record the event scope explicitly. `cycles` above samples user and kernel
execution; a user-only event cannot support a kernel share.

The replayer can load the DTVM library through sealed memfd bytes. Before
classification:

1. record the frozen library SHA-256 and ELF Build ID;
2. retain the DSO/mapping and Build ID observed in `perf.data`;
3. require exact Build-ID equality between the sampled DTVM image and frozen
   library;
4. populate an attempt-local symfs or `PERF_BUILDID_DIR`, never an unsealed
   shared cache;
5. preserve symbolized self and inclusive/call-chain reports;
6. fail attribution if any sample known to belong to DTVM remains unresolved.

Produce raw and demangled reports by command, DSO, symbol, and call chain.
Classify every on-CPU sample at the evidence-backed ownership layer:

| Category | Meaning |
|---|---|
| `replayer` | The replay executable, including orchestration, EVMC host, witness/state, and stock Reth paths that share its binary |
| `dtvm` | Exact Build-ID-matched DTVM library, generated code, and attributable runtime helpers |
| `kernel` | Kernel samples charged to the process |
| `other` | Resolved libc, allocator, loader, compression, or another ownership DSO |
| `inherited-child` | Synchronous objdump/linker/shell or other child command |
| `unresolved` | Samples without a defensible command/DSO/symbol classification |

The shares use all process-wide on-CPU samples as denominator. Always report
event, user/kernel scope, inheritance, raw sample count, lost samples, and
unresolved share. The mandatory ownership buckets must sum to the denominator.
They are CPU-sample shares, not wall-time shares.

Write `perf/classification.json` with this exact schema:

```json
{
  "schema": "dtvm.reth-replay-performance-perf-classification.v1",
  "status": "complete",
  "contractCanonicalSha256": "64-lowercase-hex",
  "classifierSha256": "bound perfClassifier executable SHA-256",
  "recordEvent": "cycles",
  "recordEventScope": "user-and-kernel",
  "inheritChildren": true,
  "representativeBlocksCanonicalSha256": "canonical JSON SHA-256",
  "rawInputsSha256": "perf/raw-inputs.json SHA-256",
  "denominatorWeightedCycles": 1000000,
  "lostSamples": 0,
  "shares": {
    "replayer": {"weightedCycles": 500000, "percent": 50.0},
    "dtvm": {"weightedCycles": 200000, "percent": 20.0},
    "kernel": {"weightedCycles": 100000, "percent": 10.0},
    "other": {"weightedCycles": 100000, "percent": 10.0},
    "inherited-child": {"weightedCycles": 50000, "percent": 5.0},
    "unresolved": {"weightedCycles": 50000, "percent": 5.0}
  },
  "dtvmBuildIdMatch": true,
  "attemptLocalSymfs": true,
  "symbolizedSelfAndInclusiveReports": true,
  "unresolvedDtvmSamples": 0
}
```

The six weighted counts must sum exactly to the denominator and percentages
must sum to 100 within 0.0001 percentage point. `rawInputsSha256` binds the
ordered perf-data/report inventory and observed Build IDs.

Do not infer witness/state, stock Reth, compiler, or generated-runtime shares
from DSO self samples when those paths share a binary or unresolved JIT image.
Report those finer logical stages only as secondary analysis supported by
non-overlapping explicit phase timers/markers or defensible inclusive call
chains. State the evidence and denominator for every secondary split. A
wall-time stage share requires explicit stage timers that do not overlap.

## Optional cold compilation

Enable this stage only when compiler cost is relevant. Freeze one code for the
new attempt before its cold-compile measurements:

1. decode every non-empty `witness.codes` entry;
2. choose maximum decoded length;
3. break ties by block number, code index, then raw SHA-256 ascending;
4. record the exact transform required by the compiler subject.

Use this enabled contract fragment:

```json
{
  "enabled": true,
  "runnerSkill": "dtvm-cold-compile-profile",
  "inputSelection": "largest-nonempty-witness-code-deterministic-tiebreak",
  "freshProcess": true,
  "productionTimingSeparated": true,
  "measuredPairs": 20,
  "schedule": ["AB", "BA"],
  "oneShotProfilesPerVariant": 1
}
```

The actual schedule must contain `measuredPairs` entries and be balanced.
Run production-equivalent direct timing interleaved; run one independent
sealed `dtvm-cold-compile-profile` bundle per variant for attribution. A build
with synchronous perf/objdump instrumentation is not production timing.

## Source trace and optimization handoff

When call-chain-supported secondary analysis or a cold profile names a
material compiler symbol, invoke `dtvm-compiler-path-analysis`. Bind the source
trace to the profile bundle and preserve raw/demangled symbol, command, DSO,
route, mechanism, falsifier, invariants, and minimum seam.

Profiling does not authorize `src/**` edits. Enter the DTVM project workflow
before a change. Invoke `dtvm-compile-time-optimize` only when the user
explicitly requests its end-to-end optimization loop.

## Evidence seal

Use one new attempt directory. Refuse reuse. Recommended layout:

```text
attempt/
  comparison-contract.json
  comparison-contract.validation.json
  eligibility.json
  identity/
  correctness/
  environment/
  runtime/
    schedule.json
    quiet/
    samples.jsonl
    rounds.json
    runtime-result.json
    summary.json
  perf/
    block-<number>/<variant>/<pass>/{stat.txt,perf.data,report.txt}
    classification.json
  cold-compile/                 # optional
  source-trace/                 # optional
  scripts/
  report/
  SHA256SUMS
  evidence-seal.json
```

This skill does not bundle the experiment runner, statistics analyzer,
classifier, or sealer. Use existing approved reusable tools or create each
missing tool once, give it deterministic tests, and bind both tool bytes and a
machine-readable test result before timing. The tooling result schema is
`dtvm.reth-replay-performance-tooling-validation.v1`; it must have
`status: passed`, the exact five tool roles and test packages, plus a canonical
tool-set digest. The contract validator checks that continuity but does not
rerun the tool suites.

Each role binds the actual canonical command document, not only a digest:

```json
{
  "schema": "dtvm.reth-replay-performance-tool-command.v1",
  "role": "runtimeRunner",
  "argv": ["/absolute/realpath/test-runner.py", "--fixture", "/absolute/fixture"],
  "cwd": "/absolute/normalized/cwd",
  "environment": {"LC_ALL": "C", "PYTHONDONTWRITEBYTECODE": "1"},
  "expectedOutputs": ["/absolute/realpath/test-runner.log"]
}
```

The file binding's SHA-256 is `commandSha256` below. This is an auditable
self-attestation package, not cryptographic proof of human authorship. The
contract validator verifies byte continuity and the exact schemas; it does not
execute arbitrary bound commands.

Each role's bound `testResult` has this exact schema:

```json
{
  "schema": "dtvm.reth-replay-performance-tool-test.v1",
  "status": "passed",
  "role": "runtimeRunner",
  "toolSha256": "64-lowercase-hex",
  "testHarnessSha256": "64-lowercase-hex",
  "testLogSha256": "64-lowercase-hex",
  "commandSha256": "64-lowercase-hex",
  "testCases": 7,
  "testsPassed": 7,
  "testsFailed": 0,
  "rerunVerified": true
}
```

The role must be one of `semanticValidator`, `runtimeRunner`,
`statisticsAnalyzer`, `perfClassifier`, or `evidenceSealer`. The executable
must be executable; the harness, complete log, and test result are immutable
regular files. The command digest records the canonical command that produced
the log/result. `status: passed` requires at least one case, every case passed,
zero failures, and a successful clean rerun. The consolidated result uses this
exact entry shape for each of those five keys:

```json
{
  "schema": "dtvm.reth-replay-performance-tooling-validation.v1",
  "status": "passed",
  "toolSetCanonicalSha256": "canonical SHA-256 of the tools object",
  "tools": {
    "runtimeRunner": {
      "status": "passed",
      "sha256": "executable SHA-256",
      "testHarnessSha256": "64-lowercase-hex",
      "testLogSha256": "64-lowercase-hex",
      "testResultSha256": "64-lowercase-hex",
      "commandSha256": "64-lowercase-hex",
      "testCases": 7,
      "testsPassed": 7,
      "testsFailed": 0,
      "rerunVerified": true
    }
  }
}
```

The abbreviated `tools` object above must contain exactly all five role keys,
each with exactly the displayed entry fields. The semantic validator entry
must equal the generator metadata in both proof documents; for that role, the
single fail-closed invocation runs its deterministic cases and produces the
test log/result plus the two proof documents.

The sealer materializes the otherwise ambiguous source/build/corpus identity as
`identity/source-build-corpus.json`:

```json
{
  "schema": "dtvm.reth-replay-performance-source-build-corpus.v1",
  "corpusManifestSha256": "64-lowercase-hex",
  "chainConfigSha256": "64-lowercase-hex",
  "approvedReplayerManifestSha256": "64-lowercase-hex",
  "approvedReplayerBinarySha256": "64-lowercase-hex",
  "baseline": {
    "commit": "40-lowercase-hex",
    "tree": "40-lowercase-hex",
    "librarySha256": "64-lowercase-hex",
    "cmakeCacheSha256": "64-lowercase-hex",
    "strictSealSha256": "64-lowercase-hex"
  },
  "candidate": {
    "commit": "40-lowercase-hex",
    "tree": "40-lowercase-hex",
    "librarySha256": "64-lowercase-hex",
    "cmakeCacheSha256": "64-lowercase-hex",
    "strictSealSha256": "64-lowercase-hex"
  }
}
```

Wrap the two required `dtvm-write-report` lint invocations in
`report/lint.json`; copy the exact linter to `report/lint_report.py`:

```json
{
  "schema": "dtvm.reth-replay-performance-report-lint.v1",
  "status": "passed",
  "linterSha256": "report/lint_report.py SHA-256",
  "artifactSha256": "report/artifact.json SHA-256",
  "htmlSha256": "report/report.html SHA-256",
  "artifactCommandSha256": "report/artifact-lint.command.json SHA-256",
  "htmlCommandSha256": "report/html-lint.command.json SHA-256",
  "artifactLogSha256": "report/artifact-lint.log SHA-256",
  "htmlLogSha256": "report/html-lint.log SHA-256",
  "errors": 0,
  "warnings": 0
}
```

Copy or bind every runner/analysis script with realpath and SHA-256. Generate
`SHA256SUMS` in bytewise sorted relative-path order, excluding the checksum
file and seal while they are being created. The seal binds the contract
digest, checksum-manifest digest, eligibility result, source/build/corpus
identities, and report lint outputs. It records no secret values.

`evidence-seal.json` has this exact schema:

```json
{
  "schema": "dtvm.reth-replay-performance-evidence-seal.v1",
  "status": "sealed",
  "attemptId": "fixed16-formal-r20",
  "contractCanonicalSha256": "64-lowercase-hex",
  "contractValidationSha256": "64-lowercase-hex",
  "runtimeResultSha256": "64-lowercase-hex",
  "eligibilitySha256": "64-lowercase-hex",
  "hostStabilitySha256": "64-lowercase-hex",
  "perfClassificationSha256": "64-lowercase-hex",
  "reportLintSha256": "64-lowercase-hex",
  "sourceBuildCorpusSha256": "64-lowercase-hex",
  "toolingValidationSha256": "64-lowercase-hex",
  "checksumManifestSha256": "64-lowercase-hex",
  "evidenceSealerSha256": "64-lowercase-hex",
  "networkUsed": false,
  "credentialsRecorded": false,
  "rerunVerified": true,
  "finalConclusionEligible": true
}
```

`status: sealed` is permitted only when every referenced digest matches, the
checksum manifest covers every evidence byte except itself and the seal, no
unlisted regular file exists, report lint passed, and read-only seal
verification succeeds without mutation. `finalConclusionEligible` is true
only when the attempt is formal, `eligibility.status` is `passed`, and this
seal is valid. For an observational attempt it is false even though the
evidence can still be sealed.

Re-running seal verification must not rewrite evidence. Any changed byte
invalidates the attempt; create a new attempt instead of repairing a reported
result in place.

Store the validated contract and its canonical digest inside the new attempt
before its warmups or measurements. `contractFrozenBeforeAttemptTiming` refers
only to that attempt; prior experiments do not invalidate it. The bound runtime
runner must refuse to start without that `status: valid` validation artifact
and must copy the canonical contract digest into every warmup and measured
sample. The sealer verifies one digest across the contract, validation result,
schedule, and all samples.

After sealing, run the bundled read-only continuity validator:

```bash
python3 "$SKILL_ROOT/scripts/validate_replay_perf_results.py" \
  "$ATTEMPT_DIR"
```

It requires the exact runtime, host, eligibility, classification, report-lint,
source/build/corpus, checksum, and seal schemas above; recomputes bound file
hashes and checksum coverage; and fails if a formal conclusion outruns its
gates. It does not rerun the experiment or establish authorship.

## Reporting contract

Invoke `dtvm-write-report`. The report should answer:

1. what end-to-end full-window runtime changed, with baseline, candidate,
   absolute/relative delta, unit, workload, and full-window pair count;
2. whether the effect is conclusion-eligible;
3. how process-wide on-CPU samples divide among replayer, DTVM, kernel, other,
   inherited children, and unresolved, plus any separately evidenced logical
   stage split;
4. which hotspots moved and why;
5. what the optional cold diagnostic says without conflating it with replay;
6. the next discriminating optimization or measurement.

Use paired/interleaved baseline–candidate benchmark terminology. Attach
limitations to the affected claim. Keep hashes, commands, complete correctness
matrix, and raw perf tables in provenance/supporting artifacts.
