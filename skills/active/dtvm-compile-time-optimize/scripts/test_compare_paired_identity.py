#!/usr/bin/env python3
"""Regression tests for paired DTVM identity comparison."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from compare_paired_identity import (  # noqa: E402
    IdentityError,
    VariantInputs,
    build_report,
    canonical_bytes,
    main,
)


class PairedIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name).resolve()
        self.baseline = self.make_variant("baseline")
        self.candidate = self.make_variant("candidate")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def make_variant(self, name: str) -> VariantInputs:
        worktree = self.root / name
        build = worktree / "build"
        build.mkdir(parents=True)
        cache = build / "CMakeCache.txt"
        cache.write_text(
            "\n".join(
                [
                    "# This is the CMakeCache file.",
                    f"CMAKE_CACHEFILE_DIR:INTERNAL={build}",
                    f"CMAKE_FIND_PACKAGE_REDIRECTS_DIR:STATIC={build}/CMakeFiles/pkgRedirects",
                    f"CMAKE_HOME_DIRECTORY:INTERNAL={worktree}",
                    "CMAKE_CXX_COMPILER:FILEPATH=/usr/bin/c++",
                    "ZEN_ENABLE_EVM:BOOL=ON",
                    f"ZetaEngine_BINARY_DIR:STATIC={build}",
                    f"ZetaEngine_SOURCE_DIR:STATIC={worktree}",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        command = worktree / "subject-command.json"
        command.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "cwd": {"kind": "worktree_path", "value": str(worktree)},
                    "argv": [
                        {"kind": "literal", "value": "/opt/evmone/evmone-bench"},
                        {
                            "kind": "build_path",
                            "value": str(build / "lib/libdtvmapi.so"),
                        },
                        {"kind": "literal", "value": "/data/corpus/erc20.hex"},
                    ],
                    "environment": {"LC_ALL": "C"},
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        return VariantInputs(worktree, build, cache, command)

    def rewrite_cache(self, variant: VariantInputs, old: str, new: str) -> None:
        content = variant.cache.read_text(encoding="utf-8")
        variant.cache.write_text(content.replace(old, new), encoding="utf-8")

    def rewrite_command(self, variant: VariantInputs, transform) -> None:
        payload = json.loads(variant.command.read_text(encoding="utf-8"))
        transform(payload)
        variant.command.write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )

    def test_permitted_root_fields_compare_equal_and_render_deterministically(self) -> None:
        first = build_report(self.baseline, self.candidate)
        second = build_report(self.baseline, self.candidate)
        self.assertTrue(first["match"])
        self.assertEqual(canonical_bytes(first), canonical_bytes(second))
        self.assertEqual(
            first["cmake_cache"]["baseline_sha256"],
            first["cmake_cache"]["candidate_sha256"],
        )
        self.assertEqual(
            first["subject_command"]["baseline_sha256"],
            first["subject_command"]["candidate_sha256"],
        )

    def test_semantic_cache_difference_is_not_normalized(self) -> None:
        self.rewrite_cache(
            self.candidate,
            "ZEN_ENABLE_EVM:BOOL=ON",
            "ZEN_ENABLE_EVM:BOOL=OFF",
        )
        report = build_report(self.baseline, self.candidate)
        self.assertFalse(report["match"])
        self.assertEqual(
            ["$.ZEN_ENABLE_EVM.value"],
            [item["field"] for item in report["cmake_cache"]["differences"]],
        )

    def test_standalone_string_root_is_not_treated_as_a_path_field(self) -> None:
        for variant in (self.baseline, self.candidate):
            with variant.cache.open("a", encoding="utf-8") as cache_file:
                cache_file.write(
                    f"CUSTOM_COMMAND:STRING={variant.worktree}/tool --flag\n"
                )
        report = build_report(self.baseline, self.candidate)
        self.assertFalse(report["match"])
        self.assertEqual(
            ["$.CUSTOM_COMMAND.value"],
            [item["field"] for item in report["cmake_cache"]["differences"]],
        )

    def test_embedded_worktree_path_in_flag_is_not_normalized(self) -> None:
        for variant in (self.baseline, self.candidate):
            with variant.cache.open("a", encoding="utf-8") as cache_file:
                cache_file.write(
                    f"CMAKE_CXX_FLAGS:STRING=-I{variant.worktree}/include\n"
                )
        report = build_report(self.baseline, self.candidate)
        self.assertFalse(report["match"])
        self.assertEqual(
            ["$.CMAKE_CXX_FLAGS.value"],
            [item["field"] for item in report["cmake_cache"]["differences"]],
        )

    def test_literal_command_path_is_not_normalized(self) -> None:
        for variant in (self.baseline, self.candidate):
            self.rewrite_command(
                variant,
                lambda payload, root=variant.worktree: payload["argv"].append(
                    {"kind": "literal", "value": str(root / "corpus/input.hex")}
                ),
            )
        report = build_report(self.baseline, self.candidate)
        self.assertFalse(report["match"])
        self.assertEqual(
            ["$.argv[3].value"],
            [item["field"] for item in report["subject_command"]["differences"]],
        )

    def test_relative_suffix_difference_is_preserved(self) -> None:
        self.rewrite_command(
            self.candidate,
            lambda payload: payload["argv"][1].update(
                {"value": str(self.candidate.build / "lib/other.so")}
            ),
        )
        report = build_report(self.baseline, self.candidate)
        self.assertFalse(report["match"])
        self.assertEqual(
            ["$.argv[1].value"],
            [item["field"] for item in report["subject_command"]["differences"]],
        )

    def test_typed_path_must_be_inside_its_declared_root(self) -> None:
        self.rewrite_command(
            self.candidate,
            lambda payload: payload["argv"][1].update({"value": "/tmp/other.so"}),
        )
        with self.assertRaisesRegex(IdentityError, "outside the declared build"):
            build_report(self.baseline, self.candidate)

    def test_cli_writes_a_new_matching_report(self) -> None:
        output = self.root / "paired-identity.json"
        arguments = [
            "--baseline-worktree",
            str(self.baseline.worktree),
            "--baseline-build",
            str(self.baseline.build),
            "--baseline-cache",
            str(self.baseline.cache),
            "--baseline-command",
            str(self.baseline.command),
            "--candidate-worktree",
            str(self.candidate.worktree),
            "--candidate-build",
            str(self.candidate.build),
            "--candidate-cache",
            str(self.candidate.cache),
            "--candidate-command",
            str(self.candidate.command),
            "--output",
            str(output),
        ]
        self.assertEqual(0, main(arguments))
        self.assertTrue(json.loads(output.read_text(encoding="utf-8"))["match"])


if __name__ == "__main__":
    unittest.main()
