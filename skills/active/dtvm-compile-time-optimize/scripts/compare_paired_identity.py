#!/usr/bin/env python3
"""Compare paired DTVM build and subject-command identities."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
CACHE_ENTRY_RE = re.compile(r"^([^:=]+):([^=]+)=(.*)$")
CACHE_PATH_TYPES = {"FILEPATH", "PATH"}
CACHE_ROOT_KEYS = {
    "CMAKE_CACHEFILE_DIR",
    "CMAKE_FIND_PACKAGE_REDIRECTS_DIR",
    "CMAKE_HOME_DIRECTORY",
}
CACHE_ROOT_SUFFIXES = ("_BINARY_DIR", "_SOURCE_DIR")
PATH_KINDS = {"build_path", "literal", "worktree_path"}
MISSING = object()


class IdentityError(ValueError):
    """Raised when an identity input violates the comparison contract."""


@dataclass(frozen=True)
class VariantInputs:
    worktree: Path
    build: Path
    cache: Path
    command: Path


def canonical_directory(raw_path: str, label: str) -> Path:
    path = Path(raw_path)
    if not path.is_absolute():
        raise IdentityError(f"{label} must be absolute: {raw_path}")
    if not path.is_dir():
        raise IdentityError(f"{label} is not a directory: {raw_path}")
    normalized = Path(os.path.normpath(raw_path))
    resolved = path.resolve(strict=True)
    if normalized != resolved:
        raise IdentityError(
            f"{label} must be an existing canonical path: {raw_path} != {resolved}"
        )
    return resolved


def is_within(path: str, root: Path) -> bool:
    try:
        return os.path.commonpath((path, str(root))) == str(root)
    except ValueError:
        return False


def validate_roots(worktree: Path, build: Path, label: str) -> None:
    if build == worktree or not is_within(str(build), worktree):
        raise IdentityError(f"{label} build must be below its worktree")


def replace_root(path: str, root: Path, token: str) -> str:
    relative = os.path.relpath(path, root)
    return token if relative == "." else f"{token}/{relative}"


def is_cache_path_field(name: str, cache_type: str) -> bool:
    return (
        cache_type in CACHE_PATH_TYPES
        or name in CACHE_ROOT_KEYS
        or name.endswith(CACHE_ROOT_SUFFIXES)
    )


def normalize_cache_value(
    name: str, cache_type: str, value: str, worktree: Path, build: Path
) -> str:
    """Normalize only a standalone canonical path rooted in build/worktree."""
    if (
        not is_cache_path_field(name, cache_type)
        or ";" in value
        or not os.path.isabs(value)
        or os.path.normpath(value) != value
    ):
        return value
    if is_within(value, build):
        return replace_root(value, build, "${BUILD}")
    if is_within(value, worktree):
        return replace_root(value, worktree, "${WORKTREE}")
    return value


def parse_cache(path: Path, worktree: Path, build: Path) -> dict[str, dict[str, str]]:
    if not path.is_file():
        raise IdentityError(f"CMake cache does not exist: {path}")

    entries: dict[str, dict[str, str]] = {}
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        match = CACHE_ENTRY_RE.match(line)
        if not match:
            raise IdentityError(f"{path}:{line_number}: malformed CMake cache entry")
        name, cache_type, value = match.groups()
        if name in entries:
            raise IdentityError(f"{path}:{line_number}: duplicate cache key {name}")
        entries[name] = {
            "type": cache_type,
            "value": normalize_cache_value(
                name, cache_type, value, worktree, build
            ),
        }
    return entries


def require_exact_keys(
    value: dict[str, Any], expected: set[str], label: str
) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise IdentityError(f"{label} keys differ: missing={missing}, extra={extra}")


def normalize_command_value(
    raw: Any, worktree: Path, build: Path, label: str
) -> dict[str, str]:
    if not isinstance(raw, dict):
        raise IdentityError(f"{label} must be an object")
    require_exact_keys(raw, {"kind", "value"}, label)

    kind = raw["kind"]
    value = raw["value"]
    if kind not in PATH_KINDS:
        raise IdentityError(f"{label}.kind must be one of {sorted(PATH_KINDS)}")
    if not isinstance(value, str):
        raise IdentityError(f"{label}.value must be a string")
    if kind == "literal":
        return {"kind": kind, "value": value}

    if not os.path.isabs(value) or os.path.normpath(value) != value:
        raise IdentityError(f"{label}.value must be a canonical absolute path")
    if kind == "build_path":
        if not is_within(value, build):
            raise IdentityError(f"{label}.value is outside the declared build")
        normalized = replace_root(value, build, "${BUILD}")
    else:
        if not is_within(value, worktree):
            raise IdentityError(f"{label}.value is outside the declared worktree")
        if is_within(value, build):
            raise IdentityError(f"{label}.value is a build path; label it build_path")
        normalized = replace_root(value, worktree, "${WORKTREE}")
    return {"kind": kind, "value": normalized}


def parse_command(path: Path, worktree: Path, build: Path) -> dict[str, Any]:
    if not path.is_file():
        raise IdentityError(f"subject command manifest does not exist: {path}")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise IdentityError(f"{path}: invalid JSON: {error}") from error
    if not isinstance(raw, dict):
        raise IdentityError(f"{path}: top level must be an object")
    require_exact_keys(
        raw, {"schema_version", "cwd", "argv", "environment"}, str(path)
    )
    if raw["schema_version"] != SCHEMA_VERSION:
        raise IdentityError(
            f"{path}: schema_version must be {SCHEMA_VERSION}, "
            f"got {raw['schema_version']!r}"
        )
    if not isinstance(raw["argv"], list) or not raw["argv"]:
        raise IdentityError(f"{path}: argv must be a non-empty array")
    environment = raw["environment"]
    if not isinstance(environment, dict) or not all(
        isinstance(key, str) and isinstance(value, str)
        for key, value in environment.items()
    ):
        raise IdentityError(f"{path}: environment must map strings to strings")

    return {
        "schema_version": SCHEMA_VERSION,
        "cwd": normalize_command_value(
            raw["cwd"], worktree, build, f"{path}: cwd"
        ),
        "argv": [
            normalize_command_value(item, worktree, build, f"{path}: argv[{index}]")
            for index, item in enumerate(raw["argv"])
        ],
        "environment": dict(sorted(environment.items())),
    }


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode()


def sha256(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def differences(baseline: Any, candidate: Any, path: str = "$") -> list[dict[str, Any]]:
    if isinstance(baseline, dict) and isinstance(candidate, dict):
        result: list[dict[str, Any]] = []
        for key in sorted(set(baseline) | set(candidate)):
            result.extend(
                differences(
                    baseline.get(key, MISSING),
                    candidate.get(key, MISSING),
                    f"{path}.{key}",
                )
            )
        return result
    if isinstance(baseline, list) and isinstance(candidate, list):
        result = []
        for index in range(max(len(baseline), len(candidate))):
            left = baseline[index] if index < len(baseline) else MISSING
            right = candidate[index] if index < len(candidate) else MISSING
            result.extend(differences(left, right, f"{path}[{index}]"))
        return result
    if baseline == candidate:
        return []
    return [
        {
            "field": path,
            "baseline": None if baseline is MISSING else baseline,
            "candidate": None if candidate is MISSING else candidate,
        }
    ]


def compare_section(baseline: Any, candidate: Any) -> dict[str, Any]:
    delta = differences(baseline, candidate)
    return {
        "match": not delta,
        "baseline_sha256": sha256(baseline),
        "candidate_sha256": sha256(candidate),
        "differences": delta,
    }


def load_variant(inputs: VariantInputs, label: str) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_roots(inputs.worktree, inputs.build, label)
    return (
        parse_cache(inputs.cache, inputs.worktree, inputs.build),
        parse_command(inputs.command, inputs.worktree, inputs.build),
    )


def build_report(
    baseline_inputs: VariantInputs, candidate_inputs: VariantInputs
) -> dict[str, Any]:
    baseline_cache, baseline_command = load_variant(baseline_inputs, "baseline")
    candidate_cache, candidate_command = load_variant(candidate_inputs, "candidate")
    cache_report = compare_section(baseline_cache, candidate_cache)
    command_report = compare_section(baseline_command, candidate_command)
    return {
        "schema_version": SCHEMA_VERSION,
        "match": cache_report["match"] and command_report["match"],
        "normalization": {
            "cmake_cache": (
                "standalone canonical values under declared build/worktree roots"
            ),
            "subject_command": ["build_path", "worktree_path"],
        },
        "cmake_cache": cache_report,
        "subject_command": command_report,
    }


def variant_from_args(args: argparse.Namespace, prefix: str) -> VariantInputs:
    return VariantInputs(
        worktree=canonical_directory(
            getattr(args, f"{prefix}_worktree"), f"{prefix} worktree"
        ),
        build=canonical_directory(
            getattr(args, f"{prefix}_build"), f"{prefix} build"
        ),
        cache=Path(getattr(args, f"{prefix}_cache")),
        command=Path(getattr(args, f"{prefix}_command")),
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    for prefix in ("baseline", "candidate"):
        parser.add_argument(f"--{prefix}-worktree", required=True)
        parser.add_argument(f"--{prefix}-build", required=True)
        parser.add_argument(f"--{prefix}-cache", required=True)
        parser.add_argument(f"--{prefix}-command", required=True)
    parser.add_argument(
        "--output",
        help="Write the deterministic JSON report to a new file instead of stdout",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        report = build_report(
            variant_from_args(args, "baseline"),
            variant_from_args(args, "candidate"),
        )
        rendered = json.dumps(
            report, ensure_ascii=False, indent=2, sort_keys=True
        ) + "\n"
        if args.output:
            output = Path(args.output)
            if output.exists():
                raise IdentityError(f"refusing to overwrite output: {output}")
            output.write_text(rendered, encoding="utf-8")
        else:
            sys.stdout.write(rendered)
        return 0 if report["match"] else 1
    except (IdentityError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
