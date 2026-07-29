#!/usr/bin/env python3
"""Regression tests for the DTVM report linter."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
LINTER_PATH = SCRIPT_DIR / "lint_report.py"
sys.path.insert(0, str(SCRIPT_DIR))

from lint_report import lint_path  # noqa: E402


def artifact(
    blocks: list[dict],
    *,
    title: str = "两个扫描使 DTVM 冷编译耗时减半",
    tables=None,
    datasets=None,
) -> dict:
    return {
        "surface": "report",
        "manifest": {
            "version": 1,
            "surface": "report",
            "title": title,
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

    def lint_markdown(self, body: str, **kwargs):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "report.md"
            path.write_text(body, encoding="utf-8")
            return lint_path(path, **kwargs)

    def lint_html(self, body: str, **kwargs):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "report.html"
            path.write_text(body, encoding="utf-8")
            return lint_path(path, **kwargs)

    def lint_cli_json(self, payload: dict, *args: str):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "artifact.json"
            path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            env = dict(os.environ)
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            return subprocess.run(
                [sys.executable, str(LINTER_PATH), str(path), *args],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )

    def test_rejects_template_and_qa_leakage(self) -> None:
        payload = artifact(
            [
                {
                    "id": "title",
                    "type": "markdown",
                    "body": "# 两个扫描使 DTVM 冷编译耗时减半",
                },
                {
                    "id": "technical_summary",
                    "type": "markdown",
                    "body": (
                        "## 技术摘要\n\n固定 4-block 工作负载的 20 个配对样本中，"
                        "候选耗时从 2000 秒降到 1000 秒，绝对变化为 1000 秒，"
                        "相对降幅 50%。"
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
                        "## 结论：建议保留优化\n\n固定 4-block 工作负载的 "
                        "20 个配对样本中，候选耗时从 2000 秒降到 "
                        "1000 秒，绝对变化为 1000 秒，相对降幅 50%；"
                        "建议保留两个改动。"
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
 <p>固定 4-block workload 的 20 个 paired samples 中，候选耗时从
 2000 秒降到 1000 秒，绝对变化为 1000 秒，相对降幅 50%；
 建议保留改动。</p>
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

    def test_markdown_h3_through_h6_count_toward_support_ratio(self) -> None:
        support = "构建身份、复现命令和采样设置。" * 40
        for level in range(3, 7):
            with self.subTest(level=level):
                report = f"""# 两个扫描使冷编译耗时减半

## 结论：建议保留优化

固定 4-block workload 的 20 个 paired samples 中，耗时从 2000 ms
降到 1000 ms，absolute change 1000 ms，relative reduction 50%；
建议保留改动。

## 两个重复扫描被消除

索引查找替代了全表扫描。热点已经迁移到寄存器分配。

{"#" * level} 方法

{support}
"""
                issues, stats, fmt = self.lint_markdown(report)
                self.assertEqual("markdown", fmt)
                self.assertGreater(stats["support_ratio"], 0.25)
                self.assertIn(
                    "SUPPORT_RATIO", {issue.code for issue in issues}
                )
                self.assertIn(
                    "GENERIC_HEADING", {issue.code for issue in issues}
                )

    def test_heading_sections_are_equivalent_across_formats(self) -> None:
        title = "Two scans halved DTVM cold compilation time"
        result_text = " ".join(
            ["The index lookup removed one full scan."] * 24
        )
        support_text = "Build identity matched."
        for level in range(3, 7):
            markdown = f"""# {title}

## Cold compilation time decreased from 2000 to 1000 ms

{result_text}

```markdown
#### Method
ready to share
```

{"#" * level} Methodology

{support_text}
"""
            html = f"""<!doctype html>
<html><body>
<div class="portable-block" data-artifact-block-id="methodology"
 data-artifact-block-type="markdown">
<h1>{title}</h1>
<h2>Cold compilation time decreased from 2000 to 1000 ms</h2>
<p>{result_text}</p>
<pre><code>#### Method
ready to share</code></pre>
<h{level}>Methodology</h{level}>
<p>{support_text}</p>
</div>
</body></html>"""
            results = {
                "artifact": self.lint_json(
                    artifact(
                        [
                            {
                                "id": "methodology",
                                "type": "markdown",
                                "body": markdown,
                            }
                        ],
                        title=title,
                    ),
                    methods_first=True,
                ),
                "html": self.lint_html(html, methods_first=True),
                "markdown": self.lint_markdown(
                    markdown, methods_first=True
                ),
            }

            expected_stats = None
            expected_codes = None
            for expected_format, result in results.items():
                issues, stats, actual_format = result
                with self.subTest(level=level, format=expected_format):
                    self.assertEqual(expected_format, actual_format)
                    comparable_stats = {
                        key: stats[key]
                        for key in (
                            "total_chars",
                            "support_chars",
                            "support_ratio",
                        )
                    }
                    codes = [issue.code for issue in issues]
                    if expected_stats is None:
                        expected_stats = comparable_stats
                        expected_codes = codes
                    else:
                        self.assertEqual(expected_stats, comparable_stats)
                        self.assertEqual(expected_codes, codes)
                    self.assertLess(stats["support_ratio"], 0.10)
                    self.assertIn("GENERIC_HEADING", codes)
                    self.assertNotIn("QA_LABEL_LEAK", codes)

    def test_support_ancestor_applies_to_nested_heading_only(self) -> None:
        report = """# Two scans halved DTVM cold compilation time

## Cold compilation time decreased

The result section stays on the main reader path.

### Methodology

Build identity matched.

#### Compiler flags matched the baseline

The same compiler flags and source commit were used for every repetition.

## The hotspot shifted to register allocation

The next result section is back on the main reader path.
"""
        _, stats, _ = self.lint_markdown(report, methods_first=True)
        expected_support = len(
            "".join(
                (
                    "Methodology",
                    "Build identity matched.",
                    "Compiler flags matched the baseline",
                    "The same compiler flags and source commit were used "
                    "for every repetition.",
                )
            ).replace(" ", "")
        )
        self.assertEqual(expected_support, stats["support_chars"])

    def test_fenced_markdown_heading_is_not_a_section(self) -> None:
        report = """# Two scans halved DTVM cold compilation time

## The parser kept code examples out of report structure

The reader-facing result remains concise.

```markdown
### Methodology
This fenced example is not reader-facing report prose.
```
"""
        issues, stats, _ = self.lint_markdown(report, methods_first=True)
        self.assertNotIn("GENERIC_HEADING", {issue.code for issue in issues})
        self.assertEqual(0, stats["support_chars"])

    def test_cli_does_not_leave_bytecode_cache(self) -> None:
        cache_before = set(SCRIPT_DIR.rglob("__pycache__")) | set(
            SCRIPT_DIR.rglob("*.pyc")
        )
        payload = artifact(
            [
                {
                    "id": "title",
                    "type": "markdown",
                    "body": "# Two scans halved cold compilation time",
                },
                {
                    "id": "conclusion",
                    "type": "markdown",
                    "body": (
                        "## Cold compilation time decreased\n\n"
                        "On ERC-20 over 20 iterations, time fell from 2000 "
                        "to 1000 ms; absolute reduction 1000 ms; relative "
                        "reduction 50%. Retain the change."
                    ),
                },
            ],
            title="Two scans halved cold compilation time",
        )
        result = self.lint_cli_json(payload)
        self.assertEqual(0, result.returncode, result.stdout)
        cache_after = set(SCRIPT_DIR.rglob("__pycache__")) | set(
            SCRIPT_DIR.rglob("*.pyc")
        )
        self.assertEqual(cache_before, cache_after)

    def test_long_h1_is_not_treated_as_the_opening(self) -> None:
        long_title = "两个重复线性扫描被消除并使固定工作负载上的冷编译耗时减半" * 4
        report = f"""# {long_title}

## 结论：建议保留优化

固定 4-block workload 的 20 个 paired samples 中，耗时从 2000 ms
降到 1000 ms，absolute change 1000 ms，relative reduction 50%；
建议保留改动。
"""
        issues, _, _ = self.lint_markdown(report)
        codes = {issue.code for issue in issues}
        self.assertNotIn("OPENING_EFFECT", codes)
        self.assertNotIn("OPENING_DECISION", codes)

    def test_percentage_only_is_not_a_quantified_effect(self) -> None:
        payload = artifact(
            [
                {
                    "id": "title",
                    "type": "markdown",
                    "body": "# DTVM 测试覆盖率达到 100%",
                },
                {
                    "id": "conclusion",
                    "type": "markdown",
                    "body": (
                        "## 结论：建议采用\n\n固定 workload 的 20 个样本中，"
                        "覆盖率 100%；建议采用这项改动。"
                    ),
                },
            ]
        )
        issues, _, _ = self.lint_json(payload)
        opening_effect = [
            issue for issue in issues if issue.code == "OPENING_EFFECT"
        ]
        self.assertEqual(1, len(opening_effect))
        self.assertIn("baseline/candidate", opening_effect[0].message)

    def test_generic_title_is_a_cli_error_in_all_modes(self) -> None:
        generic_titles = (
            "DTVM 性能报告",
            "DTVM cold compilation optimization",
            "DTVM cold compilation improvement analysis",
            "DTVM should merge-base",
        )
        for title in generic_titles:
            payload = artifact(
                [
                    {
                        "id": "title",
                        "type": "markdown",
                        "body": f"# {title}",
                    },
                    {
                        "id": "conclusion",
                        "type": "markdown",
                        "body": (
                            "## 结论：建议采用\n\n固定 workload 的 20 个样本中，"
                            "覆盖率 100%；建议采用这项改动。"
                        ),
                    },
                ],
                title=title,
            )
            issues, _, _ = self.lint_json(payload)
            by_code = {issue.code: issue for issue in issues}
            self.assertEqual("error", by_code["GENERIC_TITLE"].severity)
            self.assertIn("OPENING_EFFECT", by_code)

            for args in ((), ("--methods-first",)):
                with self.subTest(title=title, args=args):
                    result = self.lint_cli_json(payload, *args)
                    self.assertEqual(1, result.returncode)
                    self.assertIn("ERROR [GENERIC_TITLE]", result.stdout)

    def test_observed_result_and_explicit_decision_titles_pass(self) -> None:
        titles = (
            "DTVM 冷编译耗时下降",
            "热点迁移到寄存器分配",
            "DTVM cold compilation time decreased",
            "Retain the cold-path change",
        )
        for title in titles:
            with self.subTest(title=title):
                payload = artifact(
                    [
                        {
                            "id": "title",
                            "type": "markdown",
                            "body": f"# {title}",
                        },
                        {
                            "id": "result",
                            "type": "markdown",
                            "body": (
                                "## Result\n\nThis explicitly requested "
                                "methods-first note records the observed "
                                "outcome for review."
                            ),
                        },
                    ],
                    title=title,
                )
                issues, _, _ = self.lint_json(
                    payload, methods_first=True
                )
                self.assertNotIn(
                    "GENERIC_TITLE", {issue.code for issue in issues}
                )

    def test_hyphenated_words_are_not_decisions(self) -> None:
        for phrase in ("merge-base", "pre-merge", "stop-the-world"):
            with self.subTest(phrase=phrase):
                payload = artifact(
                    [
                        {
                            "id": "title",
                            "type": "markdown",
                            "body": "# ERC-20 cold compilation time halved",
                        },
                        {
                            "id": "conclusion",
                            "type": "markdown",
                            "body": (
                                "## Cold compilation time decreased\n\n"
                                "On ERC-20 over 20 iterations, cold compilation "
                                "fell from 2000 to 1000 ms; absolute reduction "
                                "1000 ms; relative reduction 50%. The "
                                f"{phrase} measurement stayed fixed."
                            ),
                        },
                    ],
                    title="ERC-20 cold compilation time halved",
                )
                issues, _, _ = self.lint_json(payload)
                self.assertIn(
                    "OPENING_DECISION", {issue.code for issue in issues}
                )

    def test_natural_comparison_language_is_accepted(self) -> None:
        cases = {
            "english_shared_unit": (
                "ERC-20 cold compilation time halved",
                (
                    "On ERC-20 over 20 iterations, cold compilation fell "
                    "from 2000 to 1000 ms; absolute reduction 1000 ms; "
                    "relative reduction 50%. Retain the change."
                ),
            ),
            "chinese_from_shared_unit": (
                "ERC-20 冷编译耗时减半",
                (
                    "在固定 ERC-20 工作负载上重复测量 20 次，冷编译耗时"
                    "从 2000 降至 1000 毫秒，绝对变化为 1000 毫秒，"
                    "相对降低 50%；建议保留改动。"
                ),
            ),
            "chinese_from_origin": (
                "ERC-20 冷编译耗时减半",
                (
                    "在固定 ERC-20 工作负载上重复测量 20 次，冷编译耗时"
                    "由 2000 毫秒降至 1000 毫秒，绝对变化为 1000 毫秒，"
                    "相对降低 50%；建议保留改动。"
                ),
            ),
        }
        for name, (title, opening) in cases.items():
            with self.subTest(name=name):
                payload = artifact(
                    [
                        {
                            "id": "title",
                            "type": "markdown",
                            "body": f"# {title}",
                        },
                        {
                            "id": "conclusion",
                            "type": "markdown",
                            "body": f"## 结论\n\n{opening}",
                        },
                    ],
                    title=title,
                )
                issues, _, _ = self.lint_json(payload)
                self.assertNotIn(
                    "OPENING_EFFECT", {issue.code for issue in issues}
                )

    def test_workload_size_is_not_a_sample_count(self) -> None:
        payload = artifact(
            [
                {
                    "id": "title",
                    "type": "markdown",
                    "body": "# 固定区块工作负载上的冷编译耗时减半",
                },
                {
                    "id": "conclusion",
                    "type": "markdown",
                    "body": (
                        "## 冷编译耗时下降\n\n固定 4 个区块工作负载中，耗时"
                        "从 2000 降至 1000 毫秒，绝对变化为 1000 毫秒，"
                        "相对降低 50%；建议保留改动。"
                    ),
                },
            ],
            title="固定区块工作负载上的冷编译耗时减半",
        )
        issues, _, _ = self.lint_json(payload)
        opening_effect = [
            issue for issue in issues if issue.code == "OPENING_EFFECT"
        ]
        self.assertEqual(1, len(opening_effect))
        self.assertTrue(
            opening_effect[0].message.endswith("missing: sample count."),
            opening_effect[0].message,
        )

    def test_quantified_effect_reports_each_missing_field(self) -> None:
        cases = {
            "baseline/candidate": (
                (
                    "固定 block workload 的 20 个配对样本中，耗时绝对变化为 "
                    "1000 ms，相对降幅 50%；建议保留优化。"
                ),
                ("baseline/candidate", "unit"),
            ),
            "absolute change": (
                (
                    "固定 block workload 的 20 个配对样本中，baseline 为 "
                    "2000 ms，candidate 为 1000 ms，相对降幅 50%；"
                    "建议保留优化。"
                ),
                ("absolute change",),
            ),
            "relative change": (
                (
                    "固定 block workload 的 20 个配对样本中，baseline 为 "
                    "40%，candidate 为 20%，absolute change 20 pp；"
                    "建议保留优化。"
                ),
                ("relative change",),
            ),
            "unit": (
                (
                    "固定 block workload 的 20 个配对样本中，baseline 为 "
                    "2000，candidate 为 1000，绝对变化为 1000，"
                    "相对降幅 50%；建议保留优化。"
                ),
                ("unit",),
            ),
            "unit from unrelated percentage": (
                (
                    "固定 block workload 的 20 个配对样本中，耗时从 "
                    "2000 降到 1000，覆盖率 100%，绝对变化为 1000，"
                    "相对降幅 50%；建议保留优化。"
                ),
                ("unit",),
            ),
            "workload": (
                (
                    "20 个配对样本中，耗时从 2000 ms 降到 1000 ms，"
                    "绝对变化为 1000 ms，相对降幅 50%；建议保留优化。"
                ),
                ("workload",),
            ),
            "sample count": (
                (
                    "固定 block workload 中，耗时从 2000 ms 降到 1000 ms，"
                    "绝对变化为 1000 ms，相对降幅 50%；建议保留优化。"
                ),
                ("sample count",),
            ),
        }
        for missing_field, (opening, expected_missing) in cases.items():
            with self.subTest(missing_field=missing_field):
                payload = artifact(
                    [
                        {
                            "id": "title",
                            "type": "markdown",
                            "body": "# 冷编译耗时减半",
                        },
                        {
                            "id": "conclusion",
                            "type": "markdown",
                            "body": f"## 结论\n\n{opening}",
                        },
                    ]
                )
                issues, _, _ = self.lint_json(payload)
                messages = [
                    issue.message
                    for issue in issues
                    if issue.code == "OPENING_EFFECT"
                ]
                self.assertEqual(1, len(messages))
                self.assertTrue(
                    messages[0].endswith(
                        f"missing: {', '.join(expected_missing)}."
                    ),
                    messages[0],
                )


if __name__ == "__main__":
    unittest.main()
