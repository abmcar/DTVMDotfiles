#!/usr/bin/env python3
"""Lint reader-facing DTVM reports for hierarchy and terminology."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


HEADING_RE = re.compile(r"(?m)^(#{1,6})\s+(.+?)\s*$")
SUPPORT_RE = re.compile(
    r"(scope|method|correctness|robust|limit|caveat|repro|identity|"
    r"validation|instrumentation|measurement|definition|audit|"
    r"范围|方法|正确|鲁棒|限制|复现|身份|验证|门禁|定义|测量|审计)",
    re.IGNORECASE,
)
EFFECT_RE = re.compile(
    r"(%|％|×|→|->|\b\d+(?:\.\d+)?\s*(?:ms|s|sec|seconds?|x)\b|"
    r"\d+(?:\.\d+)?\s*(?:秒|毫秒|分钟|小时)|"
    r"从.{0,50}(?:降到|降至|升到|升至|提高到|缩短到))",
    re.IGNORECASE,
)
DECISION_RE = re.compile(
    r"(建议|保留|采用|合入|回退|继续|停止|优先|暂缓|不合入|"
    r"retain|adopt|merge|ship|revert|continue|stop|prioriti[sz]e|defer)",
    re.IGNORECASE,
)
AB_RE = re.compile(r"(?i)(?<![A-Za-z])A\s*[/／]\s*B(?![A-Za-z])|\bA-B\s+test")

BANNED_PHRASES = (
    "可带限制分享",
    "结论可带限制分享",
    "share with caveats",
    "ready to share",
    "needs revision",
    "诊断夹定",
    "方向性证据",
    "尚不等于正式",
)

GENERIC_HEADINGS = {
    "证据范围与指标定义",
    "方法保持了源码与构建身份",
    "正确性与鲁棒性检查",
    "方法论",
    "实验方法",
    "限制与鲁棒性",
    "scope, data, and metric definitions",
    "methodology",
    "limitations, uncertainty, and robustness checks",
    "validation report",
    "methodology review",
    "required caveats for stakeholders",
}

PASS_WORDS = {"pass", "passed", "ok", "success", "green", "通过"}


@dataclass
class ReaderBlock:
    block_id: str
    kind: str
    text: str
    headings: list[tuple[int, str]] = field(default_factory=list)
    table_id: str | None = None


@dataclass
class ReportDocument:
    title: str
    blocks: list[ReaderBlock]
    tables: dict[str, dict[str, Any]] = field(default_factory=dict)
    datasets: dict[str, list[dict[str, Any]]] = field(default_factory=dict)

    @property
    def reader_text(self) -> str:
        return "\n".join(block.text for block in self.blocks)


@dataclass
class Issue:
    severity: str
    code: str
    message: str


class PortableHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.blocks: list[ReaderBlock] = []
        self._block: dict[str, Any] | None = None
        self._block_depth = 0
        self._capture_heading: tuple[int, list[str]] | None = None
        self._capture_title = False
        self._ignored_depth = 0
        self._source_ignore_depth = 0

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        attr = {key: value or "" for key, value in attrs}
        if tag in {"script", "style", "template"}:
            self._ignored_depth += 1
            return
        if self._ignored_depth:
            return

        classes = set(attr.get("class", "").split())
        if self._block is None and "portable-block" in classes:
            self._block = {
                "id": attr.get("data-artifact-block-id", ""),
                "kind": attr.get("data-artifact-block-type", ""),
                "text": [],
                "headings": [],
            }
            self._block_depth = 1
        elif self._block is not None:
            self._block_depth += 1

        ignored_source_classes = {
            "portable-inline-source",
            "portable-source-tooltip-content",
            "portable-source-query",
            "portable-source-query-data",
        }
        if self._source_ignore_depth:
            self._source_ignore_depth += 1
            return
        if self._block is not None and classes & ignored_source_classes:
            self._source_ignore_depth = 1
            return

        if tag == "h1":
            self._capture_title = True
        if tag == "h1" or (
            self._block is not None
            and self._block["kind"] == "markdown"
            and tag in {"h2", "h3", "h4", "h5", "h6"}
        ):
            self._capture_heading = (int(tag[1]), [])

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "template"} and self._ignored_depth:
            self._ignored_depth -= 1
            return
        if self._ignored_depth:
            return

        if self._source_ignore_depth:
            self._source_ignore_depth -= 1
            if self._block is not None:
                self._block_depth -= 1
            return

        if self._capture_heading and tag == f"h{self._capture_heading[0]}":
            level, parts = self._capture_heading
            heading = normalize_space("".join(parts))
            if self._block is not None and heading:
                self._block["headings"].append((level, heading))
            if level == 1 and not self.title:
                self.title = heading
            self._capture_heading = None
        if tag == "h1":
            self._capture_title = False

        if self._block is not None:
            self._block_depth -= 1
            if self._block_depth == 0:
                text = normalize_space(" ".join(self._block["text"]))
                self.blocks.append(
                    ReaderBlock(
                        block_id=self._block["id"],
                        kind=self._block["kind"],
                        text=text,
                        headings=self._block["headings"],
                    )
                )
                self._block = None

    def handle_data(self, data: str) -> None:
        if self._ignored_depth or self._source_ignore_depth:
            return
        if self._capture_heading is not None:
            self._capture_heading[1].append(data)
        if self._capture_title and not self.title:
            self.title += data
        if self._block is not None:
            self._block["text"].append(data)


def normalize_space(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def strip_markdown(text: str) -> str:
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"(?m)^#{1,6}\s+", "", text)
    text = re.sub(r"(?m)^\s*[-*+]\s+", "", text)
    text = re.sub(r"(?m)^\s*\d+[.)]\s+", "", text)
    text = text.replace("**", "").replace("__", "").replace("*", "")
    return normalize_space(text)


def markdown_headings(text: str) -> list[tuple[int, str]]:
    return [
        (len(match.group(1)), strip_markdown(match.group(2)))
        for match in HEADING_RE.finditer(text)
    ]


def parse_artifact(path: Path) -> ReportDocument:
    data = json.loads(path.read_text(encoding="utf-8"))
    manifest = data.get("manifest", {})
    cards = {card["id"]: card for card in manifest.get("cards", [])}
    charts = {chart["id"]: chart for chart in manifest.get("charts", [])}
    tables = {table["id"]: table for table in manifest.get("tables", [])}
    datasets = data.get("snapshot", {}).get("datasets", {})
    blocks: list[ReaderBlock] = []

    for raw in manifest.get("blocks", []):
        kind = raw.get("type", "")
        block_id = raw.get("id", "")
        table_id: str | None = None
        if kind == "markdown":
            body = raw.get("body", "")
            text = strip_markdown(body)
            headings = markdown_headings(body)
        elif kind == "chart":
            chart = charts.get(raw.get("chartId"), {})
            text = normalize_space(
                " ".join(
                    str(chart.get(key, ""))
                    for key in ("title", "subtitle", "headerMarkdown")
                )
            )
            headings = []
        elif kind == "table":
            table_id = raw.get("tableId")
            table = tables.get(table_id, {})
            rows = datasets.get(table.get("dataset", ""), [])
            row_text = " ".join(
                " ".join(str(value) for value in row.values()) for row in rows
            )
            text = normalize_space(
                f"{table.get('title', '')} {table.get('subtitle', '')} {row_text}"
            )
            headings = []
        elif kind == "metric-strip":
            selected = [cards.get(card_id, {}) for card_id in raw.get("cardIds", [])]
            parts: list[str] = []
            for card in selected:
                parts.append(str(card.get("description", "")))
                parts.extend(
                    str(metric.get("label", ""))
                    for metric in card.get("metrics", [])
                )
            text = normalize_space(" ".join(parts))
            headings = []
        else:
            text = normalize_space(str(raw))
            headings = []
        blocks.append(
            ReaderBlock(
                block_id=block_id,
                kind=kind,
                text=text,
                headings=headings,
                table_id=table_id,
            )
        )

    return ReportDocument(
        title=manifest.get("title", ""),
        blocks=blocks,
        tables=tables,
        datasets=datasets,
    )


def parse_html(path: Path) -> ReportDocument:
    parser = PortableHTMLParser()
    parser.feed(path.read_text(encoding="utf-8"))
    return ReportDocument(title=normalize_space(parser.title), blocks=parser.blocks)


def parse_markdown(path: Path) -> ReportDocument:
    text = path.read_text(encoding="utf-8")
    title = ""
    blocks: list[ReaderBlock] = []
    current: list[str] = []
    current_heading: tuple[int, str] | None = None

    for line in text.splitlines():
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if match:
            level = len(match.group(1))
            heading = strip_markdown(match.group(2))
            if level == 1 and not title:
                title = heading
            if level == 2 and current:
                body = "\n".join(current)
                blocks.append(
                    ReaderBlock(
                        block_id="",
                        kind="markdown",
                        text=strip_markdown(body),
                        headings=[current_heading] if current_heading else [],
                    )
                )
                current = []
            if level == 2:
                current_heading = (level, heading)
            current.append(line)
        else:
            current.append(line)

    if current:
        body = "\n".join(current)
        blocks.append(
            ReaderBlock(
                block_id="",
                kind="markdown",
                text=strip_markdown(body),
                headings=[current_heading] if current_heading else [],
            )
        )
    return ReportDocument(title=title, blocks=blocks)


def parse_document(path: Path, requested_format: str) -> tuple[str, ReportDocument]:
    fmt = requested_format
    if fmt == "auto":
        if path.suffix.lower() == ".html":
            fmt = "html"
        elif path.suffix.lower() == ".json":
            fmt = "artifact"
        else:
            fmt = "markdown"
    if fmt == "artifact":
        return fmt, parse_artifact(path)
    if fmt == "html":
        return fmt, parse_html(path)
    return fmt, parse_markdown(path)


def visible_char_count(text: str) -> int:
    return len(re.sub(r"\s+", "", text))


def block_is_support(block: ReaderBlock) -> bool:
    if SUPPORT_RE.search(block.block_id):
        return True
    return any(SUPPORT_RE.search(heading) for _, heading in block.headings)


def first_substantive_block(document: ReportDocument) -> ReaderBlock | None:
    for block in document.blocks:
        if block.block_id == "title":
            continue
        non_title_headings = [heading for level, heading in block.headings if level > 1]
        text = block.text
        if non_title_headings or visible_char_count(text) >= 40:
            return block
    return None


def table_is_all_pass(
    table: dict[str, Any], datasets: dict[str, list[dict[str, Any]]]
) -> bool:
    rows = datasets.get(table.get("dataset", ""), [])
    if not rows:
        return False
    values: list[str] = []
    for row in rows:
        for key in ("result", "status", "outcome"):
            if key in row:
                values.append(str(row[key]).strip().lower())
                break
    return bool(values) and all(value in PASS_WORDS for value in values)


def lint_document(
    document: ReportDocument,
    *,
    methods_first: bool,
    randomized_ab: bool,
    max_support_ratio: float,
    max_sections: int,
) -> tuple[list[Issue], dict[str, Any]]:
    issues: list[Issue] = []
    reader_text = document.reader_text
    reader_text_lower = reader_text.lower()
    headings = [
        (level, heading)
        for block in document.blocks
        for level, heading in block.headings
    ]
    h2_headings = [heading for level, heading in headings if level == 2]

    narrative_blocks = [
        block
        for block in document.blocks
        if block.block_id != "title" and visible_char_count(block.text)
    ]
    total_chars = sum(visible_char_count(block.text) for block in narrative_blocks)
    support_chars = sum(
        visible_char_count(block.text)
        for block in narrative_blocks
        if block_is_support(block)
    )
    support_ratio = support_chars / total_chars if total_chars else 0.0

    for phrase in BANNED_PHRASES:
        if phrase.lower() in reader_text_lower:
            issues.append(
                Issue(
                    "error",
                    "QA_LABEL_LEAK",
                    f"Internal QA/process phrase appears in reader text: {phrase!r}.",
                )
            )

    if AB_RE.search(reader_text) and not randomized_ab:
        issues.append(
            Issue(
                "error",
                "AB_TERMINOLOGY",
                "A/B terminology requires randomized concurrent treatment/control; "
                "use baseline–candidate or paired benchmark.",
            )
        )

    for heading in h2_headings:
        normalized = normalize_space(heading).strip("：:。.!！").lower()
        if normalized in GENERIC_HEADINGS:
            issues.append(
                Issue(
                    "error",
                    "GENERIC_HEADING",
                    f"Generic template role leaked into a visible heading: {heading!r}.",
                )
            )

    if len(h2_headings) > max_sections and not methods_first:
        issues.append(
            Issue(
                "error",
                "SECTION_COUNT",
                f"{len(h2_headings)} major sections exceed the default limit "
                f"of {max_sections}.",
            )
        )

    support_sections = [
        heading for heading in h2_headings if SUPPORT_RE.search(heading)
    ]
    if len(support_sections) > 1 and not methods_first:
        issues.append(
            Issue(
                "error",
                "SUPPORT_SECTION_COUNT",
                "More than one independent method/scope/correctness/limitation "
                "section appears in the main reading path.",
            )
        )

    if support_ratio > max_support_ratio and not methods_first:
        issues.append(
            Issue(
                "error",
                "SUPPORT_RATIO",
                f"Support/audit content is {support_ratio:.1%}; the default maximum "
                f"is {max_support_ratio:.0%}.",
            )
        )

    opening = first_substantive_block(document)
    if opening is None:
        issues.append(
            Issue("error", "EMPTY_REPORT", "No substantive reader-facing block found.")
        )
    elif not methods_first:
        if not EFFECT_RE.search(opening.text):
            issues.append(
                Issue(
                    "error",
                    "OPENING_EFFECT",
                    "The first substantive block does not state a quantified effect.",
                )
            )
        if not DECISION_RE.search(opening.text):
            issues.append(
                Issue(
                    "error",
                    "OPENING_DECISION",
                    "The first substantive block does not state the recommended decision.",
                )
            )

    if document.tables and not methods_first:
        for table_id, table in document.tables.items():
            table_text = f"{table_id} {table.get('title', '')}"
            if SUPPORT_RE.search(table_text) and table_is_all_pass(
                table, document.datasets
            ):
                issues.append(
                    Issue(
                        "error",
                        "CORRECTNESS_TABLE",
                        f"All-pass correctness table {table_id!r} belongs in "
                        "supporting evidence; summarize it in one sentence.",
                    )
                )

    if re.search(r"(诊断|性能|实验|技术|分析)?报告\s*$|\breport\s*$", document.title):
        issues.append(
            Issue(
                "warning",
                "GENERIC_TITLE",
                "Prefer a result-bearing title over a generic report label.",
            )
        )

    prose_text = "\n".join(
        block.text for block in document.blocks if block.kind == "markdown"
    )
    long_sentences = [
        sentence
        for sentence in re.split(r"[。！？!?]", prose_text)
        if visible_char_count(sentence) > 120
    ]
    if long_sentences:
        longest = max(long_sentences, key=visible_char_count)
        excerpt = normalize_space(longest)[:80]
        issues.append(
            Issue(
                "warning",
                "LONG_SENTENCE",
                f"{len(long_sentences)} sentence(s) exceed 120 non-space "
                f"characters; longest starts with {excerpt!r}.",
            )
        )

    stats = {
        "title": document.title,
        "major_sections": len(h2_headings),
        "total_chars": total_chars,
        "support_chars": support_chars,
        "support_ratio": support_ratio,
        "errors": sum(issue.severity == "error" for issue in issues),
        "warnings": sum(issue.severity == "warning" for issue in issues),
    }
    return issues, stats


def lint_path(
    path: Path,
    *,
    requested_format: str = "auto",
    methods_first: bool = False,
    randomized_ab: bool = False,
    max_support_ratio: float = 0.25,
    max_sections: int = 6,
) -> tuple[list[Issue], dict[str, Any], str]:
    fmt, document = parse_document(path, requested_format)
    issues, stats = lint_document(
        document,
        methods_first=methods_first,
        randomized_ab=randomized_ab,
        max_support_ratio=max_support_ratio,
        max_sections=max_sections,
    )
    return issues, stats, fmt


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint a DTVM report artifact, portable HTML, or Markdown file."
    )
    parser.add_argument("path", type=Path)
    parser.add_argument(
        "--format",
        choices=("auto", "artifact", "html", "markdown"),
        default="auto",
    )
    parser.add_argument("--methods-first", action="store_true")
    parser.add_argument("--randomized-ab", action="store_true")
    parser.add_argument("--max-support-ratio", type=float, default=0.25)
    parser.add_argument("--max-sections", type=int, default=6)
    args = parser.parse_args()

    if not args.path.is_file():
        print(f"ERROR: report not found: {args.path}", file=sys.stderr)
        return 2
    if not 0 <= args.max_support_ratio <= 1:
        print("ERROR: --max-support-ratio must be between 0 and 1", file=sys.stderr)
        return 2

    try:
        issues, stats, fmt = lint_path(
            args.path,
            requested_format=args.format,
            methods_first=args.methods_first,
            randomized_ab=args.randomized_ab,
            max_support_ratio=args.max_support_ratio,
            max_sections=args.max_sections,
        )
    except (json.JSONDecodeError, OSError, ValueError) as exc:
        print(f"ERROR: unable to parse {args.path}: {exc}", file=sys.stderr)
        return 2

    status = "FAIL" if stats["errors"] else "PASS"
    print(
        f"DTVM report lint: {status} "
        f"(format={fmt}, sections={stats['major_sections']}, "
        f"support={stats['support_ratio']:.1%}, "
        f"errors={stats['errors']}, warnings={stats['warnings']})"
    )
    for issue in issues:
        print(f"{issue.severity.upper()} [{issue.code}] {issue.message}")
    return 1 if stats["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
