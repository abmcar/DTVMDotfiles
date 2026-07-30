#!/usr/bin/env python3
"""Validate minimum post-run continuity for one sealed replay-perf attempt."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


RUNTIME_SCHEMA = "dtvm.reth-replay-performance-runtime-result.v1"
ELIGIBILITY_SCHEMA = "dtvm.reth-replay-performance-eligibility.v1"
HOST_SCHEMA = "dtvm.reth-replay-performance-host-stability.v1"
CLASSIFICATION_SCHEMA = "dtvm.reth-replay-performance-perf-classification.v1"
REPORT_LINT_SCHEMA = "dtvm.reth-replay-performance-report-lint.v1"
SOURCE_BUILD_SCHEMA = "dtvm.reth-replay-performance-source-build-corpus.v1"
SEAL_SCHEMA = "dtvm.reth-replay-performance-evidence-seal.v1"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CLASSES = {
    "replayer",
    "dtvm",
    "kernel",
    "other",
    "inherited-child",
    "unresolved",
}
GATES = {
    "semanticValidation",
    "toolingValidation",
    "pairedIdentity",
    "sourceRelation",
    "strictCorrectness",
    "fullWindowCompleteness",
    "strictAlternatingSchedule",
    "repeatability",
    "quietness",
    "hostStability",
    "confidenceDirection",
    "practicalThreshold",
    "runtimePurity",
}


class DuplicateKeyError(ValueError):
    pass


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise DuplicateKeyError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


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


class ResultsValidator:
    def __init__(self, attempt: Path) -> None:
        self.attempt = attempt
        self.errors: list[str] = []

    def error(self, path: str, detail: str) -> None:
        self.errors.append(f"{path}: {detail}")

    def load_json(self, relative: str) -> dict[str, Any] | None:
        path = self.attempt / relative
        if path.is_symlink() or not path.is_file():
            self.error(relative, "regular non-symlink JSON file required")
            return None
        try:
            with path.open(encoding="utf-8") as stream:
                value = json.load(stream, object_pairs_hook=unique_object)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            self.error(relative, f"invalid JSON: {exc}")
            return None
        if not isinstance(value, dict):
            self.error(relative, "JSON object required")
            return None
        return value

    def exact_keys(
        self, value: Any, path: str, keys: set[str]
    ) -> dict[str, Any] | None:
        if not isinstance(value, dict):
            self.error(path, "object required")
            return None
        for key in sorted(keys - set(value)):
            self.error(path, f"missing key {key!r}")
        for key in sorted(set(value) - keys):
            self.error(path, f"unknown key {key!r}")
        return value

    def exact(self, value: Any, path: str, expected: Any) -> None:
        if value != expected:
            self.error(path, f"must equal {expected!r}")

    def digest(self, value: Any, path: str) -> None:
        if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
            self.error(path, "64 lowercase hexadecimal bytes required")

    def integer(self, value: Any, path: str, minimum: int = 0) -> int | None:
        if isinstance(value, bool) or not isinstance(value, int):
            self.error(path, "integer required")
            return None
        if value < minimum:
            self.error(path, f"must be at least {minimum}")
        return value

    def file_digest(self, relative: str) -> str | None:
        path = self.attempt / relative
        if path.is_symlink() or not path.is_file():
            self.error(relative, "regular non-symlink file required")
            return None
        return sha256_file(path)

    def validate_contract_bindings(
        self, value: Any, path: str = "contract"
    ) -> None:
        if isinstance(value, dict):
            if set(value) == {"path", "sha256"}:
                raw_path = value.get("path")
                expected = value.get("sha256")
                if not isinstance(raw_path, str) or not raw_path:
                    self.error(f"{path}.path", "absolute path required")
                    return
                candidate = Path(raw_path)
                try:
                    resolved = candidate.resolve(strict=True)
                except OSError as exc:
                    self.error(f"{path}.path", f"cannot resolve: {exc}")
                    return
                if (
                    not candidate.is_absolute()
                    or candidate != Path(os.path.abspath(candidate))
                    or candidate != resolved
                    or not candidate.is_file()
                    or candidate.is_symlink()
                ):
                    self.error(
                        f"{path}.path",
                        "canonical regular non-symlink file required",
                    )
                    return
                self.digest(expected, f"{path}.sha256")
                self.exact(
                    sha256_file(candidate),
                    f"{path}.sha256",
                    expected,
                )
                return
            for key, item in value.items():
                self.validate_contract_bindings(item, f"{path}.{key}")
        elif isinstance(value, list):
            for index, item in enumerate(value):
                self.validate_contract_bindings(item, f"{path}[{index}]")

    def validate(self) -> None:
        contract = self.load_json("comparison-contract.json")
        contract_validation = self.load_json(
            "comparison-contract.validation.json"
        )
        runtime = self.load_json("runtime/runtime-result.json")
        eligibility = self.load_json("eligibility.json")
        host = self.load_json("environment/host-stability.json")
        classification = self.load_json("perf/classification.json")
        report_lint = self.load_json("report/lint.json")
        source_build = self.load_json("identity/source-build-corpus.json")
        seal = self.load_json("evidence-seal.json")
        if any(
            value is None
            for value in (
                contract,
                contract_validation,
                runtime,
                eligibility,
                host,
                classification,
                report_lint,
                source_build,
                seal,
            )
        ):
            return
        assert contract is not None
        assert contract_validation is not None
        assert runtime is not None
        assert eligibility is not None
        assert host is not None
        assert classification is not None
        assert report_lint is not None
        assert source_build is not None
        assert seal is not None

        self.validate_contract_bindings(contract)
        contract_canonical = canonical_sha256(contract)
        contract_bytes = self.file_digest("comparison-contract.json")
        validation_bytes = self.file_digest(
            "comparison-contract.validation.json"
        )
        self.exact(
            contract_validation.get("status"),
            "comparison-contract.validation.status",
            "valid",
        )
        validation_contract = contract_validation.get("contract")
        if isinstance(validation_contract, dict):
            self.exact(
                validation_contract.get("sha256"),
                "comparison-contract.validation.contract.sha256",
                contract_bytes,
            )
            self.exact(
                validation_contract.get("canonicalSha256"),
                "comparison-contract.validation.contract.canonicalSha256",
                contract_canonical,
            )
        else:
            self.error(
                "comparison-contract.validation.contract", "object required"
            )

        output = contract.get("output")
        attempt_id = output.get("attemptId") if isinstance(output, dict) else None
        if isinstance(output, dict):
            expected_attempt = (
                Path(output.get("attemptRoot", "")) / str(attempt_id)
            )
            self.exact(
                str(self.attempt),
                "attempt",
                str(expected_attempt),
            )
        purpose = contract.get("purpose")
        tooling = contract.get("tooling")
        tooling_validation_binding = (
            tooling.get("validation") if isinstance(tooling, dict) else None
        )
        tooling_validation_sha = (
            tooling_validation_binding.get("sha256")
            if isinstance(tooling_validation_binding, dict)
            else None
        )
        evidence_sealer_package = (
            tooling.get("evidenceSealer")
            if isinstance(tooling, dict)
            else None
        )
        evidence_sealer_executable = (
            evidence_sealer_package.get("executable")
            if isinstance(evidence_sealer_package, dict)
            else None
        )
        evidence_sealer_sha = (
            evidence_sealer_executable.get("sha256")
            if isinstance(evidence_sealer_executable, dict)
            else None
        )

        self.validate_host(host, contract_canonical)
        self.validate_runtime(
            runtime,
            contract,
            contract_canonical,
            validation_bytes,
            attempt_id,
            host,
        )
        self.validate_eligibility(
            eligibility,
            purpose,
            contract_canonical,
            self.file_digest("runtime/runtime-result.json"),
            runtime,
        )
        self.validate_classification(
            classification, contract, contract_canonical
        )
        self.validate_report_lint(report_lint)
        self.validate_source_build(source_build, contract)
        self.validate_checksums()
        self.validate_seal(
            seal,
            attempt_id,
            purpose,
            contract_canonical,
            validation_bytes,
            tooling_validation_sha,
            evidence_sealer_sha,
            eligibility,
        )

    def validate_host(
        self, host: dict[str, Any], contract_canonical: str
    ) -> None:
        self.exact_keys(
            host,
            "hostStability",
            {
                "schema",
                "status",
                "contractCanonicalSha256",
                "beforeSnapshotSha256",
                "afterSnapshotSha256",
                "quietObservationsSha256",
                "targetLogicalCpu",
                "smtSiblingPolicy",
                "allQuietGatesPassed",
                "stableEnvironment",
            },
        )
        self.exact(host.get("schema"), "hostStability.schema", HOST_SCHEMA)
        self.exact(host.get("status"), "hostStability.status", "stable")
        self.exact(
            host.get("contractCanonicalSha256"),
            "hostStability.contractCanonicalSha256",
            contract_canonical,
        )
        for key in (
            "beforeSnapshotSha256",
            "afterSnapshotSha256",
            "quietObservationsSha256",
        ):
            self.digest(host.get(key), f"hostStability.{key}")
        for key, relative in (
            ("beforeSnapshotSha256", "environment/before.json"),
            ("afterSnapshotSha256", "environment/after.json"),
            (
                "quietObservationsSha256",
                "runtime/quiet-observations.json",
            ),
        ):
            self.exact(
                host.get(key),
                f"hostStability.{key}",
                self.file_digest(relative),
            )
        self.integer(
            host.get("targetLogicalCpu"),
            "hostStability.targetLogicalCpu",
        )
        self.exact(
            host.get("smtSiblingPolicy"),
            "hostStability.smtSiblingPolicy",
            "idle-or-offline",
        )
        self.exact(
            host.get("allQuietGatesPassed"),
            "hostStability.allQuietGatesPassed",
            True,
        )
        self.exact(
            host.get("stableEnvironment"),
            "hostStability.stableEnvironment",
            True,
        )

    def validate_runtime(
        self,
        runtime: dict[str, Any],
        contract: dict[str, Any],
        contract_canonical: str,
        validation_sha: str | None,
        attempt_id: Any,
        host: dict[str, Any],
    ) -> None:
        self.exact_keys(
            runtime,
            "runtimeResult",
            {
                "schema",
                "status",
                "attemptId",
                "contractCanonicalSha256",
                "contractValidationSha256",
                "runnerSha256",
                "statisticsAnalyzerSha256",
                "hostStabilitySha256",
                "schedule",
                "execution",
                "statistics",
            },
        )
        self.exact(runtime.get("schema"), "runtimeResult.schema", RUNTIME_SCHEMA)
        self.exact(runtime.get("status"), "runtimeResult.status", "complete")
        self.exact(runtime.get("attemptId"), "runtimeResult.attemptId", attempt_id)
        self.exact(
            runtime.get("contractCanonicalSha256"),
            "runtimeResult.contractCanonicalSha256",
            contract_canonical,
        )
        self.exact(
            runtime.get("contractValidationSha256"),
            "runtimeResult.contractValidationSha256",
            validation_sha,
        )
        self.exact(
            runtime.get("hostStabilitySha256"),
            "runtimeResult.hostStabilitySha256",
            self.file_digest("environment/host-stability.json"),
        )
        for key in ("runnerSha256", "statisticsAnalyzerSha256"):
            self.digest(runtime.get(key), f"runtimeResult.{key}")
        tooling = contract.get("tooling")
        for result_key, role in (
            ("runnerSha256", "runtimeRunner"),
            ("statisticsAnalyzerSha256", "statisticsAnalyzer"),
        ):
            package = tooling.get(role) if isinstance(tooling, dict) else None
            executable = (
                package.get("executable")
                if isinstance(package, dict)
                else None
            )
            self.exact(
                runtime.get(result_key),
                f"runtimeResult.{result_key}",
                executable.get("sha256")
                if isinstance(executable, dict)
                else None,
            )
        schedule = self.exact_keys(
            runtime.get("schedule"),
            "runtimeResult.schedule",
            {
                "warmup",
                "measuredScheduleSha256",
                "roundsPlanned",
                "roundsCompleted",
                "blockCount",
                "warmupSamplesExpected",
                "warmupSamplesComplete",
                "measuredSamplesExpected",
                "measuredSamplesComplete",
            },
        )
        runtime_contract = contract.get("runtime")
        window = contract.get("window")
        contract_cpu = (
            runtime_contract.get("cpu")
            if isinstance(runtime_contract, dict)
            else None
        )
        if isinstance(contract_cpu, dict):
            self.exact(
                host.get("targetLogicalCpu"),
                "hostStability.targetLogicalCpu",
                contract_cpu.get("logicalCpu"),
            )
        if (
            schedule is not None
            and isinstance(runtime_contract, dict)
            and isinstance(window, dict)
        ):
            rounds = runtime_contract.get("measuredRounds")
            blocks = window.get("blockCount")
            self.exact(
                schedule.get("warmup"),
                "runtimeResult.schedule.warmup",
                ["AB", "BA"],
            )
            self.exact(
                schedule.get("roundsPlanned"),
                "runtimeResult.schedule.roundsPlanned",
                rounds,
            )
            self.exact(
                schedule.get("roundsCompleted"),
                "runtimeResult.schedule.roundsCompleted",
                rounds,
            )
            self.exact(
                schedule.get("blockCount"),
                "runtimeResult.schedule.blockCount",
                blocks,
            )
            self.exact(
                schedule.get("measuredScheduleSha256"),
                "runtimeResult.schedule.measuredScheduleSha256",
                canonical_sha256(runtime_contract.get("schedule")),
            )
            if isinstance(blocks, int) and isinstance(rounds, int):
                self.exact(
                    schedule.get("warmupSamplesExpected"),
                    "runtimeResult.schedule.warmupSamplesExpected",
                    4 * blocks,
                )
                self.exact(
                    schedule.get("warmupSamplesComplete"),
                    "runtimeResult.schedule.warmupSamplesComplete",
                    4 * blocks,
                )
                self.exact(
                    schedule.get("measuredSamplesExpected"),
                    "runtimeResult.schedule.measuredSamplesExpected",
                    2 * rounds * blocks,
                )
                self.exact(
                    schedule.get("measuredSamplesComplete"),
                    "runtimeResult.schedule.measuredSamplesComplete",
                    2 * rounds * blocks,
                )
        self.digest(
            schedule.get("measuredScheduleSha256") if schedule else None,
            "runtimeResult.schedule.measuredScheduleSha256",
        )
        execution = self.exact_keys(
            runtime.get("execution"),
            "runtimeResult.execution",
            {
                "freshProcessEverySample",
                "strictCorrectEverySample",
                "offlineEverySample",
                "quietBeforeEveryBlockPair",
                "quietAfterRun",
                "noConcurrentFormalStage",
                "stdoutStderrBound",
                "samplesSha256",
                "roundsSha256",
                "quietObservationsSha256",
            },
        )
        if execution is not None:
            for key in (
                "freshProcessEverySample",
                "strictCorrectEverySample",
                "offlineEverySample",
                "quietBeforeEveryBlockPair",
                "quietAfterRun",
                "noConcurrentFormalStage",
                "stdoutStderrBound",
            ):
                self.exact(
                    execution.get(key), f"runtimeResult.execution.{key}", True
                )
            for key in (
                "samplesSha256",
                "roundsSha256",
                "quietObservationsSha256",
            ):
                self.digest(
                    execution.get(key), f"runtimeResult.execution.{key}"
                )
            self.exact(
                execution.get("quietObservationsSha256"),
                "runtimeResult.execution.quietObservationsSha256",
                host.get("quietObservationsSha256"),
            )
            for key, relative in (
                ("samplesSha256", "runtime/samples.jsonl"),
                ("roundsSha256", "runtime/rounds.json"),
                (
                    "quietObservationsSha256",
                    "runtime/quiet-observations.json",
                ),
            ):
                self.exact(
                    execution.get(key),
                    f"runtimeResult.execution.{key}",
                    self.file_digest(relative),
                )
        statistics = self.exact_keys(
            runtime.get("statistics"),
            "runtimeResult.statistics",
            {
                "pairCount",
                "primaryName",
                "pointEstimatePercent",
                "confidenceLevel",
                "confidenceLowerPercent",
                "confidenceUpperPercent",
                "bootstrapSeed",
                "bootstrapResamples",
                "minimumPracticalEffectPercent",
                "baselineRoundCvPercent",
                "candidateRoundCvPercent",
                "aggregateCandidateToBaselineRatio",
            },
        )
        if statistics is not None and isinstance(runtime_contract, dict):
            self.exact(
                statistics.get("pairCount"),
                "runtimeResult.statistics.pairCount",
                runtime_contract.get("measuredRounds"),
            )
            self.exact(
                statistics.get("primaryName"),
                "runtimeResult.statistics.primaryName",
                "median-paired-full-window-relative-delta",
            )
            self.exact(
                statistics.get("confidenceLevel"),
                "runtimeResult.statistics.confidenceLevel",
                0.95,
            )
            self.exact(
                statistics.get("minimumPracticalEffectPercent"),
                "runtimeResult.statistics.minimumPracticalEffectPercent",
                0.5,
            )

    def validate_eligibility(
        self,
        eligibility: dict[str, Any],
        purpose: Any,
        contract_canonical: str,
        runtime_sha: str | None,
        runtime: dict[str, Any],
    ) -> None:
        self.exact_keys(
            eligibility,
            "eligibility",
            {
                "schema",
                "status",
                "purpose",
                "contractCanonicalSha256",
                "runtimeResultSha256",
                "statisticsAnalyzerSha256",
                "gates",
                "conclusionEligibleBeforeSeal",
                "reasons",
            },
        )
        self.exact(
            eligibility.get("schema"), "eligibility.schema", ELIGIBILITY_SCHEMA
        )
        self.exact(eligibility.get("purpose"), "eligibility.purpose", purpose)
        self.exact(
            eligibility.get("contractCanonicalSha256"),
            "eligibility.contractCanonicalSha256",
            contract_canonical,
        )
        self.exact(
            eligibility.get("runtimeResultSha256"),
            "eligibility.runtimeResultSha256",
            runtime_sha,
        )
        self.exact(
            eligibility.get("statisticsAnalyzerSha256"),
            "eligibility.statisticsAnalyzerSha256",
            runtime.get("statisticsAnalyzerSha256"),
        )
        gates = self.exact_keys(
            eligibility.get("gates"), "eligibility.gates", GATES
        )
        all_gates = gates is not None and all(value is True for value in gates.values())
        eligible = purpose == "formal" and all_gates
        self.exact(
            eligibility.get("status"),
            "eligibility.status",
            "passed" if eligible else "observational",
        )
        self.exact(
            eligibility.get("conclusionEligibleBeforeSeal"),
            "eligibility.conclusionEligibleBeforeSeal",
            eligible,
        )
        reasons = eligibility.get("reasons")
        if eligible:
            self.exact(reasons, "eligibility.reasons", [])
        elif not isinstance(reasons, list) or not reasons:
            self.error(
                "eligibility.reasons",
                "non-empty list required for observational result",
            )

    def validate_classification(
        self,
        classification: dict[str, Any],
        contract: dict[str, Any],
        contract_canonical: str,
    ) -> None:
        self.exact_keys(
            classification,
            "perfClassification",
            {
                "schema",
                "status",
                "contractCanonicalSha256",
                "classifierSha256",
                "recordEvent",
                "recordEventScope",
                "inheritChildren",
                "representativeBlocksCanonicalSha256",
                "rawInputsSha256",
                "denominatorWeightedCycles",
                "lostSamples",
                "shares",
                "dtvmBuildIdMatch",
                "attemptLocalSymfs",
                "symbolizedSelfAndInclusiveReports",
                "unresolvedDtvmSamples",
            },
        )
        self.exact(
            classification.get("schema"),
            "perfClassification.schema",
            CLASSIFICATION_SCHEMA,
        )
        self.exact(
            classification.get("status"),
            "perfClassification.status",
            "complete",
        )
        self.exact(
            classification.get("contractCanonicalSha256"),
            "perfClassification.contractCanonicalSha256",
            contract_canonical,
        )
        profiling = contract.get("profiling")
        tooling = contract.get("tooling")
        classifier_package = (
            tooling.get("perfClassifier") if isinstance(tooling, dict) else None
        )
        classifier_executable = (
            classifier_package.get("executable")
            if isinstance(classifier_package, dict)
            else None
        )
        self.exact(
            classification.get("classifierSha256"),
            "perfClassification.classifierSha256",
            classifier_executable.get("sha256")
            if isinstance(classifier_executable, dict)
            else None,
        )
        if isinstance(profiling, dict):
            for key in ("recordEvent", "recordEventScope", "inheritChildren"):
                self.exact(
                    classification.get(key),
                    f"perfClassification.{key}",
                    profiling.get(key),
                )
            self.exact(
                classification.get("representativeBlocksCanonicalSha256"),
                "perfClassification.representativeBlocksCanonicalSha256",
                canonical_sha256(profiling.get("representativeBlocks")),
            )
        for key in ("classifierSha256", "rawInputsSha256"):
            self.digest(
                classification.get(key), f"perfClassification.{key}"
            )
        self.exact(
            classification.get("rawInputsSha256"),
            "perfClassification.rawInputsSha256",
            self.file_digest("perf/raw-inputs.json"),
        )
        denominator = self.integer(
            classification.get("denominatorWeightedCycles"),
            "perfClassification.denominatorWeightedCycles",
            1,
        )
        self.integer(
            classification.get("lostSamples"),
            "perfClassification.lostSamples",
        )
        shares = self.exact_keys(
            classification.get("shares"), "perfClassification.shares", CLASSES
        )
        weighted_total = 0
        percent_total = 0.0
        if shares is not None:
            for role in sorted(CLASSES):
                share = self.exact_keys(
                    shares.get(role),
                    f"perfClassification.shares.{role}",
                    {"weightedCycles", "percent"},
                )
                if share is None:
                    continue
                weighted = self.integer(
                    share.get("weightedCycles"),
                    f"perfClassification.shares.{role}.weightedCycles",
                )
                percent = share.get("percent")
                if isinstance(percent, bool) or not isinstance(
                    percent, (int, float)
                ):
                    self.error(
                        f"perfClassification.shares.{role}.percent",
                        "number required",
                    )
                else:
                    percent_total += float(percent)
                if weighted is not None:
                    weighted_total += weighted
        if denominator is not None:
            self.exact(
                weighted_total,
                "perfClassification.shares.weightedCycles",
                denominator,
            )
        if abs(percent_total - 100.0) > 0.0001:
            self.error(
                "perfClassification.shares.percent",
                "percentages must sum to 100",
            )
        for key in (
            "dtvmBuildIdMatch",
            "attemptLocalSymfs",
            "symbolizedSelfAndInclusiveReports",
        ):
            self.exact(
                classification.get(key), f"perfClassification.{key}", True
            )
        self.exact(
            classification.get("unresolvedDtvmSamples"),
            "perfClassification.unresolvedDtvmSamples",
            0,
        )

    def validate_report_lint(self, lint: dict[str, Any]) -> None:
        self.exact_keys(
            lint,
            "reportLint",
            {
                "schema",
                "status",
                "linterSha256",
                "artifactSha256",
                "htmlSha256",
                "artifactCommandSha256",
                "htmlCommandSha256",
                "artifactLogSha256",
                "htmlLogSha256",
                "errors",
                "warnings",
            },
        )
        self.exact(lint.get("schema"), "reportLint.schema", REPORT_LINT_SCHEMA)
        self.exact(lint.get("status"), "reportLint.status", "passed")
        for key in (
            "linterSha256",
            "artifactSha256",
            "htmlSha256",
            "artifactCommandSha256",
            "htmlCommandSha256",
            "artifactLogSha256",
            "htmlLogSha256",
        ):
            self.digest(lint.get(key), f"reportLint.{key}")
        for key, relative in (
            ("linterSha256", "report/lint_report.py"),
            ("artifactSha256", "report/artifact.json"),
            ("htmlSha256", "report/report.html"),
            ("artifactCommandSha256", "report/artifact-lint.command.json"),
            ("htmlCommandSha256", "report/html-lint.command.json"),
            ("artifactLogSha256", "report/artifact-lint.log"),
            ("htmlLogSha256", "report/html-lint.log"),
        ):
            self.exact(
                lint.get(key), f"reportLint.{key}", self.file_digest(relative)
            )
        self.exact(lint.get("errors"), "reportLint.errors", 0)
        self.integer(lint.get("warnings"), "reportLint.warnings")

    def validate_source_build(
        self, source_build: dict[str, Any], contract: dict[str, Any]
    ) -> None:
        self.exact_keys(
            source_build,
            "sourceBuildCorpus",
            {
                "schema",
                "corpusManifestSha256",
                "chainConfigSha256",
                "approvedReplayerManifestSha256",
                "approvedReplayerBinarySha256",
                "baseline",
                "candidate",
            },
        )
        self.exact(
            source_build.get("schema"),
            "sourceBuildCorpus.schema",
            SOURCE_BUILD_SCHEMA,
        )
        evidence = contract.get("evidence")
        variants = contract.get("variants")

        def bound_digest(container: Any, key: str) -> Any:
            binding = container.get(key) if isinstance(container, dict) else None
            return binding.get("sha256") if isinstance(binding, dict) else None

        for key, contract_key in (
            ("corpusManifestSha256", "corpusManifest"),
            ("chainConfigSha256", "chainConfig"),
            ("approvedReplayerManifestSha256", "approvedReplayerManifest"),
            ("approvedReplayerBinarySha256", "approvedReplayerBinary"),
        ):
            self.exact(
                source_build.get(key),
                f"sourceBuildCorpus.{key}",
                bound_digest(evidence, contract_key),
            )
        for role in ("baseline", "candidate"):
            value = self.exact_keys(
                source_build.get(role),
                f"sourceBuildCorpus.{role}",
                {
                    "commit",
                    "tree",
                    "librarySha256",
                    "cmakeCacheSha256",
                    "strictSealSha256",
                },
            )
            variant = variants.get(role) if isinstance(variants, dict) else None
            if value is None or not isinstance(variant, dict):
                continue
            self.exact(
                value.get("commit"),
                f"sourceBuildCorpus.{role}.commit",
                variant.get("commit"),
            )
            self.exact(
                value.get("tree"),
                f"sourceBuildCorpus.{role}.tree",
                variant.get("tree"),
            )
            self.exact(
                value.get("librarySha256"),
                f"sourceBuildCorpus.{role}.librarySha256",
                bound_digest(variant, "library"),
            )
            self.exact(
                value.get("cmakeCacheSha256"),
                f"sourceBuildCorpus.{role}.cmakeCacheSha256",
                bound_digest(variant, "cmakeCache"),
            )
            self.exact(
                value.get("strictSealSha256"),
                f"sourceBuildCorpus.{role}.strictSealSha256",
                bound_digest(evidence, f"{role}Seal"),
            )

    def validate_checksums(self) -> None:
        path = self.attempt / "SHA256SUMS"
        if path.is_symlink() or not path.is_file():
            self.error("SHA256SUMS", "regular non-symlink file required")
            return
        entries: dict[str, str] = {}
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            self.error("SHA256SUMS", str(exc))
            return
        names: list[str] = []
        for index, line in enumerate(lines, 1):
            if len(line) < 67 or line[64:66] != "  ":
                self.error(f"SHA256SUMS:{index}", "GNU-style SHA-256 line required")
                continue
            digest, name = line[:64], line[66:]
            if not SHA256_RE.fullmatch(digest):
                self.error(f"SHA256SUMS:{index}", "invalid SHA-256")
                continue
            relative = Path(name)
            if (
                not name
                or relative.is_absolute()
                or ".." in relative.parts
                or name in entries
                or name in {"SHA256SUMS", "evidence-seal.json"}
            ):
                self.error(f"SHA256SUMS:{index}", "unsafe or duplicate path")
                continue
            entries[name] = digest
            names.append(name)
        if names != sorted(names, key=lambda item: item.encode("utf-8")):
            self.error("SHA256SUMS", "paths must be bytewise sorted")
        actual: dict[str, str] = {}
        for candidate in self.attempt.rglob("*"):
            relative = candidate.relative_to(self.attempt).as_posix()
            if relative in {"SHA256SUMS", "evidence-seal.json"}:
                continue
            if candidate.is_symlink():
                self.error(relative, "symlink forbidden in sealed attempt")
            elif candidate.is_file():
                actual[relative] = sha256_file(candidate)
        self.exact(entries, "SHA256SUMS.entries", actual)

    def validate_seal(
        self,
        seal: dict[str, Any],
        attempt_id: Any,
        purpose: Any,
        contract_canonical: str,
        validation_sha: str | None,
        tooling_validation_sha: Any,
        evidence_sealer_sha: Any,
        eligibility: dict[str, Any],
    ) -> None:
        self.exact_keys(
            seal,
            "evidenceSeal",
            {
                "schema",
                "status",
                "attemptId",
                "contractCanonicalSha256",
                "contractValidationSha256",
                "runtimeResultSha256",
                "eligibilitySha256",
                "hostStabilitySha256",
                "perfClassificationSha256",
                "reportLintSha256",
                "sourceBuildCorpusSha256",
                "toolingValidationSha256",
                "checksumManifestSha256",
                "evidenceSealerSha256",
                "networkUsed",
                "credentialsRecorded",
                "rerunVerified",
                "finalConclusionEligible",
            },
        )
        self.exact(seal.get("schema"), "evidenceSeal.schema", SEAL_SCHEMA)
        self.exact(seal.get("status"), "evidenceSeal.status", "sealed")
        self.exact(seal.get("attemptId"), "evidenceSeal.attemptId", attempt_id)
        expected = {
            "contractCanonicalSha256": contract_canonical,
            "contractValidationSha256": validation_sha,
            "runtimeResultSha256": self.file_digest("runtime/runtime-result.json"),
            "eligibilitySha256": self.file_digest("eligibility.json"),
            "hostStabilitySha256": self.file_digest("environment/host-stability.json"),
            "perfClassificationSha256": self.file_digest("perf/classification.json"),
            "reportLintSha256": self.file_digest("report/lint.json"),
            "sourceBuildCorpusSha256": self.file_digest(
                "identity/source-build-corpus.json"
            ),
            "toolingValidationSha256": tooling_validation_sha,
            "checksumManifestSha256": self.file_digest("SHA256SUMS"),
        }
        for key, value in expected.items():
            self.exact(seal.get(key), f"evidenceSeal.{key}", value)
        self.exact(
            seal.get("evidenceSealerSha256"),
            "evidenceSeal.evidenceSealerSha256",
            evidence_sealer_sha,
        )
        self.exact(seal.get("networkUsed"), "evidenceSeal.networkUsed", False)
        self.exact(
            seal.get("credentialsRecorded"),
            "evidenceSeal.credentialsRecorded",
            False,
        )
        self.exact(
            seal.get("rerunVerified"), "evidenceSeal.rerunVerified", True
        )
        gates = eligibility.get("gates")
        expected_eligible = (
            purpose == "formal"
            and isinstance(gates, dict)
            and set(gates) == GATES
            and all(value is True for value in gates.values())
            and eligibility.get("status") == "passed"
            and eligibility.get("conclusionEligibleBeforeSeal") is True
        )
        self.exact(
            seal.get("finalConclusionEligible"),
            "evidenceSeal.finalConclusionEligible",
            expected_eligible,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("attempt", type=Path)
    args = parser.parse_args()
    attempt = args.attempt
    if (
        not attempt.is_absolute()
        or attempt != Path(os.path.abspath(attempt))
        or attempt != attempt.resolve(strict=True)
        or not attempt.is_dir()
        or attempt.is_symlink()
    ):
        print("attempt must be a canonical absolute directory", file=sys.stderr)
        return 2
    validator = ResultsValidator(attempt)
    validator.validate()
    report = {
        "schema": "dtvm.reth-replay-performance-post-run-validation.v1",
        "status": "valid" if not validator.errors else "invalid",
        "attempt": str(attempt),
        "errors": sorted(set(validator.errors)),
    }
    print(json.dumps(report, sort_keys=True, indent=2) + "\n", end="")
    return 0 if not validator.errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
