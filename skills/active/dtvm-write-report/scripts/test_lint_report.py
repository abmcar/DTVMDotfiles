#!/usr/bin/env python3
"""Regression tests for the DTVM report linter."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from lint_report import lint_path  # noqa: E402


def artifact(blocks: list[dict], *, tables=None, datasets=None) -> dict:
    return {
        "surface": "report",
        "manifest": {
            "version": 1,
            "surface": "report",
            "title": "DTVM 冷编译优化",
            "cards": [],
            "charts": [],
            "tables": tables or [],
            "sources": [],
            "blocks": blocks,
        },
        "snapshot": {
            "version": 1,
            "status": "ready",
            "datasets": datasets or {},
        },
        "sources": [],
    }


class ReportLintTests(unittest.TestCase):
    def lint_json(self, payload: dict, **kwargs):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "artifact.json"
            path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            return lint_path(path, **kwargs)

    def test_rejects_template_and_qa_leakage(self) -> None:
        payload = artifact(
            [
                {
                    "id": "title",
                    "type": "markdown",
                    "body": "# DTVM 冷编译优化",
                },
                {
                    "id": "technical_summary",
                    "type": "markdown",
                    "body": (
                        "## 技术摘要\n\n候选耗时从 2000 秒降到 1000 秒（-50%）。"
                        "结论可带限制分享，尚不等于正式 A/B。"
                    ),
                },
                {
                    "id": "scope_and_definitions",
                    "type": "markdown",
                    "body": "## 证据范围与指标定义\n\n" + "范围与定义。" * 80,
                },
                {
                    "id": "method_identity",
                    "type": "markdown",
                    "body": "## 方法保持了源码与构建身份\n\n" + "构建身份。" * 80,
                },
                {
                    "id": "correctness_heading",
                    "type": "markdown",
                    "body": "## 正确性与鲁棒性检查\n\n所有测试通过。",
                },
                {
                    "id": "correctness_table",
                    "type": "table",
                    "tableId": "correctness_gates",
                },
            ],
            tables=[
                {
                    "id": "correctness_gates",
                    "title": "正确性门禁",
                    "dataset": "correctness",
                }
            ],
            datasets={"correctness": [{"result": "PASS"}, {"result": "PASS"}]},
        )
        issues, stats, _ = self.lint_json(payload)
        codes = {issue.code for issue in issues}
        self.assertGreater(stats["support_ratio"], 0.25)
        self.assertTrue(
            {
                "QA_LABEL_LEAK",
                "AB_TERMINOLOGY",
                "GENERIC_HEADING",
                "SUPPORT_RATIO",
                "CORRECTNESS_TABLE",
                "OPENING_DECISION",
            }.issubset(codes)
        )

    def test_accepts_decision_first_report(self) -> None:
        payload = artifact(
            [
                {
                    "id": "title",
                    "type": "markdown",
                    "body": "# 两个线性扫描使 DTVM 冷编译耗时减半",
                },
                {
                    "id": "conclusion",
                    "type": "markdown",
                    "body": (
                        "## 结论：建议保留优化\n\n候选耗时从 2000 秒降到 "
                        "1000 秒（-50%，20 个配对样本）；建议保留两个改动。"
                    ),
                },
                {
                    "id": "mechanism",
                    "type": "markdown",
                    "body": "## 两个重复扫描被消除\n\n索引查找替代全表扫描，反向遍历只访问 use 后缀。",
                },
                {
                    "id": "impact",
                    "type": "markdown",
                    "body": "## 热点已经迁移\n\n目标函数占比从 52% 降到 0.3%，下一热点是寄存器分配。",
                },
                {
                    "id": "next_steps",
                    "type": "markdown",
                    "body": "## 下一步\n\n继续分析寄存器分配，并在完整语料上运行配对 benchmark。",
                },
                {
                    "id": "measurement_note",
                    "type": "markdown",
                    "body": "## 这些数字怎么理解\n\n当前结果覆盖固定工作负载；完整语料尚未复测。",
                },
            ]
        )
        issues, stats, _ = self.lint_json(payload)
        errors = [issue for issue in issues if issue.severity == "error"]
        self.assertEqual([], errors)
        self.assertLessEqual(stats["support_ratio"], 0.25)

    def test_parses_portable_html(self) -> None:
        html = """<!doctype html>
<html><body>
<div class="portable-block" data-artifact-block-id="title"
 data-artifact-block-type="markdown"><h1>两个扫描使编译耗时减半</h1></div>
<div class="portable-block" data-artifact-block-id="conclusion"
 data-artifact-block-type="markdown"><h2>结论：建议保留优化</h2>
 <p>候选耗时从 2000 秒降到 1000 秒（-50%）；建议保留改动。</p>
 <div class="portable-inline-source"><pre class="portable-source-query-data">
 SELECT a_really_long_internal_query_that_must_not_count_as_reader_prose
 FROM evidence_source_metadata
 </pre></div></div>
<div class="portable-block" data-artifact-block-id="mechanism"
 data-artifact-block-type="markdown"><h2>两个重复扫描被消除</h2>
 <p>索引查找替代全表扫描。</p></div>
</body></html>"""
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "report.html"
            path.write_text(html, encoding="utf-8")
            issues, _, fmt = lint_path(path)
        self.assertEqual("html", fmt)
        self.assertFalse(any(issue.severity == "error" for issue in issues))


if __name__ == "__main__":
    unittest.main()
