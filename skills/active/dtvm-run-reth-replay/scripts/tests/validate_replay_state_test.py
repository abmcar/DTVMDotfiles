#!/usr/bin/env python3
"""Focused fixed/finalized dispatch tests for validate-replay-state.py."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_sha256(value: Any) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, sort_keys=True), encoding="utf-8")


def invoke(validator: Path, state_dir: Path) -> tuple[int, dict[str, Any]]:
    process = subprocess.run(
        [sys.executable, str(validator), str(state_dir)],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    return process.returncode, json.loads(process.stdout)


def expect(
    validator: Path,
    state_dir: Path,
    status: str,
    category: str | None = None,
) -> None:
    returncode, result = invoke(validator, state_dir)
    assert result["status"] == status, result
    if status == "verified":
        assert returncode == 0, result
    else:
        assert returncode != 0, result
        assert result["failureCategory"] == category, result


def main() -> int:
    skill_root = Path(__file__).resolve().parents[2]
    validator = Path(
        os.environ.get(
            "DTVM_REPLAY_STATE_VALIDATOR",
            skill_root / "scripts" / "validate-replay-state.py",
        )
    )
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        state_dir = root / "state"
        state_dir.mkdir()
        binary = root / "replay-block"
        binary.write_bytes(b"approved-replayer")
        binary.chmod(0o700)
        approval = root / "approved-replayer.json"
        write_json(approval, {"approved": True})
        approved = {
            "role": "downstream_replayer_identity",
            "manifestRealpath": str(approval),
            "manifestSha256": sha256(approval),
            "replayer": {
                "realpath": str(binary),
                "sha256": sha256(binary),
            },
        }
        metrics = {
            "schema": "reth-dtvm.rpc-ha-metrics.v1",
            "secretMaterialRecorded": False,
        }
        write_json(state_dir / "metrics.json", metrics)

        selection = {
            "mode": "exact_fixed_range",
            "startNumber": 25625000,
            "startNumberHex": "0x18701a8",
            "endNumber": 25625000,
            "endNumberHex": "0x18701a8",
            "count": 1,
        }
        ordered = [
            {
                "number": 25625000,
                "numberHex": "0x18701a8",
                "hash": "0x" + "12" * 32,
            }
        ]
        frozen = {
            "requestedSelection": selection,
            "range": {
                "firstNumber": 25625000,
                "firstNumberHex": "0x18701a8",
                "lastNumber": 25625000,
                "lastNumberHex": "0x18701a8",
            },
            "rangeAnchor": {
                "number": 25625000,
                "numberHex": "0x18701a8",
                "hash": ordered[0]["hash"],
                "agreedEndpoints": ["primary", "standby"],
            },
            "orderedHeightHashes": ordered,
            "orderedCommitmentSha256": canonical_sha256(ordered),
        }
        readiness = {
            "schema": "reth-dtvm.rpc-ha-fixed-range-readiness.v1",
            "status": "ready",
            "success": True,
            "requestedSelection": selection,
            "frozenPin": None,
            "frozenRange": frozen,
            "oldestWitnessReadiness": {
                "number": ordered[0]["number"],
                "numberHex": ordered[0]["numberHex"],
                "hash": ordered[0]["hash"],
                "method": "debug_executionWitnessByBlockHash",
                "mode": "canonical",
                "required": 2,
                "readyEndpoints": ["primary", "standby"],
                "satisfied": True,
                "endpoints": [
                    {
                        "name": "primary",
                        "role": "witness-primary",
                        "ready": True,
                        "failureCategory": None,
                    },
                    {
                        "name": "standby",
                        "role": "witness-standby",
                        "ready": True,
                        "failureCategory": None,
                    },
                ],
                "failures": [],
            },
            "secretMaterialRecorded": False,
        }
        readiness_path = state_dir / "readiness.json"
        write_json(readiness_path, readiness)
        fixed_state = {
            "schema": "reth-dtvm.rpc-ha-fixed-range-resume-state.v2",
            "status": "in_progress",
            "phase": "ready",
            "configFingerprint": "34" * 32,
            "requestedTag": None,
            "requestedCount": 1,
            "requestedSelection": selection,
            "frozenRange": frozen,
            "readinessSha256": sha256(readiness_path),
            "preCaptureOrderedHeightHashes": None,
            "postCaptureOrderedHeightHashes": None,
            "preCaptureOrderedCommitmentSha256": None,
            "postCaptureOrderedCommitmentSha256": None,
            "orderedBlockCommitmentSha256": None,
            "output": str(root / "fixed-corpus"),
            "networkCaptureCompleted": False,
            "strictReplayCompleted": False,
            "evidenceSealed": False,
            "credentialsRecorded": False,
            "approvedReplayer": approved,
        }
        state_path = state_dir / "resume-state.json"
        write_json(state_path, fixed_state)
        expect(validator, state_dir, "verified")

        malformed_selection = json.loads(json.dumps(fixed_state))
        malformed_selection["requestedSelection"]["endNumberHex"] = "0x0"
        write_json(state_path, malformed_selection)
        expect(
            validator,
            state_dir,
            "failure",
            "fixed_range_state_contract_failed",
        )

        write_json(state_path, fixed_state)
        changed_readiness = json.loads(json.dumps(readiness))
        changed_readiness["status"] = "not_ready"
        write_json(readiness_path, changed_readiness)
        expect(
            validator,
            state_dir,
            "failure",
            "fixed_range_readiness_evidence_failed",
        )

        write_json(readiness_path, changed_readiness)
        changed_contract = json.loads(json.dumps(fixed_state))
        changed_contract["readinessSha256"] = sha256(readiness_path)
        write_json(state_path, changed_contract)
        expect(
            validator,
            state_dir,
            "failure",
            "fixed_range_readiness_contract_failed",
        )

        changed_oldest = json.loads(json.dumps(readiness))
        changed_oldest["oldestWitnessReadiness"]["hash"] = "0x" + "99" * 32
        write_json(readiness_path, changed_oldest)
        changed_contract = json.loads(json.dumps(fixed_state))
        changed_contract["readinessSha256"] = sha256(readiness_path)
        write_json(state_path, changed_contract)
        expect(
            validator,
            state_dir,
            "failure",
            "fixed_range_readiness_contract_failed",
        )

        write_json(readiness_path, readiness)
        output = root / "fixed-corpus"
        bundles = output / "bundles"
        bundles.mkdir(parents=True)
        bundle = bundles / "block.json"
        bundle.write_bytes(b"fixed-range-bundle")
        bundle_sha256 = sha256(bundle)
        block = {
            "number": 25625000,
            "numberHex": "0x18701a8",
            "hash": ordered[0]["hash"],
            "parentHash": "0x" + "11" * 32,
            "bundle": "bundles/block.json",
            "bundleSha256": bundle_sha256,
        }
        manifest = {
            "schema": "reth-dtvm.atomic-fixed-range-capture.v1",
            "success": True,
            "requestedTag": None,
            "pinnedHead": None,
            "requestedSelection": selection,
            "count": 1,
            "range": frozen["range"],
            "rangeAnchor": {
                key: value
                for key, value in frozen["rangeAnchor"].items()
                if key != "agreedEndpoints"
            },
            "witness": {
                "method": "debug_executionWitnessByBlockHash",
                "mode": "canonical",
                "policy": "production",
            },
            "canonicalRecheck": {
                "beforeCapture": {
                    "phase": "before_capture",
                    "checkedCount": 1,
                    "orderedHeightHashes": ordered,
                    "orderedCommitmentSha256": canonical_sha256(ordered),
                },
                "afterCapture": {
                    "phase": "after_capture",
                    "checkedCount": 1,
                    "orderedHeightHashes": ordered,
                    "orderedCommitmentSha256": canonical_sha256(ordered),
                },
                "allOrderedHashesUnchanged": True,
            },
            "orderedBlockCommitmentSha256": canonical_sha256(
                [{"number": block["number"], "hash": block["hash"]}]
            ),
            "replayerIdentity": approved,
            "blocks": [block],
            "rpcUrlRecorded": False,
        }
        manifest_path = output / "manifest.json"
        write_json(manifest_path, manifest)
        checksum_lines = f"{bundle_sha256}  bundles/block.json\n".encode()
        (output / "BUNDLE_SHA256SUMS").write_bytes(checksum_lines)
        checksums = {
            "schema": "reth-dtvm.bundle-checksums.v1",
            "blockCount": 1,
            "bundles": [
                {
                    "number": block["number"],
                    "hash": block["hash"],
                    "path": block["bundle"],
                    "sha256": bundle_sha256,
                }
            ],
            "bundleSetSha256": hashlib.sha256(checksum_lines).hexdigest(),
            "manifestSha256": sha256(manifest_path),
        }
        checksums_path = output / "bundle-checksums.json"
        write_json(checksums_path, checksums)

        verify_script = root / "verify-corpus.sh"
        verify_script.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        verify_script.chmod(0o700)
        library = root / "libdtvmapi.so"
        library.write_bytes(b"fixed-library")
        replay_output = root / "fixed-replay"
        replay_output.mkdir()
        replay_result = {
            "schema": "reth-dtvm.corpus-correctness.v1",
            "corpus": {
                "manifestSha256": sha256(manifest_path),
                "blockCount": 1,
            },
            "dtvm": {
                "librarySha256": sha256(library),
                "loadedFromVerifiedSealedMemfd": True,
            },
            "replayer": approved["replayer"],
            "correctness": {
                "passed": True,
                "blockResults": [
                    {
                        "blockNumber": block["number"],
                        "blockHash": block["hash"],
                        "bundle": block["bundle"],
                        "bundleSha256": bundle_sha256,
                        "correctnessPassed": True,
                        "differentialMatch": True,
                        "rawBound": True,
                        "preExecutionCommitments": True,
                        "preStateRootVerified": True,
                        "postStateRootVerified": True,
                        "postExecutionCommitments": {
                            "gasUsed": True,
                            "receiptsRoot": True,
                            "logsBloom": True,
                            "requestsHash": True,
                            "blobGasUsed": True,
                        },
                    }
                ],
            },
            "timingQualification": {
                "excludesFromFormalPr577PerformanceConclusion": True
            },
        }
        replay_result_path = replay_output / "result.json"
        write_json(replay_result_path, replay_result)
        isolation = {
            "schema": "libseccomp-deny-network-syscalls.v1",
            "runnerRealpath": str(validator),
            "runnerSha256": sha256(validator),
            "deniedSyscalls": [
                "socket",
                "socketpair",
                "connect",
                "bind",
                "listen",
                "accept",
                "accept4",
                "sendto",
                "sendmsg",
                "recvfrom",
                "recvmsg",
                "shutdown",
                "io_uring_setup",
                "io_uring_enter",
                "io_uring_register",
            ],
        }
        sealed_state = {
            **fixed_state,
            "status": "success",
            "phase": "sealed",
            "preCaptureOrderedHeightHashes": ordered,
            "postCaptureOrderedHeightHashes": ordered,
            "preCaptureOrderedCommitmentSha256": canonical_sha256(ordered),
            "postCaptureOrderedCommitmentSha256": canonical_sha256(ordered),
            "orderedBlockCommitmentSha256": manifest[
                "orderedBlockCommitmentSha256"
            ],
            "output": str(output),
            "manifestSha256": sha256(manifest_path),
            "bundleSetSha256": checksums["bundleSetSha256"],
            "networkCaptureCompleted": True,
            "strictReplayCompleted": True,
            "networkExcludedFromReplay": True,
            "replayOutput": str(replay_output),
            "replayResultSha256": sha256(replay_result_path),
            "verifyCorpusScript": str(verify_script),
            "verifyCorpusSha256": sha256(verify_script),
            "dtvmLibrary": str(library),
            "dtvmLibrarySha256": sha256(library),
            "offlineReplayIsolation": isolation,
            "evidenceSealed": True,
        }
        preseal = {
            **sealed_state,
            "phase": "replayed",
            "evidenceSealed": False,
        }
        preseal_path = state_dir / "resume-state-before-seal.json"
        write_json(preseal_path, preseal)
        seal_inputs = [
            ("capture_manifest", manifest_path),
            ("readiness_report", readiness_path),
            ("bundle_checksums", checksums_path),
            ("resume_state_before_seal", preseal_path),
            ("strict_replay_runner", verify_script),
            ("dtvm_library", library),
            ("approved_replayer", binary),
            ("offline_replay_launcher", validator),
            ("rpc_metrics", state_dir / "metrics.json"),
            ("strict_replay_result", replay_result_path),
        ]
        seal = {
            "schema": "reth-dtvm.rpc-ha-fixed-range-evidence-seal.v1",
            "status": "sealed",
            "sealedAtUtc": "2026-07-29T00:00:00Z",
            "configFingerprint": sealed_state["configFingerprint"],
            "requestedSelection": selection,
            "frozenRange": frozen,
            "readinessSha256": sha256(readiness_path),
            "networkCaptureCompleted": True,
            "strictReplayCompleted": True,
            "networkExcludedFromReplay": True,
            "inputs": [
                {"role": role, "path": str(path), "sha256": sha256(path)}
                for role, path in seal_inputs
            ],
            "metrics": metrics,
            "credentialsRecorded": False,
        }
        seal_path = state_dir / "evidence-seal.json"
        write_json(seal_path, seal)
        sealed_state["evidenceSeal"] = str(seal_path)
        sealed_state["evidenceSealSha256"] = sha256(seal_path)
        write_json(state_path, sealed_state)
        expect(validator, state_dir, "verified")

        forged_state_dir = root / "forged-state"
        forged_state_dir.mkdir()
        write_json(forged_state_dir / "metrics.json", metrics)
        forged_selection = {
            "mode": "exact_fixed_range",
            "startNumber": 25625000,
            "startNumberHex": "0x18701a8",
            "endNumber": 25625002,
            "endNumberHex": "0x18701aa",
            "count": 3,
        }
        frozen_order = [
            {
                "number": 25625000 + index,
                "numberHex": f"0x{25625000 + index:x}",
                "hash": "0x" + f"{0x20 + index:02x}" * 32,
            }
            for index in range(3)
        ]
        forged_frozen = {
            "requestedSelection": forged_selection,
            "range": {
                "firstNumber": 25625000,
                "firstNumberHex": "0x18701a8",
                "lastNumber": 25625002,
                "lastNumberHex": "0x18701aa",
            },
            "rangeAnchor": {
                "number": 25625002,
                "numberHex": "0x18701aa",
                "hash": frozen_order[-1]["hash"],
                "agreedEndpoints": ["primary", "standby"],
            },
            "orderedHeightHashes": frozen_order,
            "orderedCommitmentSha256": canonical_sha256(frozen_order),
        }
        forged_readiness = {
            **readiness,
            "requestedSelection": forged_selection,
            "frozenRange": forged_frozen,
            "oldestWitnessReadiness": {
                **readiness["oldestWitnessReadiness"],
                "number": frozen_order[0]["number"],
                "numberHex": frozen_order[0]["numberHex"],
                "hash": frozen_order[0]["hash"],
            },
        }
        forged_readiness_path = forged_state_dir / "readiness.json"
        write_json(forged_readiness_path, forged_readiness)
        forged_output = root / "forged-corpus"
        forged_bundles = forged_output / "bundles"
        forged_bundles.mkdir(parents=True)
        manifest_hashes = [
            frozen_order[0]["hash"],
            "0x" + "99" * 32,
            frozen_order[2]["hash"],
        ]
        forged_blocks: list[dict[str, Any]] = []
        for index, block_hash in enumerate(manifest_hashes):
            bundle_path = forged_bundles / f"block-{index}.json"
            bundle_path.write_bytes(f"bundle-{index}".encode())
            forged_blocks.append(
                {
                    "number": 25625000 + index,
                    "numberHex": f"0x{25625000 + index:x}",
                    "hash": block_hash,
                    "parentHash": (
                        "0x" + "10" * 32
                        if index == 0
                        else manifest_hashes[index - 1]
                    ),
                    "bundle": f"bundles/block-{index}.json",
                    "bundleSha256": sha256(bundle_path),
                }
            )
        forged_block_identities = [
            {
                "number": block["number"],
                "hash": block["hash"],
            }
            for block in forged_blocks
        ]
        forged_manifest = {
            "schema": "reth-dtvm.atomic-fixed-range-capture.v1",
            "success": True,
            "requestedTag": None,
            "pinnedHead": None,
            "requestedSelection": forged_selection,
            "count": 3,
            "range": forged_frozen["range"],
            "rangeAnchor": {
                key: value
                for key, value in forged_frozen["rangeAnchor"].items()
                if key != "agreedEndpoints"
            },
            "witness": {
                "method": "debug_executionWitnessByBlockHash",
                "mode": "canonical",
                "policy": "production",
            },
            "canonicalRecheck": {
                "beforeCapture": {
                    "phase": "before_capture",
                    "checkedCount": 3,
                    "orderedHeightHashes": frozen_order,
                    "orderedCommitmentSha256": canonical_sha256(frozen_order),
                },
                "afterCapture": {
                    "phase": "after_capture",
                    "checkedCount": 3,
                    "orderedHeightHashes": frozen_order,
                    "orderedCommitmentSha256": canonical_sha256(frozen_order),
                },
                "allOrderedHashesUnchanged": True,
            },
            "orderedBlockCommitmentSha256": canonical_sha256(
                forged_block_identities
            ),
            "replayerIdentity": approved,
            "blocks": forged_blocks,
            "rpcUrlRecorded": False,
        }
        forged_manifest_path = forged_output / "manifest.json"
        write_json(forged_manifest_path, forged_manifest)
        forged_checksum_lines = "".join(
            f"{block['bundleSha256']}  {block['bundle']}\n"
            for block in sorted(
                forged_blocks,
                key=lambda item: item["bundle"],
            )
        ).encode()
        (forged_output / "BUNDLE_SHA256SUMS").write_bytes(
            forged_checksum_lines
        )
        forged_checksums = {
            "schema": "reth-dtvm.bundle-checksums.v1",
            "blockCount": 3,
            "bundles": [
                {
                    "number": block["number"],
                    "hash": block["hash"],
                    "path": block["bundle"],
                    "sha256": block["bundleSha256"],
                }
                for block in forged_blocks
            ],
            "bundleSetSha256": hashlib.sha256(
                forged_checksum_lines
            ).hexdigest(),
            "manifestSha256": sha256(forged_manifest_path),
        }
        write_json(
            forged_output / "bundle-checksums.json",
            forged_checksums,
        )
        forged_state = {
            **fixed_state,
            "status": "success",
            "phase": "published",
            "requestedCount": 3,
            "requestedSelection": forged_selection,
            "frozenRange": forged_frozen,
            "readinessSha256": sha256(forged_readiness_path),
            "preCaptureOrderedHeightHashes": frozen_order,
            "postCaptureOrderedHeightHashes": frozen_order,
            "preCaptureOrderedCommitmentSha256": canonical_sha256(
                frozen_order
            ),
            "postCaptureOrderedCommitmentSha256": canonical_sha256(
                frozen_order
            ),
            "orderedBlockCommitmentSha256": forged_manifest[
                "orderedBlockCommitmentSha256"
            ],
            "output": str(forged_output),
            "manifestSha256": sha256(forged_manifest_path),
            "bundleSetSha256": forged_checksums["bundleSetSha256"],
            "networkCaptureCompleted": True,
        }
        write_json(forged_state_dir / "resume-state.json", forged_state)
        expect(
            validator,
            forged_state_dir,
            "failure",
            "fixed_range_capture_identity_failed",
        )

        changed_seal = json.loads(json.dumps(seal))
        changed_seal["readinessSha256"] = "78" * 32
        write_json(seal_path, changed_seal)
        changed_sealed_state = json.loads(json.dumps(sealed_state))
        changed_sealed_state["evidenceSealSha256"] = sha256(seal_path)
        write_json(state_path, changed_sealed_state)
        expect(
            validator,
            state_dir,
            "failure",
            "fixed_range_seal_contract_failed",
        )

        write_json(readiness_path, readiness)
        finalized_state = {
            "schema": "reth-dtvm.rpc-ha-resume-state.v1",
            "status": "in_progress",
            "phase": "initializing",
            "configFingerprint": "56" * 32,
            "requestedTag": "finalized",
            "requestedCount": 1,
            "frozenPin": None,
            "output": str(root / "finalized-corpus"),
            "networkCaptureCompleted": False,
            "strictReplayCompleted": False,
            "evidenceSealed": False,
            "credentialsRecorded": False,
            "approvedReplayer": approved,
        }
        write_json(state_path, finalized_state)
        expect(validator, state_dir, "verified")

    print("validate-replay-state dispatch regressions: 9/9")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
