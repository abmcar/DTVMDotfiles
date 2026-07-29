#!/usr/bin/env python3
"""Static routing tests for the DTVM compile-time optimization skill."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


SKILL_PATH = Path(__file__).resolve().parent.parent / "SKILL.md"


class SkillContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SKILL_PATH.read_text(encoding="utf-8")

    def section(self, heading: str) -> str:
        start = self.text.index(heading)
        match = re.search(r"^## ", self.text[start + len(heading) :], re.MULTILINE)
        end = (
            len(self.text)
            if match is None
            else start + len(heading) + match.start()
        )
        return self.text[start:end]

    def test_project_workflow_precedes_compiler_dispatch(self) -> None:
        workflow = "## 4. Enter the project change workflow"
        compiler = "## 5. Delegate the compiler change"
        self.assertLess(self.text.index(workflow), self.text.index(compiler))
        pre_dispatch = self.text[: self.text.index(compiler)]
        self.assertIn("$dtvm-dev-workflow", pre_dispatch)
        self.assertIn("before any `src/**` edit", pre_dispatch)
        self.assertIn(
            "docs/changes/YYYY-MM-DD-<slug>/README.md",
            pre_dispatch,
        )
        self.assertIn("docs/modules/<module>/spec.md", pre_dispatch)

    def test_missing_workflow_blocks_source_edits(self) -> None:
        workflow = self.section("## 4. Enter the project change workflow")
        normalized = " ".join(workflow.split())
        self.assertIn(
            "If `$dtvm-dev-workflow` is not discoverable, stop before any "
            "`src/**` edit",
            normalized,
        )
        self.assertIn("do not fall through to `compiler-agent`", normalized)
        self.assertIn("end without editing `src/**`", normalized)

    def test_ordinary_optimization_does_not_default_to_dev_cycle(self) -> None:
        workflow = self.section("## 4. Enter the project change workflow")
        self.assertIn(
            "ordinary performance improvement as an enhancement, not a feature",
            workflow,
        )
        self.assertIn("do not invoke `$dtvm-dev-cycle` by default", workflow)
        self.assertIn(
            "feature, architecture change, or breaking change",
            workflow,
        )

    def test_change_document_stays_accepted_until_merge(self) -> None:
        workflow = self.section("## 4. Enter the project change workflow")
        compiler = self.section("## 5. Delegate the compiler change")
        benchmark = self.section("## 6. Run the isomorphic paired benchmark")
        self.assertIn("reach `Accepted` before implementation", workflow)
        self.assertIn("Keep it `Accepted` until merge", workflow)
        self.assertIn("Never mark an unmerged change", workflow)
        self.assertIn("`Implemented`", workflow)
        self.assertIn("change document remains `Accepted`", compiler)
        self.assertIn("change document remains `Accepted`", benchmark)
        self.assertIn(
            "only the post-merge workflow may change it to `Implemented`",
            self.text,
        )


if __name__ == "__main__":
    unittest.main()
