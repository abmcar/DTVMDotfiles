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


SUPPORT_RE = re.compile(
    r"(scope|method|correctness|robust|limit|caveat|repro|identity|"
    r"validation|instrumentation|measurement|definition|audit|"
    r"范围|方法|正确|鲁棒|限制|复现|身份|验证|门禁|定义|测量|审计)",
    re.IGNORECASE,
)
UNSIGNED_NUMBER_PATTERN = r"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"
NUMBER_PATTERN = rf"[+-]?{UNSIGNED_NUMBER_PATTERN}"
BARE_NUMBER_PATTERN = rf"{NUMBER_PATTERN}(?![\d,.])"
NUMBER_RE = re.compile(BARE_NUMBER_PATTERN)
UNIT_PATTERN = (
    r"(?:ns|us|µs|μs|ms|s|sec(?:ond)?s?|minutes?|hours?|cycles?|"
    r"instructions?|bytes?|KiB|MiB|GiB|KB|MB|GB|gas|%|％|pp|"
    r"percentage\s+points?|x|×|calls?|queries?|comparisons?|"
    r"errors?|failures?|mismatches?|sections?|blocks?|transactions?|txs?|"
    r"纳秒|微秒|毫秒|秒|分钟|小时|周期|指令|字节|百分点|次调用|次查询|"
    r"次比较|个章节|个区块|笔交易|个主?差异|项主?差异)"
)
MEASUREMENT_PATTERN = rf"{NUMBER_PATTERN}\s*{UNIT_PATTERN}(?![A-Za-z])"
MEASUREMENT_RE = re.compile(
    MEASUREMENT_PATTERN,
    re.IGNORECASE,
)
ABSOLUTE_UNIT_PATTERN = (
    r"(?:ns|us|µs|μs|ms|s|sec(?:ond)?s?|minutes?|hours?|cycles?|"
    r"instructions?|bytes?|KiB|MiB|GiB|KB|MB|GB|gas|pp|"
    r"percentage\s+points?|calls?|queries?|comparisons?|"
    r"errors?|failures?|mismatches?|sections?|blocks?|transactions?|txs?|"
    r"纳秒|微秒|毫秒|秒|分钟|小时|周期|指令|字节|百分点|次调用|次查询|"
    r"次比较|个章节|个区块|笔交易|个主?差异|项主?差异)"
)
ABSOLUTE_VALUE_PATTERN = (
    rf"{BARE_NUMBER_PATTERN}(?:\s*{ABSOLUTE_UNIT_PATTERN}(?![A-Za-z]))?"
    r"(?!\s*(?:%|％|x|×))"
)
BASELINE_LABEL_RE = re.compile(
    r"(?:\bbaseline\b|\breference\b|\bbefore\b|基线|参考|优化前|修复前|"
    r"原(?:始|报告|版本))",
    re.IGNORECASE,
)
CANDIDATE_LABEL_RE = re.compile(
    r"(?:\bcandidate\b|\bafter\b|\bfinal\b|候选|优化后|修复后|新版本|最终)",
    re.IGNORECASE,
)
FROM_TO_NUMERIC_RE = re.compile(
    rf"(?:from|从|由)\s*.{{0,50}}?{BARE_NUMBER_PATTERN}"
    rf".{{0,50}}?(?:to|降到|降至|升到|升至|提高到|缩短到|变为|减为)"
    rf"\s*{BARE_NUMBER_PATTERN}",
    re.IGNORECASE,
)
COMPARISON_CONNECTOR_PATTERN = (
    r"(?:to|降到|降至|升到|升至|提高到|缩短到|变为|减为)"
)
FROM_TO_SHARED_UNIT_RE = re.compile(
    rf"(?:from|从|由)\s*.{{0,50}}?"
    rf"(?:"
    rf"{MEASUREMENT_PATTERN}.{{0,50}}?{COMPARISON_CONNECTOR_PATTERN}"
    rf"\s*{BARE_NUMBER_PATTERN}|"
    rf"{BARE_NUMBER_PATTERN}.{{0,50}}?{COMPARISON_CONNECTOR_PATTERN}"
    rf"\s*{MEASUREMENT_PATTERN}"
    rf")",
    re.IGNORECASE,
)
NUMERIC_ARROW_RE = re.compile(
    rf"{BARE_NUMBER_PATTERN}\s*(?:→|->|到)\s*{BARE_NUMBER_PATTERN}",
    re.IGNORECASE,
)
SHARED_UNIT_ARROW_RE = re.compile(
    rf"(?:"
    rf"{MEASUREMENT_PATTERN}\s*(?:→|->|到)\s*{BARE_NUMBER_PATTERN}|"
    rf"{BARE_NUMBER_PATTERN}\s*(?:→|->|到)\s*{MEASUREMENT_PATTERN}"
    rf")",
    re.IGNORECASE,
)
RELATIVE_CHANGE_RE = re.compile(
    rf"(?:{NUMBER_PATTERN}\s*(?:%|％|x|×)\s*"
    r"(?:reduction|increase|decrease|improvement|regression|faster|slower|"
    r"relative\s+(?:change|reduction|increase)|"
    r"相对(?:降幅|增幅|变化|降低|下降|减少|提高|提升|增加)|"
    r"降幅|增幅|变化|提升|改善|回退)|"
    r"(?:relative\s+(?:change|reduction|increase)|"
    r"reduction|increase|decrease|improvement|regression|"
    r"faster|slower|相对(?:降幅|增幅|变化|降低|下降|减少|提高|提升|增加)|"
    r"降幅|增幅|变化|提升|改善|回退)"
    rf".{{0,30}}?{NUMBER_PATTERN}\s*(?:%|％|x|×)|"
    rf"[+−-]{UNSIGNED_NUMBER_PATTERN}\s*(?:%|％))",
    re.IGNORECASE,
)
ABSOLUTE_CHANGE_RE = re.compile(
    rf"(?:absolute\s+(?:change|delta|reduction|increase)|delta)"
    rf"\s*(?:of|=|:)?\s*{ABSOLUTE_VALUE_PATTERN}|"
    r"(?:reduced?|decreased?|increased?|improved?|regressed?|changed?|"
    rf"fell|rose|dropped|saved)\s+by\s+{ABSOLUTE_VALUE_PATTERN}|"
    rf"(?:绝对变化|绝对差值|变化量|差值)\s*(?:为|是|[:：=])?\s*"
    rf"{ABSOLUTE_VALUE_PATTERN}|"
    rf"(?:减少|降低|下降|增加|上升|提升|缩短|节省)(?:了|约)?\s*"
    rf"{ABSOLUTE_VALUE_PATTERN}",
    re.IGNORECASE,
)
WORKLOAD_RE = re.compile(
    r"(?:workload|corpus|benchmark|fixture|dataset|reader-facing\s+text|"
    r"report\s+body|cold\s+(?:compile|process)|ERC-?20|工作负载|语料|基准|夹具|"
    r"数据集|正文|冷编译|冷进程|区块|交易)",
    re.IGNORECASE,
)
SAMPLE_COUNT_RE = re.compile(
    rf"(?:\bn\s*=\s*{NUMBER_PATTERN}\b|"
    rf"{NUMBER_PATTERN}\s*(?:个|组|对|次|轮|份|条|笔)?\s*"
    r"(?:paired\s+)?(?:samples?|reps?|repetitions?|runs?|trials?|"
    r"iterations?|process(?:es)?|observations?|measurements?|"
    r"配对样本|样本|重复|轮次|进程|观测|测量)|"
    r"(?:one|single|一|单)(?:\s+|个|次|轮)?"
    r"(?:cold\s+process|process|observation|run|冷进程|进程|观测)|"
    rf"(?:重复测量|重复|测量).{{0,12}}?{NUMBER_PATTERN}\s*次)",
    re.IGNORECASE,
)
ENGLISH_DECISION_PATTERN = (
    r"(?<![A-Za-z0-9_-])"
    r"(?:retain|adopt|merge|ship|revert|continue|stop|prioriti[sz]e|defer)"
    r"(?![A-Za-z0-9_-])"
)
DECISION_RE = re.compile(
    r"(?:建议|保留|采用|合入|回退|继续|停止|优先|暂缓|不合入)|"
    rf"{ENGLISH_DECISION_PATTERN}",
    re.IGNORECASE,
)
TITLE_OUTCOME_RE = re.compile(
    r"(?<![A-Za-z0-9_-])"
    r"(?:reduces|reduced|decreases|decreased|increases|increased|"
    r"improves|improved|eliminates|eliminated|removes|removed|"
    r"moves|moved|shifts|shifted|matches|matched|passes|passed|"
    r"fails|failed|blocks|blocked|halves|halved|cuts|stabilizes|"
    r"stabilized|zeroes|zeroed)"
    r"(?![A-Za-z0-9_-])|"
    r"(?:已|已经|成功|仍|未|被|使).{0,40}?"
    r"(?:降低|降至|降到|下降|减少|减半|提升|提高|增加|加速|消除|"
    r"移除|迁移|归零|通过|失败|阻止|一致|收敛|回退)|"
    r"(?:降低|降至|降到|下降|减少|提升|提高|增加).{0,12}?"
    rf"(?:{NUMBER_PATTERN}|一半|半)|"
    r"(?:降低|下降|减少|减半|提升|提高|增加|加速|消除|移除|归零|"
    r"通过|失败|阻止|一致|收敛|回退)$|"
    r"迁移(?:到|至).+$",
    re.IGNORECASE,
)
TITLE_DECISION_RE = re.compile(
    rf"^{ENGLISH_DECISION_PATTERN}|"
    r"\b(?:recommend(?:ed|s)?|should|must|can)\s+"
    rf"{ENGLISH_DECISION_PATTERN}|"
    r"(?:建议|应当|应该|决定|暂不|不要).{0,16}?"
    r"(?:保留|采用|合入|回退|继续|停止|优先|暂缓|不合入)",
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
    "方法",
    "method",
    "methods",
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
    support_headings: list[tuple[int, str]] = field(default_factory=list)
    table_id: str | None = None


@dataclass
class ReportDocument:
    title: str
    blocks: list[ReaderBlock]
    alternate_titles: list[str] = field(default_factory=list)
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


@dataclass(frozen=True)
class ClaimValidation:
    baseline_candidate: bool
    absolute_change: bool
    relative_change: bool
    unit: bool
    workload: bool
    sample_count: bool

    @property
    def missing(self) -> list[str]:
        fields = (
            ("baseline/candidate", self.baseline_candidate),
            ("absolute change", self.absolute_change),
            ("relative change", self.relative_change),
            ("unit", self.unit),
            ("workload", self.workload),
            ("sample count", self.sample_count),
        )
        return [name for name, present in fields if not present]


class PortableHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.blocks: list[ReaderBlock] = []
        self._block: dict[str, Any] | None = None
        self._block_depth = 0
        self._capture_heading: tuple[int, list[str]] | None = None
        self._ignored_depth = 0
        self._source_ignore_depth = 0
        self._preformatted_ignore_depth = 0

    def _finish_section(self) -> None:
        if self._block is None:
            return
        heading = self._block["current_heading"]
        support_headings = self._block["current_support_headings"]
        parts = self._block["current_text"]
        text_parts = [heading[1]] if heading else []
        text_parts.extend(parts)
        text = normalize_space(" ".join(text_parts))
        if text:
            self._block["sections"].append((heading, support_headings, text))
        self._block["current_heading"] = None
        self._block["current_support_headings"] = []
        self._block["current_text"] = []

    def _finish_block(self) -> None:
        if self._block is None:
            return
        self._finish_section()
        for heading, support_headings, text in self._block["sections"]:
            block_id = self._block["id"] if heading is None else ""
            if heading and heading[0] == 1:
                block_id = "title"
            self.blocks.append(
                ReaderBlock(
                    block_id=block_id,
                    kind=self._block["kind"],
                    text=text,
                    headings=[heading] if heading else [],
                    support_headings=support_headings,
                )
            )
        self._block = None

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
                "sections": [],
                "current_heading": None,
                "current_support_headings": [],
                "current_text": [],
                "heading_path": [],
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

        if self._preformatted_ignore_depth:
            self._preformatted_ignore_depth += 1
            return
        if (
            self._block is not None
            and self._block["kind"] == "markdown"
            and tag == "pre"
        ):
            self._preformatted_ignore_depth = 1
            return

        if tag == "h1" or (
            self._block is not None
            and self._block["kind"] == "markdown"
            and tag in {"h2", "h3", "h4", "h5", "h6"}
        ):
            self._finish_section()
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

        if self._preformatted_ignore_depth:
            self._preformatted_ignore_depth -= 1
            if self._block is not None:
                self._block_depth -= 1
            return

        if self._capture_heading and tag == f"h{self._capture_heading[0]}":
            level, parts = self._capture_heading
            heading = normalize_space("".join(parts))
            if self._block is not None and heading:
                current_heading = (level, heading)
                heading_path = [
                    item
                    for item in self._block["heading_path"]
                    if item[0] < level
                ]
                heading_path.append(current_heading)
                self._block["heading_path"] = heading_path
                self._block["current_heading"] = current_heading
                self._block["current_support_headings"] = list(
                    heading_path
                )
            if level == 1 and not self.title:
                self.title = heading
            self._capture_heading = None

        if self._block is not None:
            self._block_depth -= 1
            if self._block_depth == 0:
                self._finish_block()

    def handle_data(self, data: str) -> None:
        if (
            self._ignored_depth
            or self._source_ignore_depth
            or self._preformatted_ignore_depth
        ):
            return
        if self._capture_heading is not None:
            self._capture_heading[1].append(data)
        elif self._block is not None:
            self._block["current_text"].append(data)


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


def split_markdown_sections(
    text: str,
    *,
    source_block_id: str = "",
) -> list[ReaderBlock]:
    blocks: list[ReaderBlock] = []
    current: list[str] = []
    current_heading: tuple[int, str] | None = None
    current_support_headings: list[tuple[int, str]] = []
    heading_path: list[tuple[int, str]] = []
    fence_marker: str | None = None
    fence_length = 0

    def flush_current() -> None:
        nonlocal current, current_heading, current_support_headings
        if not current:
            return
        body = "\n".join(current)
        text_content = strip_markdown(body)
        block_id = source_block_id if current_heading is None else ""
        if current_heading and current_heading[0] == 1:
            block_id = "title"
        if text_content:
            blocks.append(
                ReaderBlock(
                    block_id=block_id,
                    kind="markdown",
                    text=text_content,
                    headings=[current_heading] if current_heading else [],
                    support_headings=current_support_headings,
                )
            )
        current = []
        current_heading = None
        current_support_headings = []

    for line in text.splitlines():
        fence_match = re.match(r"^\s*(`{3,}|~{3,})", line)
        if fence_marker is not None:
            if (
                fence_match
                and fence_match.group(1)[0] == fence_marker
                and len(fence_match.group(1)) >= fence_length
            ):
                fence_marker = None
                fence_length = 0
            continue
        if fence_match:
            fence_marker = fence_match.group(1)[0]
            fence_length = len(fence_match.group(1))
            continue
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if match:
            flush_current()
            level = len(match.group(1))
            current_heading = (level, strip_markdown(match.group(2)))
            heading_path = [
                item for item in heading_path if item[0] < level
            ]
            heading_path.append(current_heading)
            current_support_headings = list(heading_path)
            current.append(line)
            if current_heading[0] == 1:
                flush_current()
        else:
            current.append(line)

    flush_current()
    return blocks


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
            blocks.extend(
                split_markdown_sections(body, source_block_id=block_id)
            )
            continue
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

    visible_title = next(
        (
            heading
            for block in blocks
            for level, heading in block.headings
            if level == 1
        ),
        "",
    )
    manifest_title = normalize_space(str(manifest.get("title", "")))
    title = visible_title or manifest_title
    alternate_titles = [
        candidate
        for candidate in (manifest_title, visible_title)
        if candidate and candidate != title
    ]
    return ReportDocument(
        title=title,
        blocks=blocks,
        alternate_titles=alternate_titles,
        tables=tables,
        datasets=datasets,
    )


def parse_html(path: Path) -> ReportDocument:
    parser = PortableHTMLParser()
    parser.feed(path.read_text(encoding="utf-8"))
    return ReportDocument(title=normalize_space(parser.title), blocks=parser.blocks)


def parse_markdown(path: Path) -> ReportDocument:
    text = path.read_text(encoding="utf-8")
    blocks = split_markdown_sections(text)
    title = next(
        (
            heading
            for block in blocks
            for level, heading in block.headings
            if level == 1
        ),
        "",
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
    headings = block.support_headings or block.headings
    return any(SUPPORT_RE.search(heading) for _, heading in headings)


def first_substantive_block(document: ReportDocument) -> ReaderBlock | None:
    for block in document.blocks:
        if block.block_id == "title":
            continue
        if block.headings and all(level == 1 for level, _ in block.headings):
            continue
        non_title_headings = [heading for level, heading in block.headings if level > 1]
        text = block.text
        if non_title_headings or visible_char_count(text) >= 40:
            return block
    return None


def label_has_value(
    text: str,
    label_re: re.Pattern[str],
    opposite_label_re: re.Pattern[str],
    value_re: re.Pattern[str],
) -> bool:
    for match in label_re.finditer(text):
        right = text[match.end() : match.end() + 96]
        opposite = opposite_label_re.search(right)
        if opposite:
            right = right[: opposite.start()]
        right = re.split(r"[。！？!?\n]", right, maxsplit=1)[0]
        if value_re.search(right):
            return True
    return False


def validate_quantified_claim(text: str) -> ClaimValidation:
    labeled_numeric_pair = label_has_value(
        text, BASELINE_LABEL_RE, CANDIDATE_LABEL_RE, NUMBER_RE
    ) and label_has_value(
        text, CANDIDATE_LABEL_RE, BASELINE_LABEL_RE, NUMBER_RE
    )
    labeled_measured_pair = label_has_value(
        text, BASELINE_LABEL_RE, CANDIDATE_LABEL_RE, MEASUREMENT_RE
    ) and label_has_value(
        text, CANDIDATE_LABEL_RE, BASELINE_LABEL_RE, MEASUREMENT_RE
    )
    baseline_candidate = bool(
        FROM_TO_NUMERIC_RE.search(text)
        or NUMERIC_ARROW_RE.search(text)
        or labeled_numeric_pair
    )
    comparison_unit = bool(
        FROM_TO_SHARED_UNIT_RE.search(text)
        or SHARED_UNIT_ARROW_RE.search(text)
        or labeled_measured_pair
    )

    return ClaimValidation(
        baseline_candidate=baseline_candidate,
        absolute_change=bool(ABSOLUTE_CHANGE_RE.search(text)),
        relative_change=bool(RELATIVE_CHANGE_RE.search(text)),
        unit=comparison_unit,
        workload=bool(WORKLOAD_RE.search(text)),
        sample_count=bool(SAMPLE_COUNT_RE.search(text)),
    )


def title_is_result_bearing(title: str) -> bool:
    return bool(
        TITLE_OUTCOME_RE.search(title)
        or TITLE_DECISION_RE.search(title)
        or RELATIVE_CHANGE_RE.search(title)
        or ABSOLUTE_CHANGE_RE.search(title)
        or FROM_TO_NUMERIC_RE.search(title)
        or NUMERIC_ARROW_RE.search(title)
    )


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
    section_headings = [
        heading for level, heading in headings if 2 <= level <= 6
    ]

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

    for heading in section_headings:
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
        claim = validate_quantified_claim(opening.text)
        if claim.missing:
            issues.append(
                Issue(
                    "error",
                    "OPENING_EFFECT",
                    "The first substantive block has an incomplete quantified claim; "
                    f"missing: {', '.join(claim.missing)}.",
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

    title_candidates = list(
        dict.fromkeys([document.title, *document.alternate_titles])
    )
    generic_titles = [
        title for title in title_candidates if not title_is_result_bearing(title)
    ]
    if generic_titles:
        issues.append(
            Issue(
                "error",
                "GENERIC_TITLE",
                "Every reader-facing title must state a result or decision; "
                f"topic-only title: {generic_titles[0]!r}.",
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
