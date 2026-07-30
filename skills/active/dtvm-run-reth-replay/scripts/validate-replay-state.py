#!/usr/bin/env python3
"""Validate a DTVM–Reth resume directory without reading endpoint secrets."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


HASH = re.compile(r"^[0-9a-f]{64}$")
BLOCK_HASH = re.compile(r"^0x[0-9a-fA-F]{64}$")
QUANTITY = re.compile(r"^0x(?:0|[1-9a-f][0-9a-f]*)$")
SCHEMA_STATE = "reth-dtvm.rpc-ha-resume-state.v1"
SCHEMA_FIXED_STATE = "reth-dtvm.rpc-ha-fixed-range-resume-state.v2"
SCHEMA_MANIFEST = "reth-dtvm.atomic-capture-window.v1"
SCHEMA_FIXED_MANIFEST = "reth-dtvm.atomic-fixed-range-capture.v1"
SCHEMA_SEAL = "reth-dtvm.rpc-ha-evidence-seal.v1"
SCHEMA_FIXED_SEAL = "reth-dtvm.rpc-ha-fixed-range-evidence-seal.v1"
SCHEMA_FIXED_READINESS = "reth-dtvm.rpc-ha-fixed-range-readiness.v1"
OFFLINE_REQUIRED_NETWORK_SYSCALLS = [
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
]
OFFLINE_OPTIONAL_NETWORK_SYSCALLS = {"socketcall"}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def load(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def canonical_digest(value: Any) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def quantity(value: int) -> str:
    return f"0x{value:x}"


def fixed_selection(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict) or value.get("mode") != "exact_fixed_range":
        return None
    start = value.get("startNumber")
    end = value.get("endNumber")
    count = value.get("count")
    if (
        isinstance(start, bool)
        or isinstance(end, bool)
        or isinstance(count, bool)
        or not isinstance(start, int)
        or not isinstance(end, int)
        or not isinstance(count, int)
        or start < 0
        or end < start
        or count < 1
        or count > 256
        or end - start + 1 != count
    ):
        return None
    expected = {
        "mode": "exact_fixed_range",
        "startNumber": start,
        "startNumberHex": quantity(start),
        "endNumber": end,
        "endNumberHex": quantity(end),
        "count": count,
    }
    return expected if value == expected else None


def valid_ordered_heights(
    value: Any,
    selection: dict[str, Any],
) -> bool:
    if not isinstance(value, list) or len(value) != selection["count"]:
        return False
    for index, entry in enumerate(value):
        number = selection["startNumber"] + index
        if (
            not isinstance(entry, dict)
            or entry
            != {
                "number": number,
                "numberHex": quantity(number),
                "hash": entry.get("hash"),
            }
            or not isinstance(entry.get("hash"), str)
            or not BLOCK_HASH.fullmatch(entry["hash"])
            or entry["hash"] != entry["hash"].lower()
        ):
            return False
    return True


def valid_frozen_range(
    value: Any,
    selection: dict[str, Any],
) -> bool:
    if not isinstance(value, dict):
        return False
    anchor = value.get("rangeAnchor")
    ordered = value.get("orderedHeightHashes")
    if (
        value.get("requestedSelection") != selection
        or value.get("range")
        != {
            "firstNumber": selection["startNumber"],
            "firstNumberHex": selection["startNumberHex"],
            "lastNumber": selection["endNumber"],
            "lastNumberHex": selection["endNumberHex"],
        }
        or not isinstance(anchor, dict)
        or anchor.get("number") != selection["endNumber"]
        or anchor.get("numberHex") != selection["endNumberHex"]
        or not isinstance(anchor.get("hash"), str)
        or not BLOCK_HASH.fullmatch(anchor["hash"])
        or anchor["hash"] != anchor["hash"].lower()
        or not isinstance(anchor.get("agreedEndpoints"), list)
        or not all(
            isinstance(endpoint, str)
            for endpoint in anchor["agreedEndpoints"]
        )
        or not valid_ordered_heights(ordered, selection)
        or ordered[-1]["hash"] != anchor["hash"]
        or value.get("orderedCommitmentSha256")
        != canonical_digest(ordered)
    ):
        return False
    return True


def valid_oldest_witness_readiness(
    value: Any,
    frozen_range: dict[str, Any],
) -> bool:
    if not isinstance(value, dict):
        return False
    oldest = frozen_range["orderedHeightHashes"][0]
    required = value.get("required")
    ready_endpoints = value.get("readyEndpoints")
    endpoint_reports = value.get("endpoints")
    failures = value.get("failures")
    if (
        value.get("number") != oldest["number"]
        or value.get("numberHex") != oldest["numberHex"]
        or value.get("hash") != oldest["hash"]
        or value.get("method")
        != "debug_executionWitnessByBlockHash"
        or value.get("mode") != "canonical"
        or isinstance(required, bool)
        or not isinstance(required, int)
        or required < 1
        or not isinstance(ready_endpoints, list)
        or not all(isinstance(name, str) for name in ready_endpoints)
        or len(ready_endpoints) != len(set(ready_endpoints))
        or value.get("satisfied") is not True
        or len(ready_endpoints) < required
        or not isinstance(endpoint_reports, list)
        or not isinstance(failures, list)
    ):
        return False
    expected_ready: list[str] = []
    expected_failures: list[dict[str, str]] = []
    endpoint_names: set[str] = set()
    for report in endpoint_reports:
        if (
            not isinstance(report, dict)
            or not isinstance(report.get("name"), str)
            or not isinstance(report.get("role"), str)
            or not isinstance(report.get("ready"), bool)
            or (
                report.get("failureCategory") is not None
                and not isinstance(report.get("failureCategory"), str)
            )
        ):
            return False
        if report["name"] in endpoint_names:
            return False
        endpoint_names.add(report["name"])
        if report["ready"]:
            if report["failureCategory"] is not None:
                return False
            expected_ready.append(report["name"])
        else:
            if report["failureCategory"] is None:
                return False
            expected_failures.append(
                {
                    "name": report["name"],
                    "failureCategory": report["failureCategory"],
                }
            )
    return (
        ready_endpoints == expected_ready
        and failures == expected_failures
    )


def lexical_absolute(path: Path) -> Path:
    return Path(os.path.abspath(path))


def regular_no_symlink(path: Path) -> bool:
    path = lexical_absolute(path)
    try:
        return (
            path.is_file()
            and not path.is_symlink()
            and path.resolve(strict=True) == path
        )
    except OSError:
        return False


def directory_no_symlink(path: Path) -> bool:
    path = lexical_absolute(path)
    try:
        return (
            path.is_dir()
            and not path.is_symlink()
            and path.resolve(strict=True) == path
        )
    except OSError:
        return False


def fail(category: str) -> int:
    print(
        json.dumps(
            {
                "schema": "reth-dtvm.replay-state-validation.v1",
                "status": "failure",
                "failureCategory": category,
                "credentialsRecorded": False,
            },
            sort_keys=True,
        )
    )
    return 1


def valid_replay(
    report: Any,
    count: int,
    library_sha256: str,
    replayer_realpath: str,
    replayer_sha256: str,
    manifest_sha256: str,
    manifest_blocks: list[dict[str, Any]],
) -> bool:
    if not isinstance(report, dict):
        return False
    corpus = report.get("corpus")
    correctness = report.get("correctness")
    dtvm = report.get("dtvm")
    replayer = report.get("replayer")
    timing = report.get("timingQualification")
    if not (
        report.get("schema") == "reth-dtvm.corpus-correctness.v1"
        and isinstance(corpus, dict)
        and isinstance(corpus.get("manifestSha256"), str)
        and corpus["manifestSha256"].lower()
        == manifest_sha256
        and corpus.get("blockCount") == count
        and isinstance(correctness, dict)
        and correctness.get("passed") is True
        and isinstance(dtvm, dict)
        and isinstance(dtvm.get("librarySha256"), str)
        and dtvm["librarySha256"].lower() == library_sha256
        and dtvm.get("loadedFromVerifiedSealedMemfd") is True
        and isinstance(replayer, dict)
        and replayer.get("realpath") == replayer_realpath
        and isinstance(replayer.get("sha256"), str)
        and replayer["sha256"].lower() == replayer_sha256
        and isinstance(timing, dict)
        and timing.get(
            "excludesFromFormalPr577PerformanceConclusion"
        )
        is True
    ):
        return False
    blocks = correctness.get("blockResults")
    if (
        not isinstance(blocks, list)
        or len(blocks) != count
        or len(manifest_blocks) != count
    ):
        return False
    for block, expected in zip(blocks, manifest_blocks, strict=True):
        if not (
            isinstance(block, dict)
            and block.get("blockNumber") == expected.get("number")
            and isinstance(block.get("blockHash"), str)
            and block["blockHash"].lower()
            == str(expected.get("hash", "")).lower()
            and block.get("bundle") == expected.get("bundle")
            and isinstance(block.get("bundleSha256"), str)
            and block["bundleSha256"].lower()
            == expected.get("bundleSha256")
            and block.get("correctnessPassed") is True
            and block.get("differentialMatch") is True
            and block.get("rawBound") is True
            and block.get("preExecutionCommitments") is True
            and block.get("preStateRootVerified") is True
            and block.get("postStateRootVerified") is True
            and all(
                block.get("postExecutionCommitments", {}).get(name) is True
                for name in (
                    "gasUsed",
                    "receiptsRoot",
                    "logsBloom",
                    "requestsHash",
                    "blobGasUsed",
                )
            )
        ):
            return False
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} STATE_DIR", file=sys.stderr)
        return 2
    root = lexical_absolute(Path(sys.argv[1]))
    state_path = root / "resume-state.json"
    metrics_path = root / "metrics.json"
    if (
        not directory_no_symlink(root)
        or not regular_no_symlink(state_path)
        or not regular_no_symlink(metrics_path)
    ):
        return fail("state_or_metrics_missing")
    try:
        state = load(state_path)
        metrics = load(metrics_path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return fail("state_or_metrics_malformed")
    state_schema = state.get("schema")
    fixed = state_schema == SCHEMA_FIXED_STATE
    if (
        state_schema not in {SCHEMA_STATE, SCHEMA_FIXED_STATE}
        or state.get("credentialsRecorded") is not False
        or metrics.get("schema") != "reth-dtvm.rpc-ha-metrics.v1"
        or metrics.get("secretMaterialRecorded") is not False
        or isinstance(state.get("requestedCount"), bool)
        or not isinstance(state.get("requestedCount"), int)
        or state.get("requestedCount") < 1
    ):
        return fail("state_contract_failed")
    selection: dict[str, Any] | None = None
    frozen_range: dict[str, Any] | None = None
    readiness_path = root / "readiness.json"
    if fixed:
        selection = fixed_selection(state.get("requestedSelection"))
        frozen_range = state.get("frozenRange")
        if (
            selection is None
            or selection["count"] != state["requestedCount"]
            or state.get("requestedTag") is not None
            or "frozenPin" in state
            or (
                frozen_range is not None
                and not valid_frozen_range(frozen_range, selection)
            )
        ):
            return fail("fixed_range_state_contract_failed")
        if frozen_range is not None:
            readiness_sha256 = state.get("readinessSha256")
            if (
                not HASH.fullmatch(readiness_sha256 or "")
                or not regular_no_symlink(readiness_path)
                or digest(readiness_path) != readiness_sha256
            ):
                return fail("fixed_range_readiness_evidence_failed")
            try:
                readiness = load(readiness_path)
            except (OSError, UnicodeError, json.JSONDecodeError):
                return fail("fixed_range_readiness_evidence_failed")
            if (
                not isinstance(readiness, dict)
                or readiness.get("schema") != SCHEMA_FIXED_READINESS
                or readiness.get("status") != "ready"
                or readiness.get("success") is not True
                or readiness.get("requestedSelection") != selection
                or readiness.get("frozenPin") is not None
                or readiness.get("frozenRange") != frozen_range
                or not valid_oldest_witness_readiness(
                    readiness.get("oldestWitnessReadiness"),
                    frozen_range,
                )
                or readiness.get("secretMaterialRecorded") is not False
            ):
                return fail("fixed_range_readiness_contract_failed")
        elif (
            state.get("networkCaptureCompleted") is True
            or state.get("strictReplayCompleted") is True
            or state.get("evidenceSealed") is True
            or state.get("phase")
            in {"ready", "capturing", "captured", "checksummed", "published", "replayed", "sealed"}
        ):
            return fail("fixed_range_identity_missing")
    elif state.get("requestedTag") != "finalized":
        return fail("state_contract_failed")
    if (
        state.get("evidenceSealed") is True
        and (
            state.get("phase") != "sealed"
            or state.get("status") != "success"
            or state.get("networkCaptureCompleted") is not True
            or state.get("strictReplayCompleted") is not True
            or state.get("networkExcludedFromReplay") is not True
        )
    ):
        return fail("sealed_state_flags_inconsistent")
    if state.get("phase") == "sealed" and state.get("evidenceSealed") is not True:
        return fail("sealed_state_flags_inconsistent")
    if state.get("strictReplayCompleted") is True and (
        state.get("networkCaptureCompleted") is not True
        or state.get("networkExcludedFromReplay") is not True
        or state.get("phase") not in {"replayed", "sealed"}
    ):
        return fail("replay_state_flags_inconsistent")
    output_value = state.get("output")
    if not isinstance(output_value, str) or not Path(output_value).is_absolute():
        return fail("output_path_invalid")
    output = lexical_absolute(Path(output_value))
    approved_replayer = state.get("approvedReplayer")
    approved_binary = (
        approved_replayer.get("replayer")
        if isinstance(approved_replayer, dict)
        else None
    )
    if (
        not isinstance(approved_replayer, dict)
        or approved_replayer.get("role") != "downstream_replayer_identity"
        or not isinstance(approved_replayer.get("manifestRealpath"), str)
        or not HASH.fullmatch(approved_replayer.get("manifestSha256", ""))
        or not isinstance(approved_binary, dict)
        or not isinstance(approved_binary.get("realpath"), str)
        or not HASH.fullmatch(approved_binary.get("sha256", ""))
    ):
        return fail("approved_replayer_state_contract_failed")
    approved_manifest = Path(approved_replayer["manifestRealpath"])
    approved_binary_path = Path(approved_binary["realpath"])
    if (
        not regular_no_symlink(approved_manifest)
        or digest(approved_manifest) != approved_replayer["manifestSha256"]
        or not regular_no_symlink(approved_binary_path)
        or digest(approved_binary_path) != approved_binary["sha256"]
    ):
        return fail("approved_replayer_evidence_failed")
    manifest = output / "manifest.json"
    checksum = output / "bundle-checksums.json"
    checksum_lines = output / "BUNDLE_SHA256SUMS"
    if state.get("networkCaptureCompleted"):
        if (
            not directory_no_symlink(output)
            or not regular_no_symlink(manifest)
            or not regular_no_symlink(checksum)
            or not regular_no_symlink(checksum_lines)
        ):
            return fail("published_capture_missing")
        try:
            manifest_value = load(manifest)
            checksum_value = load(checksum)
        except (OSError, UnicodeError, json.JSONDecodeError):
            return fail("capture_evidence_malformed")
        count = state["requestedCount"]
        manifest_blocks = (
            manifest_value.get("blocks") if isinstance(manifest_value, dict) else None
        )
        checksum_entries = (
            checksum_value.get("bundles") if isinstance(checksum_value, dict) else None
        )
        capture_replayer = (
            manifest_value.get("replayerIdentity")
            if isinstance(manifest_value, dict)
            else None
        )
        capture_replayer_binary = (
            capture_replayer.get("replayer")
            if isinstance(capture_replayer, dict)
            else None
        )
        expected_manifest_schema = (
            SCHEMA_FIXED_MANIFEST if fixed else SCHEMA_MANIFEST
        )
        fixed_manifest_valid = True
        if fixed:
            if selection is None or frozen_range is None:
                return fail("fixed_range_identity_missing")
            expected_order = frozen_range["orderedHeightHashes"]
            before = (
                manifest_value.get("canonicalRecheck", {}).get("beforeCapture")
                if isinstance(manifest_value, dict)
                else None
            )
            after = (
                manifest_value.get("canonicalRecheck", {}).get("afterCapture")
                if isinstance(manifest_value, dict)
                else None
            )
            fixed_manifest_valid = bool(
                isinstance(manifest_value, dict)
                and manifest_value.get("requestedTag") is None
                and manifest_value.get("pinnedHead") is None
                and manifest_value.get("requestedSelection") == selection
                and manifest_value.get("range")
                == {
                    "firstNumber": selection["startNumber"],
                    "firstNumberHex": selection["startNumberHex"],
                    "lastNumber": selection["endNumber"],
                    "lastNumberHex": selection["endNumberHex"],
                }
                and manifest_value.get("rangeAnchor")
                == {
                    "number": selection["endNumber"],
                    "numberHex": selection["endNumberHex"],
                    "hash": frozen_range["rangeAnchor"]["hash"],
                }
                and isinstance(before, dict)
                and isinstance(after, dict)
                and before.get("phase") == "before_capture"
                and after.get("phase") == "after_capture"
                and before.get("checkedCount") == count
                and after.get("checkedCount") == count
                and before.get("orderedHeightHashes") == expected_order
                and after.get("orderedHeightHashes") == expected_order
                and before.get("orderedCommitmentSha256")
                == canonical_digest(expected_order)
                and after.get("orderedCommitmentSha256")
                == canonical_digest(expected_order)
                and manifest_value.get("canonicalRecheck", {}).get(
                    "allOrderedHashesUnchanged"
                )
                is True
                and state.get("preCaptureOrderedHeightHashes")
                == expected_order
                and state.get("postCaptureOrderedHeightHashes")
                == expected_order
                and state.get("preCaptureOrderedCommitmentSha256")
                == canonical_digest(expected_order)
                and state.get("postCaptureOrderedCommitmentSha256")
                == canonical_digest(expected_order)
            )
        if (
            not isinstance(manifest_value, dict)
            or not isinstance(checksum_value, dict)
            or manifest_value.get("schema") != expected_manifest_schema
            or manifest_value.get("success") is not True
            or manifest_value.get("count") != count
            or not fixed_manifest_valid
            or not isinstance(capture_replayer, dict)
            or capture_replayer.get("role") != approved_replayer["role"]
            or capture_replayer.get("manifestRealpath")
            != approved_replayer["manifestRealpath"]
            or capture_replayer.get("manifestSha256")
            != approved_replayer["manifestSha256"]
            or not isinstance(capture_replayer_binary, dict)
            or capture_replayer_binary.get("realpath")
            != approved_binary["realpath"]
            or str(capture_replayer_binary.get("sha256", "")).lower()
            != approved_binary["sha256"]
            or not isinstance(manifest_blocks, list)
            or len(manifest_blocks) != count
            or checksum_value.get("schema") != "reth-dtvm.bundle-checksums.v1"
            or checksum_value.get("blockCount") != count
            or not isinstance(checksum_entries, list)
            or len(checksum_entries) != count
            or checksum_value.get("manifestSha256") != digest(manifest)
            or checksum_value.get("manifestSha256") != state.get("manifestSha256")
            or not HASH.fullmatch(checksum_value.get("bundleSetSha256", ""))
            or checksum_value.get("bundleSetSha256")
            != state.get("bundleSetSha256")
        ):
            return fail("capture_checksum_contract_failed")
        manifest_by_path: dict[str, str] = {}
        previous_hash: str | None = None
        for block in manifest_blocks:
            if not isinstance(block, dict):
                return fail("capture_manifest_bundle_contract_failed")
            relative = block.get("bundle")
            bundle_sha256 = block.get("bundleSha256")
            if (
                not isinstance(block.get("number"), int)
                or isinstance(block.get("number"), bool)
                or not isinstance(block.get("numberHex"), str)
                or not QUANTITY.fullmatch(block["numberHex"])
                or int(block["numberHex"], 16) != block["number"]
                or not isinstance(block.get("hash"), str)
                or not BLOCK_HASH.fullmatch(block["hash"])
                or not isinstance(block.get("parentHash"), str)
                or not BLOCK_HASH.fullmatch(block["parentHash"])
                or (
                    fixed
                    and selection is not None
                    and block["number"]
                    != selection["startNumber"] + len(manifest_by_path)
                )
                or (
                    previous_hash is not None
                    and block["parentHash"].lower() != previous_hash
                )
                or not isinstance(relative, str)
                or Path(relative).is_absolute()
                or ".." in Path(relative).parts
                or relative in manifest_by_path
                or not HASH.fullmatch(bundle_sha256 or "")
            ):
                return fail("capture_manifest_bundle_contract_failed")
            manifest_by_path[relative] = bundle_sha256
            previous_hash = block["hash"].lower()
        if fixed:
            expected_block_identities = [
                {
                    "number": entry["number"],
                    "hash": entry["hash"],
                }
                for entry in frozen_range["orderedHeightHashes"]
            ]
            manifest_block_identities = [
                {
                    "number": block["number"],
                    "hash": block["hash"].lower(),
                }
                for block in manifest_blocks
            ]
            expected_block_commitment = canonical_digest(
                expected_block_identities
            )
            if (
                frozen_range is None
                or previous_hash != frozen_range["rangeAnchor"]["hash"]
                or manifest_block_identities != expected_block_identities
                or manifest_value.get("orderedBlockCommitmentSha256")
                != expected_block_commitment
                or state.get("orderedBlockCommitmentSha256")
                != expected_block_commitment
            ):
                return fail("fixed_range_capture_identity_failed")
        checksum_by_path: dict[str, str] = {}
        for entry in checksum_entries:
            if not isinstance(entry, dict):
                return fail("capture_checksum_entry_contract_failed")
            relative = entry.get("path")
            entry_sha256 = entry.get("sha256")
            if (
                not isinstance(relative, str)
                or Path(relative).is_absolute()
                or ".." in Path(relative).parts
                or relative in checksum_by_path
                or not HASH.fullmatch(entry_sha256 or "")
            ):
                return fail("unsafe_bundle_path")
            checksum_by_path[relative] = entry_sha256
            bundle = output / relative
            if (
                not regular_no_symlink(bundle)
                or digest(bundle) != entry_sha256
            ):
                return fail("bundle_checksum_failed")
        if checksum_by_path != manifest_by_path:
            return fail("bundle_entry_set_mismatch")
        expected_lines = "".join(
            f"{checksum_by_path[relative]}  {relative}\n"
            for relative in sorted(checksum_by_path)
        ).encode()
        if (
            hashlib.sha256(expected_lines).hexdigest()
            != checksum_value.get("bundleSetSha256")
            or checksum_lines.read_bytes() != expected_lines
        ):
            return fail("bundle_set_checksum_failed")
    if state.get("strictReplayCompleted"):
        replay_result = Path(state.get("replayOutput", "")) / "result.json"
        verify_script = Path(state.get("verifyCorpusScript", ""))
        library = Path(state.get("dtvmLibrary", ""))
        isolation = state.get("offlineReplayIsolation")
        isolation_runner = (
            Path(isolation.get("runnerRealpath", ""))
            if isinstance(isolation, dict)
            else Path("")
        )
        denied_syscalls = (
            isolation.get("deniedSyscalls")
            if isinstance(isolation, dict)
            else None
        )
        optional_denied = (
            denied_syscalls[len(OFFLINE_REQUIRED_NETWORK_SYSCALLS) :]
            if isinstance(denied_syscalls, list)
            else []
        )
        if (
            state.get("networkExcludedFromReplay") is not True
            or not isinstance(isolation, dict)
            or set(isolation)
            != {
                "schema",
                "runnerRealpath",
                "runnerSha256",
                "deniedSyscalls",
            }
            or isolation.get("schema")
            != "libseccomp-deny-network-syscalls.v1"
            or not isinstance(isolation.get("runnerRealpath"), str)
            or not Path(isolation["runnerRealpath"]).is_absolute()
            or not HASH.fullmatch(isolation.get("runnerSha256", ""))
            or not isinstance(denied_syscalls, list)
            or denied_syscalls[: len(OFFLINE_REQUIRED_NETWORK_SYSCALLS)]
            != OFFLINE_REQUIRED_NETWORK_SYSCALLS
            or len(denied_syscalls) != len(set(denied_syscalls))
            or not set(optional_denied).issubset(
                OFFLINE_OPTIONAL_NETWORK_SYSCALLS
            )
            or not regular_no_symlink(isolation_runner)
            or digest(isolation_runner) != isolation["runnerSha256"]
            or not regular_no_symlink(replay_result)
            or digest(replay_result) != state.get("replayResultSha256")
            or not regular_no_symlink(verify_script)
            or digest(verify_script) != state.get("verifyCorpusSha256")
            or not regular_no_symlink(library)
            or digest(library) != state.get("dtvmLibrarySha256")
            or not valid_replay(
                load(replay_result),
                state.get("requestedCount"),
                state.get("dtvmLibrarySha256"),
                approved_binary["realpath"],
                approved_binary["sha256"],
                state.get("manifestSha256"),
                manifest_blocks,
            )
        ):
            return fail("strict_replay_evidence_failed")
    if state.get("evidenceSealed"):
        seal = Path(state.get("evidenceSeal", ""))
        if (
            not regular_no_symlink(seal)
            or digest(seal) != state.get("evidenceSealSha256")
        ):
            return fail("seal_checksum_failed")
        try:
            seal_value = load(seal)
        except (OSError, UnicodeError, json.JSONDecodeError):
            return fail("seal_malformed")
        expected_seal_schema = SCHEMA_FIXED_SEAL if fixed else SCHEMA_SEAL
        if (
            seal_value.get("schema") != expected_seal_schema
            or seal_value.get("status") != "sealed"
            or not isinstance(seal_value.get("sealedAtUtc"), str)
            or seal_value.get("credentialsRecorded") is not False
            or seal_value.get("configFingerprint")
            != state.get("configFingerprint")
            or seal_value.get("networkCaptureCompleted") is not True
            or seal_value.get("strictReplayCompleted") is not True
            or seal_value.get("networkExcludedFromReplay") is not True
            or seal_value.get("metrics") != metrics
        ):
            return fail("seal_contract_failed")
        if fixed:
            if (
                selection is None
                or frozen_range is None
                or seal_value.get("requestedSelection") != selection
                or seal_value.get("frozenRange") != frozen_range
                or seal_value.get("readinessSha256")
                != state.get("readinessSha256")
                or "frozenPin" in seal_value
            ):
                return fail("fixed_range_seal_contract_failed")
        elif seal_value.get("frozenPin") != state.get("frozenPin"):
            return fail("seal_contract_failed")
        inputs = seal_value.get("inputs")
        expected_input_count = 10 if fixed else 9
        if not isinstance(inputs, list) or len(inputs) != expected_input_count:
            return fail("seal_inputs_missing")
        by_role = {
            item.get("role"): item
            for item in inputs
            if isinstance(item, dict)
            and isinstance(item.get("role"), str)
            and isinstance(item.get("path"), str)
            and HASH.fullmatch(item.get("sha256", ""))
        }
        required_roles = {
            "capture_manifest",
            "bundle_checksums",
            "resume_state_before_seal",
            "strict_replay_runner",
            "dtvm_library",
            "approved_replayer",
            "offline_replay_launcher",
            "rpc_metrics",
            "strict_replay_result",
        }
        if fixed:
            required_roles.add("readiness_report")
        if set(by_role) != required_roles or len(by_role) != len(inputs):
            return fail("seal_inputs_contract_failed")
        for item in by_role.values():
            path = Path(item["path"])
            if (
                not regular_no_symlink(path)
                or digest(path) != item["sha256"]
            ):
                return fail("seal_input_checksum_failed")
        replay_result = Path(state["replayOutput"]) / "result.json"
        expected_paths = {
            "capture_manifest": manifest,
            "bundle_checksums": checksum,
            "resume_state_before_seal": root / "resume-state-before-seal.json",
            "strict_replay_runner": Path(state["verifyCorpusScript"]),
            "dtvm_library": Path(state["dtvmLibrary"]),
            "approved_replayer": approved_binary_path,
            "offline_replay_launcher": Path(
                state["offlineReplayIsolation"]["runnerRealpath"]
            ),
            "rpc_metrics": metrics_path,
            "strict_replay_result": replay_result,
        }
        if fixed:
            expected_paths["readiness_report"] = readiness_path
        if any(
            Path(by_role[role]["path"]) != expected_path
            for role, expected_path in expected_paths.items()
        ):
            return fail("seal_input_path_mismatch")
        if (
            by_role["capture_manifest"]["sha256"] != state.get("manifestSha256")
            or by_role["bundle_checksums"]["sha256"] != digest(checksum)
            or by_role["rpc_metrics"]["sha256"] != digest(metrics_path)
            or by_role["strict_replay_result"]["sha256"]
            != state.get("replayResultSha256")
            or by_role["strict_replay_runner"]["sha256"]
            != state.get("verifyCorpusSha256")
            or by_role["dtvm_library"]["sha256"]
            != state.get("dtvmLibrarySha256")
            or by_role["approved_replayer"]["sha256"]
            != approved_binary["sha256"]
            or by_role["offline_replay_launcher"]["sha256"]
            != state["offlineReplayIsolation"]["runnerSha256"]
            or (
                fixed
                and by_role["readiness_report"]["sha256"]
                != state.get("readinessSha256")
            )
        ):
            return fail("seal_input_continuity_failed")
        preseal_path = expected_paths["resume_state_before_seal"]
        try:
            preseal = load(preseal_path)
        except (OSError, UnicodeError, json.JSONDecodeError):
            return fail("preseal_state_malformed")
        ignored = {"updatedAtUtc", "evidenceSeal", "evidenceSealSha256"}
        expected_preseal = {
            key: value
            for key, value in state.items()
            if key not in ignored
        }
        expected_preseal["phase"] = "replayed"
        expected_preseal["evidenceSealed"] = False
        actual_preseal = (
            {
                key: value
                for key, value in preseal.items()
                if key not in ignored
            }
            if isinstance(preseal, dict)
            else None
        )
        if actual_preseal != expected_preseal:
            return fail("preseal_state_continuity_failed")
    print(
        json.dumps(
            {
                "schema": "reth-dtvm.replay-state-validation.v1",
                "status": "verified",
                "phase": state.get("phase"),
                "networkCaptureCompleted": state.get("networkCaptureCompleted"),
                "strictReplayCompleted": state.get("strictReplayCompleted"),
                "evidenceSealed": state.get("evidenceSealed"),
                "credentialsRecorded": False,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
