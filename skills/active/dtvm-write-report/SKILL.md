---
name: dtvm-write-report
description: Write or revise reader-facing DTVM technical, performance, benchmark, profiling, experiment, and optimization reports in HTML or Markdown. Use when Codex turns DTVM evidence into a durable report, rewrites an existing report, or prepares measured results for review. Enforces decision-first hierarchy, natural language, benchmark-versus-A/B terminology, compact methods and correctness coverage, and deterministic lint before handoff.
---

# DTVM Report Writing

Turn verified engineering evidence into a concise report whose main line is:
result, mechanism, impact, and action. Keep audit depth available without making
the reader walk through the audit process.

This skill owns reader-facing structure, terminology, and language. Profiling,
compiler-analysis, test, and Data Analytics skills may own evidence collection,
validation, visualization, provenance, and HTML packaging, but they do not
override this narrative contract.

## 1. Fix the reporting decision

Write one private claim manifest before drafting:

| Field | Required content |
|---|---|
| Decision | What should the reader retain, merge, revert, investigate, or defer? |
| Main result | Baseline, candidate, absolute change, relative change, unit, and sample count when available |
| Mechanism | The smallest source-level explanation supported by profile or code evidence |
| Scope | The exact workload and environment covered |
| Uncertainty | The one limitation most likely to change the decision |

Use validation output as a generation gate. Do not render the claim manifest,
validator checklist, confidence label, chart-selection notes, or source
inventory as report sections.

Treat DTVM maintainers and technical stakeholders as the default audience even
when the subject is compiler internals. Use a methods-first shape only when the
user explicitly asks for an audit memo, experiment protocol, or methodology
review.

## 2. Build the reader path

Default to at most six major sections:

1. **Conclusion:** what changed, how much, versus what, and the recommended
   decision. Include at most one scope sentence.
2. **Why it changed:** two or three causal mechanisms, each tied to evidence.
3. **Impact and hotspot movement:** the smallest useful chart or table plus its
   interpretation.
4. **Decision and next step:** concrete action, owner or measurement when known.
5. **How to read the numbers:** a compact measurement note only when needed.

Use result-bearing headings such as `两个线性扫描被消除` or
`热点已迁移到寄存器分配`. Do not copy generic template roles into headings.

For a non-methods-first report:

- Reserve at least 75% of reader-facing text for results, mechanism, impact,
  tradeoffs, and action.
- Keep scope, definitions, method, build identity, correctness, robustness,
  limitations, and reproducibility at or below 25%.
- Summarize fully passing correctness gates in one sentence. Keep the full test
  matrix in source metadata or a supporting artifact.
- Keep source commits, hashes, commands, compiler identity, sampling settings,
  validation output, and raw logs in provenance or appendices.
- Promote a support detail into the main line only when it changes the decision.

## 3. State measurements plainly

For every headline comparison, provide the available baseline, candidate,
absolute change, relative change, unit, workload, and sample count. Do not
invent a missing dispersion measure or statistical interval. If the protocol
cannot estimate an exact effect, say which quantity was observed and what
matched measurement is still needed.

Attach a limitation to the claim it qualifies:

```text
这组结果覆盖 4 个连续区块；完整 32-block 工作负载尚未复测。
```

Avoid abstract confidence prose such as `方向性证据`, `诊断夹定`,
`可带限制分享`, or `尚不等于正式 A/B`.

Use **A/B test** only when the evidence includes concurrent treatment and
control, randomized assignment units, and statistical inference. Otherwise
use the precise design name:

- `baseline–candidate benchmark`
- `paired benchmark`
- `interleaved benchmark`
- `canary` or `gradual rollout`

An offline baseline–candidate comparison is not an A/B test merely because it
has two builds.

## 4. Use natural technical language

- Put a concrete subject before the verb.
- Prefer `X 从 40% 降到 2%` over `X 获得显著改善`.
- Keep one main idea per sentence.
- Explain uncommon English terms on first use; retain symbol names only when
  they help the reader act.
- Replace process language with outcomes. Say what passed or failed, not that a
  gate was “closed” or evidence was “made shareable”.
- Use short paragraphs and real lists. Delete repeated caveats and duplicated
  summaries.

Read [references/exemplars.md](references/exemplars.md) when creating or
substantially rewriting a durable report. It records the primary-source
examples behind this contract.

## 5. Render and lint

When Data Analytics builds the HTML, keep its canonical source metadata and
portable builder, but use this skill's section order and terminology. Treat
generic technical-report roles as internal coverage checks, not mandatory
visible sections.

Run the linter on the canonical artifact before rendering and on the delivered
HTML afterward:

```bash
SKILL_DIR="<installed-skill-directory>/dtvm-write-report"
python3 "$SKILL_DIR/scripts/lint_report.py" artifact.json
python3 "$SKILL_DIR/scripts/lint_report.py" report.html
```

Use `--methods-first` only for an explicitly requested methods report. Use
`--randomized-ab` only after the claim manifest records random assignment,
concurrent control, and the inference method.

Any linter error blocks handoff. Fix the narrative rather than weakening a
threshold. Preserve the lint output with the report's validation artifacts.

## Completion gate

Finish only when:

1. the title and first section reveal the result and decision;
2. each major section advances the same story;
3. evidence supports every number and causal statement;
4. support content stays within budget or the user requested methods-first;
5. terminology matches the actual experiment design;
6. the canonical artifact and final report both pass `lint_report.py`;
7. the rendered HTML passes its normal packaging and visual QA.
