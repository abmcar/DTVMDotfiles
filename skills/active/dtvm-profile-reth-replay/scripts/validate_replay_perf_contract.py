#!/usr/bin/env python3
"""Validate bindings and frozen result schemas for a replay performance contract.

This tool does not independently re-run semantic correctness, identity, source
relation, benchmark, statistics, classification, or sealing tools.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


SCHEMA = "dtvm.reth-replay-performance-contract.v1"
REPORT_SCHEMA = "dtvm.reth-replay-performance-contract-validation.v1"
SEMANTIC_SCHEMA = "dtvm.reth-replay-performance-semantic-validation.v1"
TOOLING_SCHEMA = "dtvm.reth-replay-performance-tooling-validation.v1"
TOOL_TEST_SCHEMA = "dtvm.reth-replay-performance-tool-test.v1"
TOOL_COMMAND_SCHEMA = "dtvm.reth-replay-performance-tool-command.v1"
IDENTITY_PROOF_SCHEMA = "dtvm.reth-replay-performance-identity-proof.v1"
SOURCE_PROOF_SCHEMA = "dtvm.reth-replay-performance-source-relation-proof.v1"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_RE = re.compile(r"^[0-9a-f]{40}$")
BLOCK_HASH_RE = re.compile(r"^0x[0-9a-f]{64}$")
ATTEMPT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
EXPECTED_STAT_EVENTS = {
    "task-clock",
    "cycles",
    "instructions",
    "branches",
    "branch-misses",
    "cache-misses",
    "context-switches",
    "page-faults",
}
EXPECTED_CLASSES = {
    "replayer",
    "dtvm",
    "kernel",
    "other",
    "inherited-child",
    "unresolved",
}


class DuplicateKeyError(ValueError):
    pass


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


class ContractValidator:
    def __init__(self, contract: Any, contract_path: Path) -> None:
        self.contract = contract
        self.contract_path = contract_path
        self.errors: list[str] = []
        self.verified_files: list[dict[str, str]] = []
        self.semantic_validation_status: str | None = None
        self.tooling_validation_status: str | None = None
        self.proof_generators: list[tuple[str, dict[str, Any]]] = []

    def error(self, path: str, detail: str) -> None:
        self.errors.append(f"{path}: {detail}")

    def obj(
        self, value: Any, path: str, expected_keys: set[str]
    ) -> dict[str, Any] | None:
        if not isinstance(value, dict):
            self.error(path, "object required")
            return None
        actual = set(value)
        for key in sorted(expected_keys - actual):
            self.error(path, f"missing key {key!r}")
        for key in sorted(actual - expected_keys):
            self.error(path, f"unknown key {key!r}")
        return value

    def true(self, value: Any, path: str) -> None:
        if value is not True:
            self.error(path, "must be true")

    def false(self, value: Any, path: str) -> None:
        if value is not False:
            self.error(path, "must be false")

    def integer(self, value: Any, path: str, minimum: int = 0) -> int | None:
        if isinstance(value, bool) or not isinstance(value, int):
            self.error(path, "integer required")
            return None
        if value < minimum:
            self.error(path, f"must be at least {minimum}")
        return value

    def number(
        self, value: Any, path: str, minimum: float, maximum: float | None = None
    ) -> float | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            self.error(path, "number required")
            return None
        result = float(value)
        if result < minimum:
            self.error(path, f"must be at least {minimum}")
        if maximum is not None and result > maximum:
            self.error(path, f"must be at most {maximum}")
        return result

    def exact(self, value: Any, path: str, expected: Any) -> None:
        if value != expected:
            self.error(path, f"must equal {expected!r}")

    def nonempty(self, value: Any, path: str) -> None:
        if not isinstance(value, str) or not value.strip():
            self.error(path, "non-empty string required")

    def file_binding(self, value: Any, path: str) -> dict[str, Any] | None:
        binding = self.obj(value, path, {"path", "sha256"})
        if binding is None:
            return None
        raw_path = binding.get("path")
        expected = binding.get("sha256")
        if not isinstance(raw_path, str) or not raw_path:
            self.error(f"{path}.path", "non-empty absolute path required")
            return binding
        candidate = Path(raw_path)
        if not candidate.is_absolute():
            self.error(f"{path}.path", "absolute path required")
            return binding
        normalized = Path(os.path.abspath(candidate))
        try:
            resolved = candidate.resolve(strict=True)
        except OSError as exc:
            self.error(f"{path}.path", f"cannot resolve regular file: {exc}")
            return binding
        if candidate != normalized or candidate != resolved:
            self.error(
                f"{path}.path",
                "canonical realpath required; symlinked and normalized "
                "aliases are forbidden",
            )
        if not candidate.is_file():
            self.error(f"{path}.path", "regular file required")
            return binding
        if not isinstance(expected, str) or not SHA256_RE.fullmatch(expected):
            self.error(f"{path}.sha256", "64 lowercase hexadecimal bytes required")
            return binding
        actual = sha256_file(candidate)
        if actual != expected:
            self.error(
                f"{path}.sha256", f"content mismatch: expected {expected}, got {actual}"
            )
            return binding
        self.verified_files.append(
            {"role": path, "path": str(candidate), "sha256": actual}
        )
        return binding

    def tool_binding(self, value: Any, path: str) -> dict[str, Any] | None:
        binding = self.file_binding(value, path)
        if binding is None:
            return None
        raw_path = binding.get("path")
        if isinstance(raw_path, str) and Path(raw_path).is_file():
            if not os.access(raw_path, os.X_OK):
                self.error(f"{path}.path", "executable tool required")
        return binding

    def load_bound_json(
        self, binding: Any, path: str
    ) -> dict[str, Any] | None:
        if not isinstance(binding, dict):
            return None
        raw_path = binding.get("path")
        if not isinstance(raw_path, str):
            return None
        try:
            with Path(raw_path).open(encoding="utf-8") as stream:
                value = json.load(stream, object_pairs_hook=unique_object)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            self.error(path, f"machine-readable JSON required: {exc}")
            return None
        if not isinstance(value, dict):
            self.error(path, "JSON object required")
            return None
        return value

    def validate_window(self, root: dict[str, Any]) -> tuple[int | None, int | None]:
        window = self.obj(
            root.get("window"),
            "window",
            {"chainId", "startBlock", "endBlock", "blockCount"},
        )
        if window is None:
            return None, None
        self.exact(window.get("chainId"), "window.chainId", "0x1")
        start = self.integer(window.get("startBlock"), "window.startBlock", 0)
        end = self.integer(window.get("endBlock"), "window.endBlock", 0)
        count = self.integer(window.get("blockCount"), "window.blockCount", 2)
        if start is not None and end is not None and end < start:
            self.error("window", "endBlock must not precede startBlock")
        if (
            start is not None
            and end is not None
            and count is not None
            and count != end - start + 1
        ):
            self.error(
                "window.blockCount", "must equal endBlock - startBlock + 1"
            )
        return start, end

    def validate_workload(self, root: dict[str, Any]) -> dict[str, Any] | None:
        workload = self.obj(
            root.get("workload"),
            "workload",
            {
                "transactionCount",
                "totalGasUsed",
                "rawBlockBytes",
                "bytecodeCount",
                "forkBoundary",
            },
        )
        if workload is None:
            return None
        for key in (
            "transactionCount",
            "totalGasUsed",
            "rawBlockBytes",
            "bytecodeCount",
        ):
            self.integer(workload.get(key), f"workload.{key}", 0)
        boundary = self.obj(
            workload.get("forkBoundary"),
            "workload.forkBoundary",
            {"crossesKnownBoundary", "description"},
        )
        if boundary is not None:
            if not isinstance(boundary.get("crossesKnownBoundary"), bool):
                self.error(
                    "workload.forkBoundary.crossesKnownBoundary",
                    "boolean required",
                )
            self.nonempty(
                boundary.get("description"),
                "workload.forkBoundary.description",
            )
        return workload

    def validate_evidence(self, root: dict[str, Any]) -> dict[str, Any] | None:
        keys = {
            "corpusManifest",
            "approvedReplayerManifest",
            "approvedReplayerBinary",
            "baselineSeal",
            "candidateSeal",
            "correctnessSummary",
            "chainConfig",
            "identityProof",
            "sourceRelationProof",
            "semanticValidator",
            "semanticValidation",
        }
        evidence = self.obj(root.get("evidence"), "evidence", keys)
        if evidence is None:
            return None
        for key in sorted(keys - {"semanticValidator"}):
            self.file_binding(evidence.get(key), f"evidence.{key}")
        self.tool_binding(
            evidence.get("semanticValidator"), "evidence.semanticValidator"
        )
        return evidence

    def validate_variant(self, value: Any, path: str) -> dict[str, Any] | None:
        variant = self.obj(
            value, path, {"label", "commit", "tree", "library", "cmakeCache"}
        )
        if variant is None:
            return None
        self.nonempty(variant.get("label"), f"{path}.label")
        for key in ("commit", "tree"):
            git_id = variant.get(key)
            if not isinstance(git_id, str) or not GIT_RE.fullmatch(git_id):
                self.error(f"{path}.{key}", "40 lowercase hexadecimal bytes required")
        self.file_binding(variant.get("library"), f"{path}.library")
        self.file_binding(variant.get("cmakeCache"), f"{path}.cmakeCache")
        return variant

    def validate_variants(
        self, root: dict[str, Any]
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        variants = self.obj(
            root.get("variants"), "variants", {"baseline", "candidate"}
        )
        if variants is None:
            return None, None
        baseline = self.validate_variant(variants.get("baseline"), "variants.baseline")
        candidate = self.validate_variant(
            variants.get("candidate"), "variants.candidate"
        )
        if baseline is None or candidate is None:
            return baseline, candidate
        for key in ("label", "commit", "tree"):
            if baseline.get(key) == candidate.get(key):
                self.error(f"variants.{key}", "baseline and candidate must differ")
        baseline_library = baseline.get("library")
        candidate_library = candidate.get("library")
        if (
            isinstance(baseline_library, dict)
            and isinstance(candidate_library, dict)
            and baseline_library.get("sha256") == candidate_library.get("sha256")
        ):
            self.error(
                "variants.library",
                "baseline and candidate library SHA-256 must differ",
            )
        return baseline, candidate

    def validate_generator(
        self, value: Any, path: str, expected_sha256: Any
    ) -> None:
        generator = self.obj(
            value,
            path,
            {
                "sha256",
                "commandSha256",
                "testHarnessSha256",
                "testLogSha256",
                "testCases",
                "rerunVerified",
            },
        )
        if generator is None:
            return
        self.exact(generator.get("sha256"), f"{path}.sha256", expected_sha256)
        for key in ("commandSha256", "testHarnessSha256", "testLogSha256"):
            value = generator.get(key)
            if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
                self.error(f"{path}.{key}", "64 lowercase hexadecimal bytes required")
        self.integer(generator.get("testCases"), f"{path}.testCases", 1)
        self.true(generator.get("rerunVerified"), f"{path}.rerunVerified")

    def validate_proof_documents(
        self,
        evidence: dict[str, Any] | None,
        baseline: dict[str, Any] | None,
        candidate: dict[str, Any] | None,
        comparison: dict[str, Any] | None,
    ) -> None:
        if (
            evidence is None
            or baseline is None
            or candidate is None
            or comparison is None
        ):
            return

        def digest(binding: Any) -> Any:
            return binding.get("sha256") if isinstance(binding, dict) else None

        generator_sha = digest(evidence.get("semanticValidator"))
        identity_inputs = {
            "approvedReplayerManifestSha256": digest(
                evidence.get("approvedReplayerManifest")
            ),
            "approvedReplayerBinarySha256": digest(
                evidence.get("approvedReplayerBinary")
            ),
            "baselineLibrarySha256": digest(baseline.get("library")),
            "candidateLibrarySha256": digest(candidate.get("library")),
            "baselineCmakeCacheSha256": digest(baseline.get("cmakeCache")),
            "candidateCmakeCacheSha256": digest(candidate.get("cmakeCache")),
            "baselineCommit": baseline.get("commit"),
            "baselineTree": baseline.get("tree"),
            "candidateCommit": candidate.get("commit"),
            "candidateTree": candidate.get("tree"),
        }
        identity = self.load_bound_json(
            evidence.get("identityProof"), "evidence.identityProof"
        )
        if identity is not None:
            identity = self.obj(
                identity,
                "identityProof",
                {
                    "schema",
                    "status",
                    "generator",
                    "inputs",
                    "normalized",
                    "allowedDifferences",
                },
            )
        if identity is not None:
            self.exact(
                identity.get("schema"),
                "identityProof.schema",
                IDENTITY_PROOF_SCHEMA,
            )
            self.exact(identity.get("status"), "identityProof.status", "passed")
            self.validate_generator(
                identity.get("generator"),
                "identityProof.generator",
                generator_sha,
            )
            if isinstance(identity.get("generator"), dict):
                self.proof_generators.append(
                    ("identityProof.generator", identity["generator"])
                )
            self.exact(
                identity.get("inputs"), "identityProof.inputs", identity_inputs
            )
            normalized = self.obj(
                identity.get("normalized"),
                "identityProof.normalized",
                {
                    "commandCanonicalSha256",
                    "buildConfigCanonicalSha256",
                    "environmentCanonicalSha256",
                },
            )
            if normalized is not None:
                for key, value in normalized.items():
                    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
                        self.error(
                            f"identityProof.normalized.{key}",
                            "64 lowercase hexadecimal bytes required",
                        )
            self.exact(
                identity.get("allowedDifferences"),
                "identityProof.allowedDifferences",
                comparison.get("allowedDifferences"),
            )

        source_inputs = {
            "baselineCommit": baseline.get("commit"),
            "baselineTree": baseline.get("tree"),
            "candidateCommit": candidate.get("commit"),
            "candidateTree": candidate.get("tree"),
        }
        source = self.load_bound_json(
            evidence.get("sourceRelationProof"),
            "evidence.sourceRelationProof",
        )
        if source is not None:
            source = self.obj(
                source,
                "sourceRelationProof",
                {
                    "schema",
                    "status",
                    "generator",
                    "relationship",
                    "inputs",
                    "commonBaseCommit",
                    "sharedChangeSetSha256",
                    "candidateOnlyChangeSha256",
                    "effectiveDiffSha256",
                },
            )
        if source is not None:
            self.exact(
                source.get("schema"),
                "sourceRelationProof.schema",
                SOURCE_PROOF_SCHEMA,
            )
            self.exact(source.get("status"), "sourceRelationProof.status", "passed")
            self.validate_generator(
                source.get("generator"),
                "sourceRelationProof.generator",
                generator_sha,
            )
            if isinstance(source.get("generator"), dict):
                self.proof_generators.append(
                    ("sourceRelationProof.generator", source["generator"])
                )
            self.exact(
                source.get("relationship"),
                "sourceRelationProof.relationship",
                comparison.get("sourceRelationship"),
            )
            self.exact(
                source.get("inputs"), "sourceRelationProof.inputs", source_inputs
            )
            common_base = source.get("commonBaseCommit")
            if not isinstance(common_base, str) or not GIT_RE.fullmatch(common_base):
                self.error(
                    "sourceRelationProof.commonBaseCommit",
                    "40 lowercase hexadecimal bytes required",
                )
            for key in (
                "sharedChangeSetSha256",
                "candidateOnlyChangeSha256",
                "effectiveDiffSha256",
            ):
                value = source.get(key)
                if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
                    self.error(
                        f"sourceRelationProof.{key}",
                        "64 lowercase hexadecimal bytes required",
                    )

    def validate_comparison(
        self, root: dict[str, Any]
    ) -> dict[str, Any] | None:
        comparison = self.obj(
            root.get("comparison"),
            "comparison",
            {
                "sameCorpusRequired",
                "sameApprovedReplayerRequired",
                "sameCommandAfterRootNormalizationRequired",
                "sameBuildConfigAfterRootNormalizationRequired",
                "sourceRelationship",
                "sourceRelationshipValidationRequired",
                "contractFrozenBeforeAttemptTiming",
                "allowedDifferences",
            },
        )
        if comparison is None:
            return None
        for key in (
            "sameCorpusRequired",
            "sameApprovedReplayerRequired",
            "sameCommandAfterRootNormalizationRequired",
            "sameBuildConfigAfterRootNormalizationRequired",
            "sourceRelationshipValidationRequired",
            "contractFrozenBeforeAttemptTiming",
        ):
            self.true(comparison.get(key), f"comparison.{key}")
        if comparison.get("sourceRelationship") not in {
            "candidate-descends-from-baseline",
            "common-base-with-exact-change-set",
        }:
            self.error(
                "comparison.sourceRelationship",
                "must be candidate-descends-from-baseline or "
                "common-base-with-exact-change-set",
            )
        self.exact(
            comparison.get("allowedDifferences"),
            "comparison.allowedDifferences",
            ["sourceCommit", "sourceTree", "dtvmLibrary"],
        )
        return comparison

    def validate_correctness_requirements(self, root: dict[str, Any]) -> None:
        correctness = self.obj(
            root.get("correctnessRequirements"),
            "correctnessRequirements",
            {
                "requireStrictReplayBothVariants",
                "requireAllDifferentialMatches",
                "requireAllPreStateRootsVerified",
                "requireAllPostStateRootsVerified",
                "requireOfflineNetworkDenial",
                "requireNoRecordedCredentials",
            },
        )
        if correctness is None:
            return
        for key in (
            "requireStrictReplayBothVariants",
            "requireAllDifferentialMatches",
            "requireAllPreStateRootsVerified",
            "requireAllPostStateRootsVerified",
            "requireOfflineNetworkDenial",
            "requireNoRecordedCredentials",
        ):
            self.true(
                correctness.get(key), f"correctnessRequirements.{key}"
            )

    def validate_isolation(self, root: dict[str, Any]) -> None:
        isolation = self.obj(
            root.get("isolation"),
            "isolation",
            {
                "networkDisabled",
                "proxyDisabled",
                "downloadsDisabled",
                "rethStopped",
                "formalStagesSerialized",
            },
        )
        if isolation is None:
            return
        for key in isolation:
            self.true(isolation.get(key), f"isolation.{key}")

    def balanced_schedule(
        self, value: Any, path: str, expected_length: int | None
    ) -> None:
        if not isinstance(value, list):
            self.error(path, "list required")
            return
        if expected_length is not None and len(value) != expected_length:
            self.error(path, f"must contain exactly {expected_length} entries")
        invalid = sorted({item for item in value if item not in {"AB", "BA"}})
        if invalid:
            self.error(path, f"only AB and BA are allowed: {invalid!r}")
            return
        if abs(value.count("AB") - value.count("BA")) > 1:
            self.error(path, "AB and BA counts may differ by at most one")

    def alternating_schedule(
        self, value: Any, path: str, expected_length: int | None
    ) -> None:
        self.balanced_schedule(value, path, expected_length)
        if not isinstance(value, list) or not value:
            return
        expected = ["AB" if index % 2 == 0 else "BA" for index in range(len(value))]
        if value != expected:
            self.error(path, "must alternate AB, BA from the first round")

    def validate_runtime(self, root: dict[str, Any], purpose: Any) -> None:
        runtime = self.obj(
            root.get("runtime"),
            "runtime",
            {
                "design",
                "measurementUnit",
                "processGranularity",
                "warmupRounds",
                "warmupSchedule",
                "measuredRounds",
                "schedule",
                "cpu",
                "networkDisabled",
                "dropKernelCaches",
                "stopOnCorrectnessFailure",
                "retainRawSamples",
                "primaryStatistic",
                "confidence",
                "minimumPracticalEffectPercent",
                "maxRoundCvPercent",
            },
        )
        if runtime is None:
            return
        self.exact(
            runtime.get("design"),
            "runtime.design",
            "balanced-adjacent-paired-fresh-process",
        )
        self.exact(
            runtime.get("measurementUnit"),
            "runtime.measurementUnit",
            "full-window-round",
        )
        self.exact(
            runtime.get("processGranularity"),
            "runtime.processGranularity",
            "one-block",
        )
        self.exact(runtime.get("warmupRounds"), "runtime.warmupRounds", 2)
        self.exact(
            runtime.get("warmupSchedule"),
            "runtime.warmupSchedule",
            ["AB", "BA"],
        )
        minimum_rounds = 20 if purpose == "formal" else 7
        rounds = self.integer(
            runtime.get("measuredRounds"),
            "runtime.measuredRounds",
            minimum_rounds,
        )
        self.alternating_schedule(
            runtime.get("schedule"), "runtime.schedule", rounds
        )
        self.true(runtime.get("networkDisabled"), "runtime.networkDisabled")
        self.false(runtime.get("dropKernelCaches"), "runtime.dropKernelCaches")
        self.true(
            runtime.get("stopOnCorrectnessFailure"),
            "runtime.stopOnCorrectnessFailure",
        )
        self.true(runtime.get("retainRawSamples"), "runtime.retainRawSamples")
        self.exact(
            runtime.get("primaryStatistic"),
            "runtime.primaryStatistic",
            "median-paired-full-window-relative-delta",
        )

        cpu = self.obj(
            runtime.get("cpu"),
            "runtime.cpu",
            {
                "logicalCpu",
                "smtSiblingPolicy",
                "maxBusyPercent",
                "sampleWindowSeconds",
                "consecutiveQuietWindows",
                "quietBeforeEachBlockPair",
                "quietAfterRun",
            },
        )
        if cpu is not None:
            self.integer(cpu.get("logicalCpu"), "runtime.cpu.logicalCpu", 0)
            self.exact(
                cpu.get("smtSiblingPolicy"),
                "runtime.cpu.smtSiblingPolicy",
                "idle-or-offline",
            )
            self.number(
                cpu.get("maxBusyPercent"),
                "runtime.cpu.maxBusyPercent",
                0.0,
                5.0,
            )
            self.number(
                cpu.get("sampleWindowSeconds"),
                "runtime.cpu.sampleWindowSeconds",
                2.0,
            )
            self.integer(
                cpu.get("consecutiveQuietWindows"),
                "runtime.cpu.consecutiveQuietWindows",
                2,
            )
            self.true(
                cpu.get("quietBeforeEachBlockPair"),
                "runtime.cpu.quietBeforeEachBlockPair",
            )
            self.true(cpu.get("quietAfterRun"), "runtime.cpu.quietAfterRun")

        confidence = self.obj(
            runtime.get("confidence"),
            "runtime.confidence",
            {"method", "level", "seed", "resamples"},
        )
        if confidence is not None:
            self.exact(
                confidence.get("method"),
                "runtime.confidence.method",
                "paired-bootstrap",
            )
            self.exact(confidence.get("level"), "runtime.confidence.level", 0.95)
            self.integer(confidence.get("seed"), "runtime.confidence.seed", 0)
            self.integer(
                confidence.get("resamples"),
                "runtime.confidence.resamples",
                10000,
            )
        self.exact(
            runtime.get("minimumPracticalEffectPercent"),
            "runtime.minimumPracticalEffectPercent",
            0.5,
        )
        self.number(
            runtime.get("maxRoundCvPercent"),
            "runtime.maxRoundCvPercent",
            0.1,
            5.0,
        )

    def validate_profiling(
        self,
        root: dict[str, Any],
        start: int | None,
        end: int | None,
        evidence: dict[str, Any] | None,
    ) -> None:
        profiling = self.obj(
            root.get("profiling"),
            "profiling",
            {
                "enabled",
                "selectionFrozenBeforeAttemptProfiling",
                "representativeBlocks",
                "statEvents",
                "recordEvent",
                "recordEventScope",
                "frequencyHz",
                "callGraph",
                "processWide",
                "inheritChildren",
                "freshProcess",
                "passesPerVariantPerBlock",
                "balancedOrder",
                "recordRunsExcludedFromRuntime",
                "memfdSymbolizationRequired",
                "dtvmBuildIdMatchRequired",
                "attemptLocalSymfsRequired",
                "symbolizedSelfAndInclusiveReportsRequired",
                "unresolvedDtvmAllowed",
                "classifications",
            },
        )
        if profiling is None:
            return
        for key in (
            "enabled",
            "selectionFrozenBeforeAttemptProfiling",
            "processWide",
            "inheritChildren",
            "freshProcess",
            "balancedOrder",
            "recordRunsExcludedFromRuntime",
            "memfdSymbolizationRequired",
            "dtvmBuildIdMatchRequired",
            "attemptLocalSymfsRequired",
            "symbolizedSelfAndInclusiveReportsRequired",
        ):
            self.true(profiling.get(key), f"profiling.{key}")
        self.false(
            profiling.get("unresolvedDtvmAllowed"),
            "profiling.unresolvedDtvmAllowed",
        )
        blocks = profiling.get("representativeBlocks")
        if not isinstance(blocks, list) or len(blocks) != 2:
            self.error(
                "profiling.representativeBlocks",
                "exactly highest-gas and median-gas entries are required",
            )
        else:
            roles: list[Any] = []
            numbers: list[int] = []
            for index, item in enumerate(blocks):
                path = f"profiling.representativeBlocks[{index}]"
                block = self.obj(item, path, {"role", "blockNumber", "blockHash"})
                if block is None:
                    continue
                role = block.get("role")
                roles.append(role)
                block_hash = block.get("blockHash")
                if (
                    not isinstance(block_hash, str)
                    or not BLOCK_HASH_RE.fullmatch(block_hash)
                ):
                    self.error(
                        f"{path}.blockHash",
                        "0x-prefixed 32-byte lowercase hash required",
                    )
                number = self.integer(
                    block.get("blockNumber"), f"{path}.blockNumber", 0
                )
                if number is not None:
                    numbers.append(number)
                    if start is not None and number < start:
                        self.error(f"{path}.blockNumber", "precedes frozen window")
                    if end is not None and number > end:
                        self.error(f"{path}.blockNumber", "follows frozen window")
            if sorted(roles) != ["highest-gas", "median-gas"]:
                self.error(
                    "profiling.representativeBlocks",
                    "roles must be highest-gas and median-gas",
                )
            if len(numbers) == 2 and numbers[0] == numbers[1]:
                self.error(
                    "profiling.representativeBlocks",
                    "the two roles must select different blocks",
                )
            self.validate_profile_selection(blocks, evidence)
        events = profiling.get("statEvents")
        if not isinstance(events, list) or any(
            not isinstance(event, str) for event in events
        ):
            self.error("profiling.statEvents", "string list required")
        elif len(events) != len(set(events)):
            self.error("profiling.statEvents", "duplicate events are forbidden")
        else:
            missing = sorted(EXPECTED_STAT_EVENTS - set(events))
            if missing:
                self.error(
                    "profiling.statEvents", f"missing required events: {missing!r}"
                )
        self.exact(profiling.get("recordEvent"), "profiling.recordEvent", "cycles")
        self.exact(
            profiling.get("recordEventScope"),
            "profiling.recordEventScope",
            "user-and-kernel",
        )
        self.integer(profiling.get("frequencyHz"), "profiling.frequencyHz", 99)
        self.exact(profiling.get("callGraph"), "profiling.callGraph", "dwarf")
        self.integer(
            profiling.get("passesPerVariantPerBlock"),
            "profiling.passesPerVariantPerBlock",
            2,
        )
        classes = profiling.get("classifications")
        if not isinstance(classes, list) or any(
            not isinstance(item, str) for item in classes
        ):
            self.error("profiling.classifications", "string list required")
        elif len(classes) != len(set(classes)):
            self.error("profiling.classifications", "duplicates are forbidden")
        elif set(classes) != EXPECTED_CLASSES:
            self.error(
                "profiling.classifications",
                f"must equal {sorted(EXPECTED_CLASSES)!r}",
            )

    def validate_profile_selection(
        self, selected: list[Any], evidence: dict[str, Any] | None
    ) -> None:
        if evidence is None:
            return
        binding = evidence.get("corpusManifest")
        if not isinstance(binding, dict):
            return
        raw_path = binding.get("path")
        if not isinstance(raw_path, str):
            return
        try:
            with Path(raw_path).open(encoding="utf-8") as stream:
                manifest = json.load(stream, object_pairs_hook=unique_object)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            self.error(
                "evidence.corpusManifest",
                f"cannot inspect representative-block inputs: {exc}",
            )
            return
        raw_blocks = manifest.get("blocks") if isinstance(manifest, dict) else None
        if not isinstance(raw_blocks, list) or len(raw_blocks) < 2:
            self.error(
                "evidence.corpusManifest.blocks",
                "at least two manifest block entries are required",
            )
            return
        blocks: list[tuple[int, int, str]] = []
        for index, item in enumerate(raw_blocks):
            if not isinstance(item, dict):
                self.error(
                    f"evidence.corpusManifest.blocks[{index}]", "object required"
                )
                return
            number = item.get("number")
            gas = item.get("gasUsed")
            block_hash = item.get("hash")
            if (
                isinstance(number, bool)
                or not isinstance(number, int)
                or isinstance(gas, bool)
                or not isinstance(gas, int)
                or gas < 0
                or not isinstance(block_hash, str)
                or not BLOCK_HASH_RE.fullmatch(block_hash)
            ):
                self.error(
                    f"evidence.corpusManifest.blocks[{index}]",
                    "valid number, gasUsed, and lowercase block hash required",
                )
                return
            blocks.append((number, gas, block_hash))
        highest = sorted(blocks, key=lambda item: (-item[1], item[0], item[2]))[0]
        ordered = sorted(blocks, key=lambda item: (item[1], item[0], item[2]))
        median = ordered[(len(ordered) - 1) // 2]
        expected = {
            "highest-gas": (highest[0], highest[2]),
            "median-gas": (median[0], median[2]),
        }
        for index, item in enumerate(selected):
            if not isinstance(item, dict):
                continue
            role = item.get("role")
            if role not in expected:
                continue
            actual = (item.get("blockNumber"), item.get("blockHash"))
            if actual != expected[role]:
                self.error(
                    f"profiling.representativeBlocks[{index}]",
                    f"{role} must bind manifest block {expected[role]!r}",
                )

    def validate_semantic_result(
        self,
        evidence: dict[str, Any] | None,
        baseline: dict[str, Any] | None,
        candidate: dict[str, Any] | None,
        comparison: dict[str, Any] | None,
        workload: dict[str, Any] | None,
    ) -> None:
        if (
            evidence is None
            or baseline is None
            or candidate is None
            or comparison is None
            or workload is None
        ):
            return

        def digest(binding: Any) -> Any:
            return binding.get("sha256") if isinstance(binding, dict) else None

        correctness_inputs = {
            "corpusManifestSha256": digest(evidence.get("corpusManifest")),
            "chainConfigSha256": digest(evidence.get("chainConfig")),
            "baselineSealSha256": digest(evidence.get("baselineSeal")),
            "candidateSealSha256": digest(evidence.get("candidateSeal")),
            "correctnessSummarySha256": digest(
                evidence.get("correctnessSummary")
            ),
            "workloadCanonicalSha256": canonical_sha256(workload),
        }
        identity_inputs = {
            "identityProofSha256": digest(evidence.get("identityProof")),
            "approvedReplayerManifestSha256": digest(
                evidence.get("approvedReplayerManifest")
            ),
            "approvedReplayerBinarySha256": digest(
                evidence.get("approvedReplayerBinary")
            ),
            "baselineLibrarySha256": digest(baseline.get("library")),
            "candidateLibrarySha256": digest(candidate.get("library")),
            "baselineCmakeCacheSha256": digest(baseline.get("cmakeCache")),
            "candidateCmakeCacheSha256": digest(candidate.get("cmakeCache")),
        }
        source_inputs = {
            "sourceRelationProofSha256": digest(
                evidence.get("sourceRelationProof")
            ),
            "baselineCommit": baseline.get("commit"),
            "baselineTree": baseline.get("tree"),
            "candidateCommit": candidate.get("commit"),
            "candidateTree": candidate.get("tree"),
        }
        input_set = {
            "correctness": correctness_inputs,
            "identity": identity_inputs,
            "sourceRelation": source_inputs,
        }
        result = self.load_bound_json(
            evidence.get("semanticValidation"),
            "evidence.semanticValidation",
        )
        if result is None:
            return
        result = self.obj(
            result,
            "semanticValidation",
            {
                "schema",
                "status",
                "validatorSha256",
                "inputSetCanonicalSha256",
                "roles",
            },
        )
        if result is None:
            return
        self.exact(
            result.get("schema"), "semanticValidation.schema", SEMANTIC_SCHEMA
        )
        self.exact(result.get("status"), "semanticValidation.status", "passed")
        self.semantic_validation_status = result.get("status")
        self.exact(
            result.get("validatorSha256"),
            "semanticValidation.validatorSha256",
            digest(evidence.get("semanticValidator")),
        )
        self.exact(
            result.get("inputSetCanonicalSha256"),
            "semanticValidation.inputSetCanonicalSha256",
            canonical_sha256(input_set),
        )
        roles = self.obj(
            result.get("roles"),
            "semanticValidation.roles",
            {"correctness", "identity", "sourceRelation"},
        )
        if roles is None:
            return
        for role, inputs in (
            ("correctness", correctness_inputs),
            ("identity", identity_inputs),
        ):
            value = self.obj(
                roles.get(role),
                f"semanticValidation.roles.{role}",
                {"status", "inputs"},
            )
            if value is not None:
                self.exact(
                    value.get("status"),
                    f"semanticValidation.roles.{role}.status",
                    "passed",
                )
                self.exact(
                    value.get("inputs"),
                    f"semanticValidation.roles.{role}.inputs",
                    inputs,
                )
        source = self.obj(
            roles.get("sourceRelation"),
            "semanticValidation.roles.sourceRelation",
            {"status", "relationship", "inputs"},
        )
        if source is not None:
            self.exact(
                source.get("status"),
                "semanticValidation.roles.sourceRelation.status",
                "passed",
            )
            self.exact(
                source.get("relationship"),
                "semanticValidation.roles.sourceRelation.relationship",
                comparison.get("sourceRelationship"),
            )
            self.exact(
                source.get("inputs"),
                "semanticValidation.roles.sourceRelation.inputs",
                source_inputs,
            )

    def validate_tooling(
        self, root: dict[str, Any], evidence: dict[str, Any] | None
    ) -> None:
        keys = {
            "semanticValidator",
            "runtimeRunner",
            "statisticsAnalyzer",
            "perfClassifier",
            "evidenceSealer",
            "validation",
        }
        tooling = self.obj(root.get("tooling"), "tooling", keys)
        if tooling is None:
            return
        tool_roles = keys - {"validation"}
        expected_tools: dict[str, dict[str, Any]] = {}
        for role in sorted(tool_roles):
            package = self.obj(
                tooling.get(role),
                f"tooling.{role}",
                {
                    "executable",
                    "testCommand",
                    "testHarness",
                    "testLog",
                    "testResult",
                },
            )
            if package is None:
                continue
            executable = self.tool_binding(
                package.get("executable"), f"tooling.{role}.executable"
            )
            harness = self.file_binding(
                package.get("testHarness"), f"tooling.{role}.testHarness"
            )
            command_binding = self.file_binding(
                package.get("testCommand"), f"tooling.{role}.testCommand"
            )
            log = self.file_binding(
                package.get("testLog"), f"tooling.{role}.testLog"
            )
            test_binding = self.file_binding(
                package.get("testResult"), f"tooling.{role}.testResult"
            )
            test_result = self.load_bound_json(
                test_binding, f"tooling.{role}.testResult"
            )
            if test_result is None:
                continue
            command = self.load_bound_json(
                command_binding, f"tooling.{role}.testCommand"
            )
            if command is not None:
                command = self.obj(
                    command,
                    f"tooling.{role}.testCommandDocument",
                    {
                        "schema",
                        "role",
                        "argv",
                        "cwd",
                        "environment",
                        "expectedOutputs",
                    },
                )
            if command is not None:
                self.exact(
                    command.get("schema"),
                    f"tooling.{role}.testCommandDocument.schema",
                    TOOL_COMMAND_SCHEMA,
                )
                self.exact(
                    command.get("role"),
                    f"tooling.{role}.testCommandDocument.role",
                    role,
                )
                argv = command.get("argv")
                if (
                    not isinstance(argv, list)
                    or not argv
                    or any(not isinstance(item, str) or not item for item in argv)
                ):
                    self.error(
                        f"tooling.{role}.testCommandDocument.argv",
                        "non-empty list of non-empty strings required",
                    )
                cwd = command.get("cwd")
                if (
                    not isinstance(cwd, str)
                    or not Path(cwd).is_absolute()
                    or cwd != os.path.abspath(cwd)
                ):
                    self.error(
                        f"tooling.{role}.testCommandDocument.cwd",
                        "normalized absolute path required",
                    )
                environment = command.get("environment")
                if not isinstance(environment, dict) or any(
                    not isinstance(key, str)
                    or not key
                    or not isinstance(value, str)
                    for key, value in (
                        environment.items()
                        if isinstance(environment, dict)
                        else ()
                    )
                ):
                    self.error(
                        f"tooling.{role}.testCommandDocument.environment",
                        "string-to-string object required",
                    )
                outputs = command.get("expectedOutputs")
                if (
                    not isinstance(outputs, list)
                    or not outputs
                    or any(not isinstance(item, str) or not item for item in outputs)
                ):
                    self.error(
                        f"tooling.{role}.testCommandDocument.expectedOutputs",
                        "non-empty list of non-empty strings required",
                    )
            test_result = self.obj(
                test_result,
                f"tooling.{role}.testResultDocument",
                {
                    "schema",
                    "status",
                    "role",
                    "toolSha256",
                    "testHarnessSha256",
                    "testLogSha256",
                    "commandSha256",
                    "testCases",
                    "testsPassed",
                    "testsFailed",
                    "rerunVerified",
                },
            )
            if test_result is None:
                continue
            self.exact(
                test_result.get("schema"),
                f"tooling.{role}.testResultDocument.schema",
                TOOL_TEST_SCHEMA,
            )
            self.exact(
                test_result.get("status"),
                f"tooling.{role}.testResultDocument.status",
                "passed",
            )
            self.exact(
                test_result.get("role"),
                f"tooling.{role}.testResultDocument.role",
                role,
            )

            def digest(binding: Any) -> Any:
                return (
                    binding.get("sha256")
                    if isinstance(binding, dict)
                    else None
                )

            self.exact(
                test_result.get("toolSha256"),
                f"tooling.{role}.testResultDocument.toolSha256",
                digest(executable),
            )
            self.exact(
                test_result.get("testHarnessSha256"),
                f"tooling.{role}.testResultDocument.testHarnessSha256",
                digest(harness),
            )
            self.exact(
                test_result.get("testLogSha256"),
                f"tooling.{role}.testResultDocument.testLogSha256",
                digest(log),
            )
            command_sha = test_result.get("commandSha256")
            if not isinstance(command_sha, str) or not SHA256_RE.fullmatch(
                command_sha
            ):
                self.error(
                    f"tooling.{role}.testResultDocument.commandSha256",
                    "64 lowercase hexadecimal bytes required",
                )
            self.exact(
                command_sha,
                f"tooling.{role}.testResultDocument.commandSha256",
                digest(command_binding),
            )
            cases = self.integer(
                test_result.get("testCases"),
                f"tooling.{role}.testResultDocument.testCases",
                1,
            )
            passed = self.integer(
                test_result.get("testsPassed"),
                f"tooling.{role}.testResultDocument.testsPassed",
                1,
            )
            self.exact(
                test_result.get("testsFailed"),
                f"tooling.{role}.testResultDocument.testsFailed",
                0,
            )
            self.true(
                test_result.get("rerunVerified"),
                f"tooling.{role}.testResultDocument.rerunVerified",
            )
            if cases is not None and passed is not None and cases != passed:
                self.error(
                    f"tooling.{role}.testResultDocument",
                    "testCases must equal testsPassed when testsFailed is zero",
                )
            expected_tools[role] = {
                "status": "passed",
                "sha256": digest(executable),
                "testHarnessSha256": digest(harness),
                "testLogSha256": digest(log),
                "testResultSha256": digest(test_binding),
                "commandSha256": command_sha,
                "testCases": cases,
                "testsPassed": passed,
                "testsFailed": 0,
                "rerunVerified": True,
            }
        semantic_tool = expected_tools.get("semanticValidator")
        if semantic_tool is not None:
            expected_generator = {
                "sha256": semantic_tool["sha256"],
                "commandSha256": semantic_tool["commandSha256"],
                "testHarnessSha256": semantic_tool["testHarnessSha256"],
                "testLogSha256": semantic_tool["testLogSha256"],
                "testCases": semantic_tool["testCases"],
                "rerunVerified": semantic_tool["rerunVerified"],
            }
            for proof_path, generator in self.proof_generators:
                self.exact(generator, proof_path, expected_generator)
        if evidence is not None:
            semantic_package = tooling.get("semanticValidator")
            semantic_executable = (
                semantic_package.get("executable")
                if isinstance(semantic_package, dict)
                else None
            )
            self.exact(
                semantic_executable,
                "tooling.semanticValidator.executable",
                evidence.get("semanticValidator"),
            )
        self.file_binding(tooling.get("validation"), "tooling.validation")
        result = self.load_bound_json(
            tooling.get("validation"), "tooling.validation"
        )
        if result is None:
            return
        result = self.obj(
            result,
            "toolingValidation",
            {"schema", "status", "toolSetCanonicalSha256", "tools"},
        )
        if result is None:
            return
        self.exact(
            result.get("schema"), "toolingValidation.schema", TOOLING_SCHEMA
        )
        self.exact(result.get("status"), "toolingValidation.status", "passed")
        self.tooling_validation_status = result.get("status")
        self.exact(
            result.get("toolSetCanonicalSha256"),
            "toolingValidation.toolSetCanonicalSha256",
            canonical_sha256(expected_tools),
        )
        tools = self.obj(
            result.get("tools"),
            "toolingValidation.tools",
            tool_roles,
        )
        if tools is None:
            return
        for role in sorted(tool_roles):
            value = self.obj(
                tools.get(role),
                f"toolingValidation.tools.{role}",
                {
                    "status",
                    "sha256",
                    "testHarnessSha256",
                    "testLogSha256",
                    "testResultSha256",
                    "commandSha256",
                    "testCases",
                    "testsPassed",
                    "testsFailed",
                    "rerunVerified",
                },
            )
            if value is not None and role in expected_tools:
                self.exact(
                    value,
                    f"toolingValidation.tools.{role}",
                    expected_tools[role],
                )

    def validate_cold_compile(self, root: dict[str, Any]) -> None:
        value = root.get("coldCompile")
        if not isinstance(value, dict):
            self.error("coldCompile", "object required")
            return
        enabled = value.get("enabled")
        if enabled is False:
            cold = self.obj(value, "coldCompile", {"enabled", "reason"})
            if cold is not None:
                self.nonempty(cold.get("reason"), "coldCompile.reason")
            return
        cold = self.obj(
            value,
            "coldCompile",
            {
                "enabled",
                "runnerSkill",
                "inputSelection",
                "freshProcess",
                "productionTimingSeparated",
                "measuredPairs",
                "schedule",
                "oneShotProfilesPerVariant",
            },
        )
        if cold is None:
            return
        self.true(cold.get("enabled"), "coldCompile.enabled")
        self.exact(
            cold.get("runnerSkill"),
            "coldCompile.runnerSkill",
            "dtvm-cold-compile-profile",
        )
        self.exact(
            cold.get("inputSelection"),
            "coldCompile.inputSelection",
            "largest-nonempty-witness-code-deterministic-tiebreak",
        )
        self.true(cold.get("freshProcess"), "coldCompile.freshProcess")
        self.true(
            cold.get("productionTimingSeparated"),
            "coldCompile.productionTimingSeparated",
        )
        pairs = self.integer(
            cold.get("measuredPairs"), "coldCompile.measuredPairs", 20
        )
        self.balanced_schedule(cold.get("schedule"), "coldCompile.schedule", pairs)
        self.integer(
            cold.get("oneShotProfilesPerVariant"),
            "coldCompile.oneShotProfilesPerVariant",
            1,
        )

    def validate_source_trace(self, root: dict[str, Any]) -> None:
        trace = self.obj(
            root.get("sourceTrace"),
            "sourceTrace",
            {"skill", "requiredForCompilerHotspot", "requiredBeforeSourceEdit"},
        )
        if trace is None:
            return
        self.exact(
            trace.get("skill"),
            "sourceTrace.skill",
            "dtvm-compiler-path-analysis",
        )
        self.true(
            trace.get("requiredForCompilerHotspot"),
            "sourceTrace.requiredForCompilerHotspot",
        )
        self.true(
            trace.get("requiredBeforeSourceEdit"),
            "sourceTrace.requiredBeforeSourceEdit",
        )

    def validate_output(self, root: dict[str, Any]) -> None:
        output = self.obj(
            root.get("output"),
            "output",
            {
                "attemptRoot",
                "attemptId",
                "contractPath",
                "contractValidationPath",
                "refuseOverwrite",
                "evidenceSealRequired",
                "checksumManifest",
                "reportSkill",
                "claimRule",
            },
        )
        if output is None:
            return
        raw_root = output.get("attemptRoot")
        if not isinstance(raw_root, str) or not Path(raw_root).is_absolute():
            self.error("output.attemptRoot", "absolute path required")
        elif Path(raw_root) != Path(os.path.abspath(raw_root)):
            self.error("output.attemptRoot", "normalized absolute path required")
        attempt = output.get("attemptId")
        if not isinstance(attempt, str) or not ATTEMPT_RE.fullmatch(attempt):
            self.error(
                "output.attemptId",
                "1-128 safe filename characters required",
            )
        if (
            isinstance(raw_root, str)
            and Path(raw_root).is_absolute()
            and isinstance(attempt, str)
            and ATTEMPT_RE.fullmatch(attempt)
        ):
            attempt_dir = Path(raw_root) / attempt
            expected_contract = attempt_dir / "comparison-contract.json"
            expected_validation = (
                attempt_dir / "comparison-contract.validation.json"
            )
            self.exact(
                output.get("contractPath"),
                "output.contractPath",
                str(expected_contract),
            )
            self.exact(
                output.get("contractValidationPath"),
                "output.contractValidationPath",
                str(expected_validation),
            )
            self.exact(
                str(self.contract_path),
                "contract path",
                str(expected_contract),
            )
        self.true(output.get("refuseOverwrite"), "output.refuseOverwrite")
        self.true(
            output.get("evidenceSealRequired"), "output.evidenceSealRequired"
        )
        self.exact(
            output.get("checksumManifest"),
            "output.checksumManifest",
            "SHA256SUMS",
        )
        self.exact(
            output.get("reportSkill"), "output.reportSkill", "dtvm-write-report"
        )
        self.exact(
            output.get("claimRule"),
            "output.claimRule",
            "formal-only-after-all-gates",
        )

    def validate(self) -> None:
        root = self.obj(
            self.contract,
            "$",
            {
                "schema",
                "purpose",
                "window",
                "workload",
                "evidence",
                "variants",
                "comparison",
                "correctnessRequirements",
                "isolation",
                "runtime",
                "profiling",
                "coldCompile",
                "sourceTrace",
                "tooling",
                "output",
            },
        )
        if root is None:
            return
        self.exact(root.get("schema"), "schema", SCHEMA)
        purpose = root.get("purpose")
        if purpose not in {"formal", "diagnostic"}:
            self.error("purpose", "must be 'formal' or 'diagnostic'")
        start, end = self.validate_window(root)
        workload = self.validate_workload(root)
        evidence = self.validate_evidence(root)
        baseline, candidate = self.validate_variants(root)
        comparison = self.validate_comparison(root)
        self.validate_correctness_requirements(root)
        self.validate_proof_documents(
            evidence, baseline, candidate, comparison
        )
        self.validate_semantic_result(
            evidence, baseline, candidate, comparison, workload
        )
        self.validate_isolation(root)
        self.validate_runtime(root, purpose)
        self.validate_profiling(root, start, end, evidence)
        self.validate_cold_compile(root)
        self.validate_source_trace(root)
        self.validate_tooling(root, evidence)
        self.validate_output(root)


def load_contract(path: Path) -> Any:
    if not path.is_absolute():
        raise ValueError("contract path must be absolute")
    if path != Path(os.path.abspath(path)) or path != path.resolve(strict=True):
        raise ValueError("contract path must be a canonical realpath")
    if not path.is_file():
        raise ValueError("contract path is not a regular file")
    with path.open(encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=unique_object)


def write_report(path: Path | None, report: dict[str, Any]) -> None:
    payload = json.dumps(
        report, sort_keys=True, indent=2, ensure_ascii=False
    ) + "\n"
    if path is None:
        sys.stdout.write(payload)
        return
    if not path.is_absolute() or path != Path(os.path.abspath(path)):
        raise ValueError("output path must be normalized and absolute")
    path.parent.mkdir(parents=False, exist_ok=True)
    with path.open("x", encoding="utf-8") as stream:
        stream.write(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("contract", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        contract_path = args.contract
        contract = load_contract(contract_path)
        validator = ContractValidator(contract, contract_path)
        validator.validate()
        report = {
            "schema": REPORT_SCHEMA,
            "status": "valid" if not validator.errors else "invalid",
            "contract": {
                "path": str(contract_path),
                "sha256": sha256_file(contract_path),
                "canonicalSha256": canonical_sha256(contract),
            },
            "purpose": contract.get("purpose")
            if isinstance(contract, dict)
            else None,
            "semanticValidationStatus": validator.semantic_validation_status,
            "toolingValidationStatus": validator.tooling_validation_status,
            "filesVerified": sorted(
                validator.verified_files, key=lambda item: item["role"]
            ),
            "errors": sorted(set(validator.errors)),
        }
        if args.output is not None and isinstance(contract, dict):
            output_contract = contract.get("output")
            expected_output = (
                output_contract.get("contractValidationPath")
                if isinstance(output_contract, dict)
                else None
            )
            if str(args.output) != expected_output:
                raise ValueError(
                    "--output must equal output.contractValidationPath"
                )
        write_report(args.output, report)
        return 0 if not validator.errors else 1
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
