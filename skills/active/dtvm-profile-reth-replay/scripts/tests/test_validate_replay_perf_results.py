#!/usr/bin/env python3
"""Tests for minimum post-run replay performance evidence continuity."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


SCRIPTS = Path(__file__).resolve().parents[1]
RESULTS_SCRIPT = SCRIPTS / "validate_replay_perf_results.py"
CONTRACT_TEST = (
    SCRIPTS / "tests" / "test_validate_replay_perf_contract.py"
)
SPEC = importlib.util.spec_from_file_location("contract_fixture", CONTRACT_TEST)
assert SPEC is not None and SPEC.loader is not None
contract_fixture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(contract_fixture)

RESULTS_SPEC = importlib.util.spec_from_file_location(
    "results_validator", RESULTS_SCRIPT
)
assert RESULTS_SPEC is not None and RESULTS_SPEC.loader is not None
results_validator = importlib.util.module_from_spec(RESULTS_SPEC)
RESULTS_SPEC.loader.exec_module(results_validator)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )


class ResultsFixture:
    def __init__(self, root: Path) -> None:
        self.contract_fixture = contract_fixture.Fixture(root)
        self.contract = self.contract_fixture.contract
        self.attempt = self.contract_fixture.contract_path.parent
        validation_path = Path(
            self.contract["output"]["contractValidationPath"]
        )
        result = self.contract_fixture.run(validation_path)
        if result.returncode != 0:
            raise AssertionError(result.stderr + result.stdout)
        self.contract_validation = json.loads(
            validation_path.read_text(encoding="utf-8")
        )
        self.contract_canonical = contract_fixture.validator.canonical_sha256(
            self.contract
        )
        self._write_supporting_files()
        self._write_results()
        self._write_checksums_and_seal()

    def _write_supporting_files(self) -> None:
        files = {
            "environment/before.json": {"phase": "before", "stable": True},
            "environment/after.json": {"phase": "after", "stable": True},
            "runtime/quiet-observations.json": {
                "pairs": 352,
                "allPassed": True,
            },
            "runtime/samples.jsonl": {"samples": 704},
            "runtime/rounds.json": {"rounds": 20},
            "perf/raw-inputs.json": {"perfDataFiles": 8},
            "report/artifact.json": {"title": "Fixture report"},
            "report/report.html": "<!doctype html><title>Fixture</title>\n",
            "report/lint_report.py": "# fixture linter\n",
            "report/artifact-lint.command.json": {
                "argv": ["lint_report.py", "artifact.json"]
            },
            "report/html-lint.command.json": {
                "argv": ["lint_report.py", "report.html"]
            },
            "report/artifact-lint.log": "DTVM report lint: PASS\n",
            "report/html-lint.log": "DTVM report lint: PASS\n",
        }
        for relative, value in files.items():
            path = self.attempt / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(value, str):
                path.write_text(value, encoding="utf-8")
            else:
                write_json(path, value)

    def _tool_sha(self, role: str) -> str:
        return self.contract["tooling"][role]["executable"]["sha256"]

    def _write_results(self) -> None:
        host = {
            "schema": results_validator.HOST_SCHEMA,
            "status": "stable",
            "contractCanonicalSha256": self.contract_canonical,
            "beforeSnapshotSha256": sha256(
                self.attempt / "environment/before.json"
            ),
            "afterSnapshotSha256": sha256(
                self.attempt / "environment/after.json"
            ),
            "quietObservationsSha256": sha256(
                self.attempt / "runtime/quiet-observations.json"
            ),
            "targetLogicalCpu": 50,
            "smtSiblingPolicy": "idle-or-offline",
            "allQuietGatesPassed": True,
            "stableEnvironment": True,
        }
        write_json(self.attempt / "environment/host-stability.json", host)

        runtime = {
            "schema": results_validator.RUNTIME_SCHEMA,
            "status": "complete",
            "attemptId": self.contract["output"]["attemptId"],
            "contractCanonicalSha256": self.contract_canonical,
            "contractValidationSha256": sha256(
                self.attempt / "comparison-contract.validation.json"
            ),
            "runnerSha256": self._tool_sha("runtimeRunner"),
            "statisticsAnalyzerSha256": self._tool_sha(
                "statisticsAnalyzer"
            ),
            "hostStabilitySha256": sha256(
                self.attempt / "environment/host-stability.json"
            ),
            "schedule": {
                "warmup": ["AB", "BA"],
                "measuredScheduleSha256": (
                    contract_fixture.validator.canonical_sha256(
                        self.contract["runtime"]["schedule"]
                    )
                ),
                "roundsPlanned": 20,
                "roundsCompleted": 20,
                "blockCount": 16,
                "warmupSamplesExpected": 64,
                "warmupSamplesComplete": 64,
                "measuredSamplesExpected": 640,
                "measuredSamplesComplete": 640,
            },
            "execution": {
                "freshProcessEverySample": True,
                "strictCorrectEverySample": True,
                "offlineEverySample": True,
                "quietBeforeEveryBlockPair": True,
                "quietAfterRun": True,
                "noConcurrentFormalStage": True,
                "stdoutStderrBound": True,
                "samplesSha256": sha256(
                    self.attempt / "runtime/samples.jsonl"
                ),
                "roundsSha256": sha256(
                    self.attempt / "runtime/rounds.json"
                ),
                "quietObservationsSha256": host[
                    "quietObservationsSha256"
                ],
            },
            "statistics": {
                "pairCount": 20,
                "primaryName": (
                    "median-paired-full-window-relative-delta"
                ),
                "pointEstimatePercent": -1.25,
                "confidenceLevel": 0.95,
                "confidenceLowerPercent": -1.8,
                "confidenceUpperPercent": -0.7,
                "bootstrapSeed": 577,
                "bootstrapResamples": 10000,
                "minimumPracticalEffectPercent": 0.5,
                "baselineRoundCvPercent": 2.0,
                "candidateRoundCvPercent": 2.1,
                "aggregateCandidateToBaselineRatio": 0.9875,
            },
        }
        write_json(self.attempt / "runtime/runtime-result.json", runtime)

        gates = {key: True for key in results_validator.GATES}
        eligibility = {
            "schema": results_validator.ELIGIBILITY_SCHEMA,
            "status": "passed",
            "purpose": "formal",
            "contractCanonicalSha256": self.contract_canonical,
            "runtimeResultSha256": sha256(
                self.attempt / "runtime/runtime-result.json"
            ),
            "statisticsAnalyzerSha256": self._tool_sha(
                "statisticsAnalyzer"
            ),
            "gates": gates,
            "conclusionEligibleBeforeSeal": True,
            "reasons": [],
        }
        write_json(self.attempt / "eligibility.json", eligibility)

        weighted = {
            "replayer": (500, 50.0),
            "dtvm": (200, 20.0),
            "kernel": (100, 10.0),
            "other": (100, 10.0),
            "inherited-child": (50, 5.0),
            "unresolved": (50, 5.0),
        }
        classification = {
            "schema": results_validator.CLASSIFICATION_SCHEMA,
            "status": "complete",
            "contractCanonicalSha256": self.contract_canonical,
            "classifierSha256": self._tool_sha("perfClassifier"),
            "recordEvent": "cycles",
            "recordEventScope": "user-and-kernel",
            "inheritChildren": True,
            "representativeBlocksCanonicalSha256": (
                contract_fixture.validator.canonical_sha256(
                    self.contract["profiling"]["representativeBlocks"]
                )
            ),
            "rawInputsSha256": sha256(
                self.attempt / "perf/raw-inputs.json"
            ),
            "denominatorWeightedCycles": 1000,
            "lostSamples": 0,
            "shares": {
                key: {"weightedCycles": value[0], "percent": value[1]}
                for key, value in weighted.items()
            },
            "dtvmBuildIdMatch": True,
            "attemptLocalSymfs": True,
            "symbolizedSelfAndInclusiveReports": True,
            "unresolvedDtvmSamples": 0,
        }
        write_json(self.attempt / "perf/classification.json", classification)

        lint = {
            "schema": results_validator.REPORT_LINT_SCHEMA,
            "status": "passed",
            "linterSha256": sha256(
                self.attempt / "report/lint_report.py"
            ),
            "artifactSha256": sha256(
                self.attempt / "report/artifact.json"
            ),
            "htmlSha256": sha256(self.attempt / "report/report.html"),
            "artifactCommandSha256": sha256(
                self.attempt / "report/artifact-lint.command.json"
            ),
            "htmlCommandSha256": sha256(
                self.attempt / "report/html-lint.command.json"
            ),
            "artifactLogSha256": sha256(
                self.attempt / "report/artifact-lint.log"
            ),
            "htmlLogSha256": sha256(
                self.attempt / "report/html-lint.log"
            ),
            "errors": 0,
            "warnings": 0,
        }
        write_json(self.attempt / "report/lint.json", lint)

        evidence = self.contract["evidence"]
        variants = self.contract["variants"]
        source_build = {
            "schema": results_validator.SOURCE_BUILD_SCHEMA,
            "corpusManifestSha256": evidence["corpusManifest"]["sha256"],
            "chainConfigSha256": evidence["chainConfig"]["sha256"],
            "approvedReplayerManifestSha256": evidence[
                "approvedReplayerManifest"
            ]["sha256"],
            "approvedReplayerBinarySha256": evidence[
                "approvedReplayerBinary"
            ]["sha256"],
            "baseline": {
                "commit": variants["baseline"]["commit"],
                "tree": variants["baseline"]["tree"],
                "librarySha256": variants["baseline"]["library"]["sha256"],
                "cmakeCacheSha256": variants["baseline"]["cmakeCache"][
                    "sha256"
                ],
                "strictSealSha256": evidence["baselineSeal"]["sha256"],
            },
            "candidate": {
                "commit": variants["candidate"]["commit"],
                "tree": variants["candidate"]["tree"],
                "librarySha256": variants["candidate"]["library"]["sha256"],
                "cmakeCacheSha256": variants["candidate"]["cmakeCache"][
                    "sha256"
                ],
                "strictSealSha256": evidence["candidateSeal"]["sha256"],
            },
        }
        write_json(
            self.attempt / "identity/source-build-corpus.json",
            source_build,
        )

    def _write_checksums_and_seal(self) -> None:
        entries = []
        for path in self.attempt.rglob("*"):
            if path.is_file() and path.name not in {
                "SHA256SUMS",
                "evidence-seal.json",
            }:
                entries.append(
                    (path.relative_to(self.attempt).as_posix(), sha256(path))
                )
        entries.sort(key=lambda item: item[0].encode("utf-8"))
        (self.attempt / "SHA256SUMS").write_text(
            "".join(f"{digest}  {name}\n" for name, digest in entries),
            encoding="utf-8",
        )
        seal = {
            "schema": results_validator.SEAL_SCHEMA,
            "status": "sealed",
            "attemptId": self.contract["output"]["attemptId"],
            "contractCanonicalSha256": self.contract_canonical,
            "contractValidationSha256": sha256(
                self.attempt / "comparison-contract.validation.json"
            ),
            "runtimeResultSha256": sha256(
                self.attempt / "runtime/runtime-result.json"
            ),
            "eligibilitySha256": sha256(
                self.attempt / "eligibility.json"
            ),
            "hostStabilitySha256": sha256(
                self.attempt / "environment/host-stability.json"
            ),
            "perfClassificationSha256": sha256(
                self.attempt / "perf/classification.json"
            ),
            "reportLintSha256": sha256(
                self.attempt / "report/lint.json"
            ),
            "sourceBuildCorpusSha256": sha256(
                self.attempt / "identity/source-build-corpus.json"
            ),
            "toolingValidationSha256": self.contract["tooling"][
                "validation"
            ]["sha256"],
            "checksumManifestSha256": sha256(
                self.attempt / "SHA256SUMS"
            ),
            "evidenceSealerSha256": self._tool_sha("evidenceSealer"),
            "networkUsed": False,
            "credentialsRecorded": False,
            "rerunVerified": True,
            "finalConclusionEligible": True,
        }
        write_json(self.attempt / "evidence-seal.json", seal)

    def run(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(RESULTS_SCRIPT), str(self.attempt)],
            text=True,
            capture_output=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            check=False,
        )

    def rewrite_json(self, relative: str, mutate: Any) -> None:
        path = self.attempt / relative
        value = json.loads(path.read_text(encoding="utf-8"))
        mutate(value)
        write_json(path, value)


class ResultsValidatorTests(unittest.TestCase):
    def test_valid_sealed_attempt_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = ResultsFixture(Path(temp))
            result = fixture.run()
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(json.loads(result.stdout)["status"], "valid")

    def test_runtime_host_digest_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = ResultsFixture(Path(temp))
            fixture.rewrite_json(
                "runtime/runtime-result.json",
                lambda value: value.__setitem__(
                    "hostStabilitySha256", "0" * 64
                ),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("runtimeResult.hostStabilitySha256", result.stdout)

    def test_contract_bound_external_artifact_is_rehashed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = ResultsFixture(Path(temp))
            manifest = Path(
                fixture.contract["evidence"]["corpusManifest"]["path"]
            )
            manifest.write_text("drift\n", encoding="utf-8")
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "contract.evidence.corpusManifest.sha256", result.stdout
            )

    def test_perf_shares_must_cover_denominator(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = ResultsFixture(Path(temp))
            fixture.rewrite_json(
                "perf/classification.json",
                lambda value: value["shares"]["dtvm"].__setitem__(
                    "weightedCycles", 199
                ),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "perfClassification.shares.weightedCycles", result.stdout
            )

    def test_checksum_manifest_must_cover_every_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = ResultsFixture(Path(temp))
            (fixture.attempt / "unlisted.txt").write_text(
                "unlisted\n", encoding="utf-8"
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("SHA256SUMS.entries", result.stdout)

    def test_seal_cannot_claim_formal_conclusion_after_gate_failure(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = ResultsFixture(Path(temp))
            fixture.rewrite_json(
                "eligibility.json",
                lambda value: value["gates"].__setitem__(
                    "repeatability", False
                ),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("eligibility.status", result.stdout)
            self.assertIn("evidenceSeal.finalConclusionEligible", result.stdout)


if __name__ == "__main__":
    unittest.main()
