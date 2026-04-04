---
name: research-review
description: >
  Run adversarial red-team review on a research direction at the appropriate lifecycle gate.
  Use when: evaluating a new direction, checking experiment evidence, deciding whether to
  continue or kill a direction, or when preflight detects an overdue gate review.
argument-hint: direction-name
---

# Research Direction Red-Team Review

You are the **coordinator** for a gated research review. You do NOT evaluate the direction
yourself — you orchestrate two agents with opposing mandates and present results to the user.

**Spec:** `docs/superpowers/specs/2026-04-03-research-red-team-workflow-design.md` (v3.1)
**Key constraint:** Use coordinator-mediated handoff (see `memory/feedback_agent_team_patterns.md`).
Spawn Agent 1 foreground → collect output → spawn Agent 2 foreground with output injected.
Do NOT use direct SendMessage between agents.

---

## Step 1: Identify the direction

If the user did not specify a direction name in the arguments, list available directions:

```bash
ls docs/research/directions/ | grep -v _template
```

Then ask the user which direction to review.

---

## Step 2: Run preflight

Read the direction's `state.yaml`:

```
docs/research/directions/<name>/state.yaml
```

Run these checks IN ORDER. Stop at the first BLOCK.

**Check 1 — state.yaml exists:**
If the file does not exist → BLOCK.
Tell the user: "No state.yaml found for direction '<name>'. Create the direction first using the _template."

**Check 2 — not killed:**
If `status == "killed"` → BLOCK.
Tell the user: "Direction '<name>' is killed. To revive, create a new direction with lineage.revives in index.yaml."

**Check 3 — override not expired:**
If `overrides` list has any entry where `next_review` date has passed → BLOCK.
Tell the user: "Override from <date> has expired (next_review was <date>). Must run gate review before any more work."

**Check 4 — budget triggers:**
Compare `budget_consumed` against `gate3_triggers`. If ANY threshold is met:
- `budget_consumed.engineer_days >= gate3_triggers.engineer_days`
- `budget_consumed.prototype_loc >= gate3_triggers.prototype_loc`
- `budget_consumed.experiments_run >= gate3_triggers.experiment_count`
- Branch age: if `budget_consumed.branch_created` is set, check if `(today - branch_created)` in days `>= gate3_triggers.branch_age_days`

If any trigger is met AND `gate-3.md` does not exist → FORCE Gate 3.
Tell the user: "Budget trigger met (<which one>). Gate 3 review is required before further work."

**Check 5 — dedup (Gate 1 only):**
If this is a new direction entering Gate 1, read `docs/research/index.yaml`.
Check if any killed direction shares ≥2 keywords with the new direction.
If found → WARN. Show the overlap and ask: "This overlaps with killed direction '<name>' (killed because: <reason>). Is this genuinely different? Please acknowledge before proceeding."

**Preflight result:** Report all checks as PASS/BLOCK/WARN. If any BLOCK, stop here.

---

## Step 3: Determine which gate to run

Based on `state.yaml`:

| status | Gate | Additional condition |
|--------|------|---------------------|
| `exploring` | Gate 1 | — |
| `proposed` | Gate 1 (if gate-1.md missing) or inform user "Gate 1 complete, begin experiments to trigger Gate 2" | — |
| `experimenting` | Gate 2 | pre_registration must be filled |
| `implementing` | Gate 3 | — |
| `writing` | Inform user: no gate needed, direction is in writing phase | — |

If Gate 2 and `pre_registration` fields are empty → BLOCK: "Cannot run Gate 2 without pre_registration. Was Gate 1 completed?"

If Gate 2 and amendments exist, check: does any amendment have classification "weakening"?
If yes AND no FAILED EVIDENCE record exists in gate-2.md → BLOCK: "Weakening amendment requires recording old Gate 2 as FAILED EVIDENCE and Gate 1-strength re-review."

---

## Step 4: Run the gate

### Gate 1: Proposal Review

**Spawn Agent 1 — Proposer** (foreground, default mode):

Use the Agent tool with this prompt (fill in <DIRECTION_NAME>, <STATE_YAML_CONTENT>, <ARTIFACTS_CONTENT>):

```
You are the Proposer for research direction "<DIRECTION_NAME>".

Current state:
---
<STATE_YAML_CONTENT>
---

Current artifacts:
---
<ARTIFACTS_CONTENT>
---

Your task:
1. Write a complete proposal: hypothesis, target venue, expected contribution, novelty argument.
2. Search for the 5 closest related works using paper-find MCP tools (search_arxiv,
   search_semantic, search_google_scholar). For each, state the title, venue, year,
   and how our work specifically differs.
3. Fill in the pre-registration fields if not already filled:
   - baseline, metrics (with measurable thresholds), dataset/workload, comparison axes
   - budget limits (max_engineer_days, max_prototype_loc, max_experiments)
   - gate3 triggers
4. Define concrete kill conditions.

Output your proposal in this EXACT format:

## Proposal for: <DIRECTION_NAME>
### Hypothesis
<one sentence>
### Target Venue
<venue + why it fits>
### Expected Contribution
<1-3 bullet points of concrete contributions>
### Novelty Argument
<why this has not been done before — with specific evidence>
### Related Work
1. [<Title>] (<Venue>, <Year>) — Difference: <specific technical gap>
2. [<Title>] (<Venue>, <Year>) — Difference: <specific technical gap>
3. ...
### Pre-Registration
- Baseline: ...
- Metrics: [name: threshold] ...
- Dataset/Workload: ...
- Comparison axes: ...
- Budget: ... engineer-days, ... LOC, ... experiments
### Kill Conditions
1. ...
2. ...
```

Collect the Proposer's full output.

**Spawn Agent 2 — Reviewer** (foreground, plan mode):

Use the Agent tool with `mode: "plan"` and this prompt (fill in <PROPOSER_OUTPUT>, <STATE_YAML_CONTENT>, <ARTIFACTS_CONTENT>):

```
You are an academic reviewer tasked with calibrated risk assessment for a research
direction. Your goal is CALIBRATION — accurate assessment, not maximum rejection.

Direction state:
---
<STATE_YAML_CONTENT>
---

Artifact index:
---
<ARTIFACTS_CONTENT>
---

Proposer's output (NAVIGATION AID — verify claims against raw artifacts):
---
<PROPOSER_OUTPUT>
---

Mandatory verification:
- You MUST open and read at least 2 raw artifacts listed in the artifact index above.
- For EACH artifact checked, include in your output:
  (a) the file path
  (b) a content excerpt (>=3 lines copied verbatim from the file)
  (c) one-line finding
- If you cannot access an artifact, say so explicitly.
- Listing paths without content excerpts makes your verdict INVALID.

Risk assessment:
1. Produce >=2 verifiable risks or falsification attempts. For each:
   - Classify: FATAL FLAW / MAJOR RISK / OPEN UNCERTAINTY
   - State falsification method
2. Independently search for prior work using paper-find MCP tools (search_arxiv,
   search_semantic, search_google_scholar). Do NOT rely on the Proposer's search.
3. If novelty depends on future experiments: "THIS IS A BET, NOT A PLAN"
4. Forbidden words without evidence: "promising", "interesting", "novel", "significant"
5. Echo chamber check: consensus from agents is not validation
6. Check pre-registration: are baseline/metric/threshold measurable and meaningful?

Output in this EXACT format:

## Red Team Review: <DIRECTION_NAME>
### Recommendation: RECOMMEND STOP / RECOMMEND CONTINUE / INCONCLUSIVE
### Artifacts Checked
1. Path: <path>
   Excerpt:
   ```
   <>=3 lines verbatim>
   ```
   Finding: <one line>
2. Path: <path>
   Excerpt:
   ```
   <>=3 lines verbatim>
   ```
   Finding: <one line>
### Independent Prior Work Search
1. [<Title>] (<Venue>, <Year>) — Overlap: <specific overlap with this direction>
2. ...
### Risk 1: [FATAL FLAW / MAJOR RISK / OPEN UNCERTAINTY]
Description: ...
Falsification method: ...
### Risk 2: [FATAL FLAW / MAJOR RISK / OPEN UNCERTAINTY]
Description: ...
Falsification method: ...
### Reviewer-2 Test
"Isn't this just ___?"
### Honest Answer
"What would make me reject this at <venue>?"
```

### Gate 2: Evidence Review

**Spawn Agent 1 — Evidence Collector** (foreground, default mode, must NOT be the original proposer):

Use the Agent tool with this prompt:

```
You are the Evidence Collector for research direction "<DIRECTION_NAME>".
You are NOT the original proposer — your job is independent data collection.

State (including frozen pre-registration):
---
<STATE_YAML_CONTENT>
---

Amendments (if any):
---
<AMENDMENTS_CONTENT or "No amendments filed.">
---

Artifact index:
---
<ARTIFACTS_CONTENT>
---

Your task:
1. Read the pre-registration to know what metrics and thresholds were promised.
2. Read the actual experiment artifacts (logs, benchmarks, test results) listed in artifacts.md.
3. For each pre-registered metric, score: MET / MISSED / INCONCLUSIVE with actual numbers.
4. List the raw artifact paths you used as evidence.
5. Be brutally honest about what the data shows.

Output in this EXACT format:

## Evidence Summary: <DIRECTION_NAME>
### Pre-Registration Scorecard
| Metric | Threshold | Actual | Verdict |
|--------|-----------|--------|---------|
| <name> | <threshold> | <actual value + source artifact> | MET / MISSED / INCONCLUSIVE |
| ... | ... | ... | ... |
### Raw Artifacts Referenced
- <path>: <what this contains>
- ...
### Honest Assessment
<Does the data support the hypothesis? Be specific.>
```

**Spawn Agent 2 — Reviewer** (foreground, plan mode):

Same reviewer prompt as Gate 1, with these additions injected:

```
Additional rules for Gate 2:
- Evaluate against the FROZEN pre-registration (+ any amendments), not post-hoc reframing.
- If data is inconclusive, say "INCONCLUSIVE" — not "more experiments needed."
- Answer: "Would a skeptical reviewer at <venue> find these numbers convincing?"
- Check amendments: if any are classified as "weakening", flag this prominently.

Collector's evidence summary (NAVIGATION AID — verify against raw artifacts):
---
<COLLECTOR_OUTPUT>
---
```

### Gate 3: Kill-or-Continue

**Spawn Agent 1 — Status Collector** (foreground, default mode, must NOT be the original proposer):

```
You are the Status Collector for research direction "<DIRECTION_NAME>".
You are NOT the original proposer — your job is independent status assessment.

State:
---
<STATE_YAML_CONTENT>
---

All gate documents:
---
<GATE_1_CONTENT>
<GATE_2_CONTENT if exists>
---

Artifact index:
---
<ARTIFACTS_CONTENT>
---

Log:
---
<LOG_CONTENT>
---

Your task:
1. Summarize total investment: engineer-days, LOC, experiments, branch age.
2. List concrete outputs: artifacts, bugs found, benchmarks, tools built.
3. List remaining gaps for paper submission.
4. Estimate remaining effort in days with explicit assumptions.
5. Check git log for related commits if possible.

Output in this EXACT format:

## Status Report: <DIRECTION_NAME>
### Budget Accounting
| Resource | Allocated | Consumed | Remaining |
|----------|-----------|----------|-----------|
| Engineer-days | <N> | <N> | <N> |
| Prototype LOC | <N> | <N> | <N> |
| Experiments | <N> | <N> | <N> |
### Concrete Outputs
- ...
### Remaining Gaps
- ...
### Estimated Remaining Effort
<N> days, assuming: <explicit assumptions>
```

**Spawn Agent 2 — Reviewer** (foreground, plan mode):

Same reviewer prompt as Gate 1, with these additions:

```
Additional rules for Gate 3:
- You MUST argue the case for stopping NOW. Sunk cost is not a reason to continue.
- Answer: "If starting fresh today with no prior investment, would we choose this direction?"
- Compare: remaining effort vs starting a new direction.

Status Collector's report (NAVIGATION AID — verify against raw artifacts):
---
<COLLECTOR_OUTPUT>
---
```

---

## Step 5: Validate reviewer output

After receiving the Reviewer's output, check:

1. Does the output contain an "Artifacts Checked" section?
2. Does each artifact entry have (a) path, (b) ≥3 lines of content excerpt, (c) finding?
3. Are there ≥2 artifact entries?

If ANY check fails:
- Tell the user: "Reviewer verdict is INVALID — missing artifact verification. Re-running reviewer."
- Re-spawn the Reviewer with an additional line in the prompt: "YOUR PREVIOUS OUTPUT WAS INVALID because you did not include content excerpts from raw artifacts. You MUST read the actual files and quote ≥3 lines from each."

---

## Step 6: Present results

Present both outputs clearly separated:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Gate <N> Review Complete: <DIRECTION_NAME>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Proposer/Collector Assessment
<Agent 1 output>

## Red Team (Reviewer) Assessment
<Agent 2 output>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Recommendation: <RECOMMEND STOP / CONTINUE / INCONCLUSIVE>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If RECOMMEND CONTINUE:
  → You can proceed. No paperwork needed.

If RECOMMEND STOP or INCONCLUSIVE:
  → Default action is STOP.
  → To override, you must provide:
    1. Rationale (not sunk cost)
    2. Additional budget (engineer-days, LOC, experiments)
    3. Next review date
    4. What evidence would make you stop

Your decision: proceed / stop / pivot?
```

---

## Step 7: Record the decision

Based on the user's decision:

**If proceeding (CONTINUE recommendation or user override):**
1. Write the full gate output to `gate-<N>.md` (both agent outputs + recommendation + decision)
2. If user overrode STOP/INCONCLUSIVE: append override memo to `state.yaml overrides` list
3. Update `state.yaml status` per the transition table:
   - Gate 1 continue: `exploring` → `proposed`
   - Gate 2 continue: `experimenting` → `implementing`
   - Gate 3 continue: `implementing` → `writing`
4. Update `index.yaml` entry if needed (new direction at Gate 1)
5. Append to `log.md`: `- <today>: Gate <N> review — <recommendation> — user decided: <decision>`

**If stopping:**
1. Write the full gate output to `gate-<N>.md`
2. Update `state.yaml status` to `killed`
3. Update `index.yaml`: set `status: "killed"` and `kill_reason: "<from reviewer>"`
4. Append to `log.md`: `- <today>: Gate <N> review — RECOMMEND STOP — user accepted. Direction killed.`

**If pivoting:**
1. Record the stop as above
2. Ask the user to describe the pivot. Create a new direction with `lineage.revives` pointing to this one.

---

## Important Constraints

- **You are the coordinator.** Do NOT evaluate the direction yourself.
- **Coordinator-mediated handoff.** Spawn Agent 1 foreground → collect → spawn Agent 2 foreground with output injected.
- **Reviewer is plan mode.** Always use `mode: "plan"` for the reviewer agent.
- **User decides.** Never auto-proceed through a gate.
- **Full context in every prompt.** Copy state.yaml, artifacts.md, and relevant content into each agent's prompt.
- **Validate reviewer output.** Check for artifact excerpts before accepting the verdict.
