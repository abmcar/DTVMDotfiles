#!/usr/bin/env python3
"""Tests for the frozen replay performance contract validator."""

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


SCRIPT = Path(__file__).resolve().parents[1] / "validate_replay_perf_contract.py"
SPEC = importlib.util.spec_from_file_location("contract_validator", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Fixture:
    def __init__(self, root: Path, purpose: str = "formal") -> None:
        self.root = root
        self.files: dict[str, dict[str, str]] = {}
        for name in (
            "approved.json",
            "replay-block",
            "baseline-seal.json",
            "candidate-seal.json",
            "correctness.json",
            "chain-config.json",
            "paired-identity.json",
            "source-relation.json",
            "baseline.so",
            "candidate.so",
            "baseline-cache.txt",
            "candidate-cache.txt",
            "semantic-validator",
            "semantic-validator-test.py",
            "semantic-validator-test.log",
            "runtime-runner",
            "runtime-runner-test.py",
            "runtime-runner-test.log",
            "statistics-analyzer",
            "statistics-analyzer-test.py",
            "statistics-analyzer-test.log",
            "perf-classifier",
            "perf-classifier-test.py",
            "perf-classifier-test.log",
            "evidence-sealer",
            "evidence-sealer-test.py",
            "evidence-sealer-test.log",
        ):
            path = root / name
            path.write_text(f"fixture:{name}\n", encoding="utf-8")
            if name in {
                "semantic-validator",
                "runtime-runner",
                "statistics-analyzer",
                "perf-classifier",
                "evidence-sealer",
            } or name.endswith("-test.py"):
                path.chmod(0o700)
            self.files[name] = {"path": str(path), "sha256": sha256(path)}
        manifest = root / "manifest.json"
        manifest.write_text(
            json.dumps(
                {
                    "blocks": [
                        {
                            "number": 25625000 + index,
                            "hash": f"0x{25625000 + index:064x}",
                            "gasUsed": 1000 + index,
                        }
                        for index in range(16)
                    ]
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        self.files["manifest.json"] = {
            "path": str(manifest),
            "sha256": sha256(manifest),
        }
        rounds = 20 if purpose == "formal" else 7
        schedule = ["AB" if index % 2 == 0 else "BA" for index in range(rounds)]
        evidence = {
            "corpusManifest": self.files["manifest.json"],
            "approvedReplayerManifest": self.files["approved.json"],
            "approvedReplayerBinary": self.files["replay-block"],
            "baselineSeal": self.files["baseline-seal.json"],
            "candidateSeal": self.files["candidate-seal.json"],
            "correctnessSummary": self.files["correctness.json"],
            "chainConfig": self.files["chain-config.json"],
            "identityProof": self.files["paired-identity.json"],
            "sourceRelationProof": self.files["source-relation.json"],
            "semanticValidator": self.files["semantic-validator"],
        }
        variants = {
            "baseline": {
                "label": "baseline",
                "commit": "1" * 40,
                "tree": "2" * 40,
                "library": self.files["baseline.so"],
                "cmakeCache": self.files["baseline-cache.txt"],
            },
            "candidate": {
                "label": "candidate",
                "commit": "3" * 40,
                "tree": "4" * 40,
                "library": self.files["candidate.so"],
                "cmakeCache": self.files["candidate-cache.txt"],
            },
        }
        comparison = {
            "sameCorpusRequired": True,
            "sameApprovedReplayerRequired": True,
            "sameCommandAfterRootNormalizationRequired": True,
            "sameBuildConfigAfterRootNormalizationRequired": True,
            "sourceRelationship": "common-base-with-exact-change-set",
            "sourceRelationshipValidationRequired": True,
            "contractFrozenBeforeAttemptTiming": True,
            "allowedDifferences": [
                "sourceCommit",
                "sourceTree",
                "dtvmLibrary",
            ],
        }
        workload = {
            "transactionCount": 136,
            "totalGasUsed": 16120,
            "rawBlockBytes": 4096,
            "bytecodeCount": 32,
            "forkBoundary": {
                "crossesKnownBoundary": False,
                "description": "No known boundary in fixture.",
            },
        }
        semantic_command_path = root / "semantic-validator-test-command.json"
        semantic_command_path.write_text(
            json.dumps(
                {
                    "schema": validator.TOOL_COMMAND_SCHEMA,
                    "role": "semanticValidator",
                    "argv": [
                        self.files["semantic-validator-test.py"]["path"],
                        "--fixture",
                        str(root),
                    ],
                    "cwd": str(root),
                    "environment": {
                        "LC_ALL": "C",
                        "PYTHONDONTWRITEBYTECODE": "1",
                    },
                    "expectedOutputs": [
                        self.files["semantic-validator-test.log"]["path"]
                    ],
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        self.files["semantic-validator-test-command.json"] = {
            "path": str(semantic_command_path),
            "sha256": sha256(semantic_command_path),
        }
        generator = {
            "sha256": evidence["semanticValidator"]["sha256"],
            "commandSha256": self.files[
                "semantic-validator-test-command.json"
            ]["sha256"],
            "testHarnessSha256": self.files[
                "semantic-validator-test.py"
            ]["sha256"],
            "testLogSha256": self.files["semantic-validator-test.log"][
                "sha256"
            ],
            "testCases": 3,
            "rerunVerified": True,
        }
        identity_document_inputs = {
            "approvedReplayerManifestSha256": evidence[
                "approvedReplayerManifest"
            ]["sha256"],
            "approvedReplayerBinarySha256": evidence[
                "approvedReplayerBinary"
            ]["sha256"],
            "baselineLibrarySha256": variants["baseline"]["library"]["sha256"],
            "candidateLibrarySha256": variants["candidate"]["library"]["sha256"],
            "baselineCmakeCacheSha256": variants["baseline"]["cmakeCache"][
                "sha256"
            ],
            "candidateCmakeCacheSha256": variants["candidate"]["cmakeCache"][
                "sha256"
            ],
            "baselineCommit": variants["baseline"]["commit"],
            "baselineTree": variants["baseline"]["tree"],
            "candidateCommit": variants["candidate"]["commit"],
            "candidateTree": variants["candidate"]["tree"],
        }
        identity_path = Path(evidence["identityProof"]["path"])
        identity_path.write_text(
            json.dumps(
                {
                    "schema": validator.IDENTITY_PROOF_SCHEMA,
                    "status": "passed",
                    "generator": generator,
                    "inputs": identity_document_inputs,
                    "normalized": {
                        "commandCanonicalSha256": "b" * 64,
                        "buildConfigCanonicalSha256": "c" * 64,
                        "environmentCanonicalSha256": "d" * 64,
                    },
                    "allowedDifferences": comparison["allowedDifferences"],
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        evidence["identityProof"]["sha256"] = sha256(identity_path)

        source_document_inputs = {
            "baselineCommit": variants["baseline"]["commit"],
            "baselineTree": variants["baseline"]["tree"],
            "candidateCommit": variants["candidate"]["commit"],
            "candidateTree": variants["candidate"]["tree"],
        }
        source_path = Path(evidence["sourceRelationProof"]["path"])
        source_path.write_text(
            json.dumps(
                {
                    "schema": validator.SOURCE_PROOF_SCHEMA,
                    "status": "passed",
                    "generator": generator,
                    "relationship": comparison["sourceRelationship"],
                    "inputs": source_document_inputs,
                    "commonBaseCommit": "5" * 40,
                    "sharedChangeSetSha256": "e" * 64,
                    "candidateOnlyChangeSha256": "f" * 64,
                    "effectiveDiffSha256": "0" * 64,
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        evidence["sourceRelationProof"]["sha256"] = sha256(source_path)

        correctness_inputs = {
            "corpusManifestSha256": evidence["corpusManifest"]["sha256"],
            "chainConfigSha256": evidence["chainConfig"]["sha256"],
            "baselineSealSha256": evidence["baselineSeal"]["sha256"],
            "candidateSealSha256": evidence["candidateSeal"]["sha256"],
            "correctnessSummarySha256": evidence["correctnessSummary"]["sha256"],
            "workloadCanonicalSha256": validator.canonical_sha256(workload),
        }
        identity_inputs = {
            "identityProofSha256": evidence["identityProof"]["sha256"],
            "approvedReplayerManifestSha256": evidence[
                "approvedReplayerManifest"
            ]["sha256"],
            "approvedReplayerBinarySha256": evidence["approvedReplayerBinary"][
                "sha256"
            ],
            "baselineLibrarySha256": variants["baseline"]["library"]["sha256"],
            "candidateLibrarySha256": variants["candidate"]["library"]["sha256"],
            "baselineCmakeCacheSha256": variants["baseline"]["cmakeCache"][
                "sha256"
            ],
            "candidateCmakeCacheSha256": variants["candidate"]["cmakeCache"][
                "sha256"
            ],
        }
        source_inputs = {
            "sourceRelationProofSha256": evidence["sourceRelationProof"][
                "sha256"
            ],
            "baselineCommit": variants["baseline"]["commit"],
            "baselineTree": variants["baseline"]["tree"],
            "candidateCommit": variants["candidate"]["commit"],
            "candidateTree": variants["candidate"]["tree"],
        }
        input_set = {
            "correctness": correctness_inputs,
            "identity": identity_inputs,
            "sourceRelation": source_inputs,
        }
        semantic_path = root / "semantic-validation.json"
        semantic_path.write_text(
            json.dumps(
                {
                    "schema": validator.SEMANTIC_SCHEMA,
                    "status": "passed",
                    "validatorSha256": evidence["semanticValidator"]["sha256"],
                    "inputSetCanonicalSha256": validator.canonical_sha256(
                        input_set
                    ),
                    "roles": {
                        "correctness": {
                            "status": "passed",
                            "inputs": correctness_inputs,
                        },
                        "identity": {
                            "status": "passed",
                            "inputs": identity_inputs,
                        },
                        "sourceRelation": {
                            "status": "passed",
                            "relationship": comparison["sourceRelationship"],
                            "inputs": source_inputs,
                        },
                    },
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        evidence["semanticValidation"] = {
            "path": str(semantic_path),
            "sha256": sha256(semantic_path),
        }
        self.files["semantic-validation.json"] = evidence["semanticValidation"]

        role_prefixes = {
            "semanticValidator": "semantic-validator",
            "runtimeRunner": "runtime-runner",
            "statisticsAnalyzer": "statistics-analyzer",
            "perfClassifier": "perf-classifier",
            "evidenceSealer": "evidence-sealer",
        }
        tooling: dict[str, Any] = {}
        tool_set: dict[str, Any] = {}
        for role, prefix in sorted(role_prefixes.items()):
            executable = self.files[prefix]
            harness = self.files[f"{prefix}-test.py"]
            log = self.files[f"{prefix}-test.log"]
            if role == "semanticValidator":
                command = self.files[
                    "semantic-validator-test-command.json"
                ]
            else:
                command_path = root / f"{prefix}-test-command.json"
                command_path.write_text(
                    json.dumps(
                        {
                            "schema": validator.TOOL_COMMAND_SCHEMA,
                            "role": role,
                            "argv": [str(harness), "--fixture", str(root)],
                            "cwd": str(root),
                            "environment": {
                                "LC_ALL": "C",
                                "PYTHONDONTWRITEBYTECODE": "1",
                            },
                            "expectedOutputs": [str(log)],
                        },
                        sort_keys=True,
                    )
                    + "\n",
                    encoding="utf-8",
                )
                command = {
                    "path": str(command_path),
                    "sha256": sha256(command_path),
                }
                self.files[f"{prefix}-test-command.json"] = command
            command_sha = command["sha256"]
            test_result_path = root / f"{prefix}-test-result.json"
            test_result_path.write_text(
                json.dumps(
                    {
                        "schema": validator.TOOL_TEST_SCHEMA,
                        "status": "passed",
                        "role": role,
                        "toolSha256": executable["sha256"],
                        "testHarnessSha256": harness["sha256"],
                        "testLogSha256": log["sha256"],
                        "commandSha256": command_sha,
                        "testCases": 3,
                        "testsPassed": 3,
                        "testsFailed": 0,
                        "rerunVerified": True,
                    },
                    sort_keys=True,
                )
                + "\n",
                encoding="utf-8",
            )
            test_result = {
                "path": str(test_result_path),
                "sha256": sha256(test_result_path),
            }
            self.files[f"{prefix}-test-result.json"] = test_result
            tooling[role] = {
                "executable": executable,
                "testCommand": command,
                "testHarness": harness,
                "testLog": log,
                "testResult": test_result,
            }
            tool_set[role] = {
                "status": "passed",
                "sha256": executable["sha256"],
                "testHarnessSha256": harness["sha256"],
                "testLogSha256": log["sha256"],
                "testResultSha256": test_result["sha256"],
                "commandSha256": command_sha,
                "testCases": 3,
                "testsPassed": 3,
                "testsFailed": 0,
                "rerunVerified": True,
            }
        tooling_validation_path = root / "tooling-validation.json"
        tooling_validation_path.write_text(
            json.dumps(
                {
                    "schema": validator.TOOLING_SCHEMA,
                    "status": "passed",
                    "toolSetCanonicalSha256": validator.canonical_sha256(
                        tool_set
                    ),
                    "tools": tool_set,
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        tooling["validation"] = {
            "path": str(tooling_validation_path),
            "sha256": sha256(tooling_validation_path),
        }
        self.files["tooling-validation.json"] = tooling["validation"]

        self.contract: dict[str, Any] = {
            "schema": validator.SCHEMA,
            "purpose": purpose,
            "window": {
                "chainId": "0x1",
                "startBlock": 25625000,
                "endBlock": 25625015,
                "blockCount": 16,
            },
            "workload": workload,
            "evidence": evidence,
            "variants": variants,
            "comparison": comparison,
            "correctnessRequirements": {
                "requireStrictReplayBothVariants": True,
                "requireAllDifferentialMatches": True,
                "requireAllPreStateRootsVerified": True,
                "requireAllPostStateRootsVerified": True,
                "requireOfflineNetworkDenial": True,
                "requireNoRecordedCredentials": True,
            },
            "isolation": {
                "networkDisabled": True,
                "proxyDisabled": True,
                "downloadsDisabled": True,
                "rethStopped": True,
                "formalStagesSerialized": True,
            },
            "runtime": {
                "design": "balanced-adjacent-paired-fresh-process",
                "measurementUnit": "full-window-round",
                "processGranularity": "one-block",
                "warmupRounds": 2,
                "warmupSchedule": ["AB", "BA"],
                "measuredRounds": rounds,
                "schedule": schedule,
                "cpu": {
                    "logicalCpu": 50,
                    "smtSiblingPolicy": "idle-or-offline",
                    "maxBusyPercent": 5.0,
                    "sampleWindowSeconds": 2.0,
                    "consecutiveQuietWindows": 2,
                    "quietBeforeEachBlockPair": True,
                    "quietAfterRun": True,
                },
                "networkDisabled": True,
                "dropKernelCaches": False,
                "stopOnCorrectnessFailure": True,
                "retainRawSamples": True,
                "primaryStatistic": "median-paired-full-window-relative-delta",
                "confidence": {
                    "method": "paired-bootstrap",
                    "level": 0.95,
                    "seed": 577,
                    "resamples": 10000,
                },
                "minimumPracticalEffectPercent": 0.5,
                "maxRoundCvPercent": 5.0,
            },
            "profiling": {
                "enabled": True,
                "selectionFrozenBeforeAttemptProfiling": True,
                "representativeBlocks": [
                    {
                        "role": "highest-gas",
                        "blockNumber": 25625015,
                        "blockHash": f"0x{25625015:064x}",
                    },
                    {
                        "role": "median-gas",
                        "blockNumber": 25625007,
                        "blockHash": f"0x{25625007:064x}",
                    },
                ],
                "statEvents": sorted(validator.EXPECTED_STAT_EVENTS),
                "recordEvent": "cycles",
                "recordEventScope": "user-and-kernel",
                "frequencyHz": 997,
                "callGraph": "dwarf",
                "processWide": True,
                "inheritChildren": True,
                "freshProcess": True,
                "passesPerVariantPerBlock": 2,
                "balancedOrder": True,
                "recordRunsExcludedFromRuntime": True,
                "memfdSymbolizationRequired": True,
                "dtvmBuildIdMatchRequired": True,
                "attemptLocalSymfsRequired": True,
                "symbolizedSelfAndInclusiveReportsRequired": True,
                "unresolvedDtvmAllowed": False,
                "classifications": sorted(validator.EXPECTED_CLASSES),
            },
            "coldCompile": {
                "enabled": False,
                "reason": "Runtime attribution is sufficient.",
            },
            "sourceTrace": {
                "skill": "dtvm-compiler-path-analysis",
                "requiredForCompilerHotspot": True,
                "requiredBeforeSourceEdit": True,
            },
            "tooling": tooling,
            "output": {
                "attemptRoot": str(root / "attempts"),
                "attemptId": "fixed16-formal-r20",
                "contractPath": str(
                    root
                    / "attempts"
                    / "fixed16-formal-r20"
                    / "comparison-contract.json"
                ),
                "contractValidationPath": str(
                    root
                    / "attempts"
                    / "fixed16-formal-r20"
                    / "comparison-contract.validation.json"
                ),
                "refuseOverwrite": True,
                "evidenceSealRequired": True,
                "checksumManifest": "SHA256SUMS",
                "reportSkill": "dtvm-write-report",
                "claimRule": "formal-only-after-all-gates",
            },
        }
        self.contract_path = Path(self.contract["output"]["contractPath"])
        self.contract_path.parent.mkdir(parents=True)
        self.write()

    def write(self) -> None:
        self.contract_path.write_text(
            json.dumps(self.contract, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )

    def rewrite_bound_json(
        self, binding: dict[str, str], mutate: Any
    ) -> None:
        path = Path(binding["path"])
        value = json.loads(path.read_text(encoding="utf-8"))
        mutate(value)
        path.write_text(
            json.dumps(value, sort_keys=True) + "\n", encoding="utf-8"
        )
        binding["sha256"] = sha256(path)
        self.write()

    def run(self, output: Path | None = None) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(SCRIPT), str(self.contract_path)]
        if output is not None:
            command += ["--output", str(output)]
        return subprocess.run(
            command,
            text=True,
            capture_output=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            check=False,
        )


class ContractValidatorTests(unittest.TestCase):
    def test_formal_forward_fixture_passes_and_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            first = fixture.run()
            second = fixture.run()
            self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
            self.assertEqual(first.stdout, second.stdout)
            report = json.loads(first.stdout)
            self.assertEqual(report["status"], "valid")
            self.assertEqual(report["purpose"], "formal")
            self.assertEqual(report["semanticValidationStatus"], "passed")
            self.assertEqual(report["toolingValidationStatus"], "passed")
            self.assertEqual(len(report["filesVerified"]), 41)
            self.assertEqual(report["errors"], [])

    def test_diagnostic_seven_round_fixture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp), purpose="diagnostic")
            result = fixture.run()
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_formal_seven_round_contract_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["measuredRounds"] = 7
            fixture.contract["runtime"]["schedule"] = [
                "AB",
                "BA",
                "AB",
                "BA",
                "AB",
                "BA",
                "AB",
            ]
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            report = json.loads(result.stdout)
            self.assertIn(
                "runtime.measuredRounds: must be at least 20", report["errors"]
            )

    def test_block_samples_cannot_replace_full_window_unit(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["measurementUnit"] = "block-pair"
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("full-window-round", result.stdout)

    def test_unbalanced_schedule_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["schedule"] = ["AB"] * 20
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("counts may differ by at most one", result.stdout)

    def test_balanced_but_non_alternating_schedule_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["schedule"] = ["AB"] * 10 + ["BA"] * 10
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("must alternate AB, BA", result.stdout)

    def test_warmup_schedule_is_two_balanced_full_windows(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["warmupRounds"] = 1
            fixture.contract["runtime"]["warmupSchedule"] = ["AB"]
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("runtime.warmupRounds", result.stdout)
            self.assertIn("runtime.warmupSchedule", result.stdout)

    def test_practical_threshold_is_exactly_half_percent(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["minimumPracticalEffectPercent"] = 0.0
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("must equal 0.5", result.stdout)

    def test_quiet_gate_is_required_before_each_block_pair(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["runtime"]["cpu"][
                "quietBeforeEachBlockPair"
            ] = False
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "runtime.cpu.quietBeforeEachBlockPair", result.stdout
            )

    def test_workload_fork_boundary_description_is_required(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["workload"]["forkBoundary"]["description"] = ""
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "workload.forkBoundary.description", result.stdout
            )

    def test_old_self_asserted_comparison_fields_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["comparison"]["sameCorpus"] = True
            fixture.contract["comparison"][
                "contractFrozenBeforeCandidateTiming"
            ] = True
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("unknown key 'sameCorpus'", result.stdout)
            self.assertIn(
                "unknown key 'contractFrozenBeforeCandidateTiming'",
                result.stdout,
            )

    def test_non_representative_perf_block_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["profiling"]["representativeBlocks"][0][
                "blockNumber"
            ] = 25625014
            fixture.contract["profiling"]["representativeBlocks"][0][
                "blockHash"
            ] = f"0x{25625014:064x}"
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "highest-gas must bind manifest block", result.stdout
            )

    def test_user_only_perf_event_cannot_claim_kernel_share(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["profiling"]["recordEvent"] = "cycles:u"
            fixture.contract["profiling"]["recordEventScope"] = "user-only"
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("profiling.recordEvent", result.stdout)
            self.assertIn("profiling.recordEventScope", result.stdout)

    def test_unresolved_dtvm_is_forbidden(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["profiling"]["unresolvedDtvmAllowed"] = True
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("profiling.unresolvedDtvmAllowed", result.stdout)

    def test_pre_timing_build_id_result_assertion_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["profiling"][
                "dtvmBuildIdMatchesFrozenLibrary"
            ] = True
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "unknown key 'dtvmBuildIdMatchesFrozenLibrary'",
                result.stdout,
            )

    def test_post_run_symbolized_reports_are_requirements(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["profiling"][
                "symbolizedSelfAndInclusiveReportsRequired"
            ] = False
            fixture.contract["profiling"][
                "symbolizedSelfAndInclusiveReports"
            ] = True
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "profiling.symbolizedSelfAndInclusiveReportsRequired",
                result.stdout,
            )
            self.assertIn(
                "unknown key 'symbolizedSelfAndInclusiveReports'",
                result.stdout,
            )

    def test_semantic_status_must_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.rewrite_bound_json(
                fixture.contract["evidence"]["semanticValidation"],
                lambda value: value.__setitem__("status", "failed"),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("semanticValidation.status", result.stdout)

    def test_semantic_validation_is_mandatory(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            del fixture.contract["evidence"]["semanticValidation"]
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "evidence: missing key 'semanticValidation'", result.stdout
            )

    def test_chain_config_binding_is_mandatory(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            del fixture.contract["evidence"]["chainConfig"]
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("evidence: missing key 'chainConfig'", result.stdout)

    def test_each_semantic_role_must_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))

            def mutate(value: dict[str, Any]) -> None:
                value["roles"]["identity"]["status"] = "failed"

            fixture.rewrite_bound_json(
                fixture.contract["evidence"]["semanticValidation"], mutate
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "semanticValidation.roles.identity.status", result.stdout
            )

    def test_semantic_validator_hash_must_match_bound_tool(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            semantic_tool = Path(
                fixture.contract["evidence"]["semanticValidator"]["path"]
            )
            semantic_tool.write_text("changed validator\n", encoding="utf-8")
            semantic_tool.chmod(0o700)
            fixture.contract["evidence"]["semanticValidator"][
                "sha256"
            ] = sha256(semantic_tool)
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("semanticValidation.validatorSha256", result.stdout)

    def test_semantic_role_input_digest_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))

            def mutate(value: dict[str, Any]) -> None:
                value["roles"]["correctness"]["inputs"][
                    "baselineSealSha256"
                ] = "0" * 64

            fixture.rewrite_bound_json(
                fixture.contract["evidence"]["semanticValidation"], mutate
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "semanticValidation.roles.correctness.inputs", result.stdout
            )

    def test_identity_proof_schema_is_normative(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.rewrite_bound_json(
                fixture.contract["evidence"]["identityProof"],
                lambda value: value.__setitem__("schema", "ad-hoc.v1"),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("identityProof.schema", result.stdout)

    def test_source_relationship_must_match_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.rewrite_bound_json(
                fixture.contract["evidence"]["sourceRelationProof"],
                lambda value: value.__setitem__(
                    "relationship", "candidate-descends-from-baseline"
                ),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("sourceRelationProof.relationship", result.stdout)

    def test_proof_generator_must_match_semantic_tool_test_package(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.rewrite_bound_json(
                fixture.contract["evidence"]["identityProof"],
                lambda value: value["generator"].__setitem__(
                    "commandSha256", "9" * 64
                ),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("identityProof.generator", result.stdout)

    def test_tooling_validation_status_must_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.rewrite_bound_json(
                fixture.contract["tooling"]["validation"],
                lambda value: value.__setitem__("status", "failed"),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("toolingValidation.status", result.stdout)

    def test_tooling_hash_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            runner = Path(
                fixture.contract["tooling"]["runtimeRunner"]["executable"][
                    "path"
                ]
            )
            runner.write_text("changed runner\n", encoding="utf-8")
            runner.chmod(0o700)
            fixture.contract["tooling"]["runtimeRunner"]["executable"][
                "sha256"
            ] = sha256(runner)
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "toolingValidation.toolSetCanonicalSha256", result.stdout
            )

    def test_tooling_must_be_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            runner = Path(
                fixture.contract["tooling"]["runtimeRunner"]["executable"][
                    "path"
                ]
            )
            runner.chmod(0o600)
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("executable tool required", result.stdout)

    def test_tool_test_clean_rerun_is_required(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.rewrite_bound_json(
                fixture.contract["tooling"]["runtimeRunner"]["testResult"],
                lambda value: value.__setitem__("rerunVerified", False),
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "runtimeRunner.testResultDocument.rerunVerified",
                result.stdout,
            )

    def test_actual_tool_command_document_is_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            binding = fixture.contract["tooling"]["runtimeRunner"][
                "testCommand"
            ]
            command = Path(binding["path"])
            value = json.loads(command.read_text(encoding="utf-8"))
            value["argv"].append("--changed")
            command.write_text(
                json.dumps(value, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            binding["sha256"] = sha256(command)
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "runtimeRunner.testResultDocument.commandSha256",
                result.stdout,
            )

    def test_tool_test_harness_digest_is_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            binding = fixture.contract["tooling"]["runtimeRunner"][
                "testHarness"
            ]
            harness = Path(binding["path"])
            harness.write_text("changed harness\n", encoding="utf-8")
            harness.chmod(0o700)
            binding["sha256"] = sha256(harness)
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "runtimeRunner.testResultDocument.testHarnessSha256",
                result.stdout,
            )

    def test_hash_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            Path(fixture.files["manifest.json"]["path"]).write_text(
                "drift\n", encoding="utf-8"
            )
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("content mismatch", result.stdout)

    def test_symlink_artifact_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            alias = Path(temp) / "manifest-link.json"
            alias.symlink_to(fixture.files["manifest.json"]["path"])
            fixture.contract["evidence"]["corpusManifest"] = {
                "path": str(alias),
                "sha256": fixture.files["manifest.json"]["sha256"],
            }
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("canonical realpath required", result.stdout)

    def test_output_is_no_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            output = Path(
                fixture.contract["output"]["contractValidationPath"]
            )
            first = fixture.run(output)
            second = fixture.run(output)
            self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
            self.assertEqual(second.returncode, 2)
            self.assertIn("File exists", second.stderr)

    def test_contract_must_be_stored_in_attempt_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            fixture.contract["output"]["contractPath"] = str(
                Path(temp) / "outside.json"
            )
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("output.contractPath", result.stdout)

    def test_validation_output_must_be_attempt_local(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            result = fixture.run(Path(temp) / "outside-validation.json")
            self.assertEqual(result.returncode, 2)
            self.assertIn(
                "--output must equal output.contractValidationPath",
                result.stderr,
            )

    def test_enabled_cold_compile_requires_balanced_twenty_pairs(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            fixture = Fixture(Path(temp))
            schedule = ["AB" if index % 2 == 0 else "BA" for index in range(20)]
            fixture.contract["coldCompile"] = {
                "enabled": True,
                "runnerSkill": "dtvm-cold-compile-profile",
                "inputSelection": (
                    "largest-nonempty-witness-code-deterministic-tiebreak"
                ),
                "freshProcess": True,
                "productionTimingSeparated": True,
                "measuredPairs": 20,
                "schedule": schedule,
                "oneShotProfilesPerVariant": 1,
            }
            fixture.write()
            result = fixture.run()
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
