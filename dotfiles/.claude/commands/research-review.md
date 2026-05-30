---
name: research-review
description: >
  Run adversarial red-team review on a research direction.
  Use when: evaluating a new direction, checking experiment evidence, deciding whether to
  continue or kill a direction.
argument-hint: direction-name
---

# Research Direction Red-Team Review

You are the **coordinator** for a research review. You do NOT evaluate the direction
yourself — you orchestrate two agents with opposing mandates and present results to the user.

**Key constraint:** Use coordinator-mediated handoff (see `memory/feedback_agent_team_patterns.md`).
Spawn Agent 1 foreground → collect output → spawn Agent 2 foreground with output injected.
Do NOT use direct SendMessage between agents.

All research files live in the DTVM-Papers repo at `docs/research/`.

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
Tell the user: "No state.yaml found for direction '<name>'. Create the direction first with /research-new."

**Check 2 — not already closed:**
If `status == "killed"` or `status == "completed"` → WARN.
Tell the user: "Direction '<name>' is <status>. Review anyway? (This won't reopen it automatically.)"

**Check 3 — dedup (exploring directions only):**
If status is `exploring`, read `docs/research/index.yaml`.
Check if any killed/completed direction shares ≥2 keywords.
If found → WARN. Show the overlap and ask user to acknowledge.

**Preflight result:** Report all checks as PASS/BLOCK/WARN. If any BLOCK, stop here.

---

## Step 3: Determine review type

| status | Review type |
|--------|------------|
| `exploring` | Proposal review — is this worth pursuing? |
| `active` | Evidence review — does the data support the hypothesis? |
| `paused` | Kill-or-continue — should we resume or abandon? |

---

## Step 4: Run the review

### Proposal Review (exploring)

**Spawn Agent 1 — Proposer** (foreground):

Inject into prompt: state.yaml content, artifacts.md content, README.md content.

Ask the Proposer to:
1. Write a complete proposal: hypothesis, target venue, expected contribution, novelty argument
2. Search for the 5 closest related works using `WebSearch` / `WebFetch` (arXiv, Semantic Scholar, Google Scholar)
3. Define concrete kill conditions
4. Output in structured format with sections: Hypothesis, Target Venue, Expected Contribution, Novelty Argument, Related Work, Kill Conditions

**Spawn Agent 2 — Reviewer** (foreground, plan mode):

Inject: state.yaml, artifacts.md, Proposer's output.

Ask the Reviewer to:
1. Produce ≥2 verifiable risks (FATAL FLAW / MAJOR RISK / OPEN UNCERTAINTY)
2. Independently search for prior work (do NOT rely on Proposer's search)
3. Read ≥2 raw artifacts and quote ≥3 lines from each
4. Answer: "Isn't this just ___?" and "What would make me reject this at <venue>?"
5. Give recommendation: RECOMMEND STOP / RECOMMEND CONTINUE / INCONCLUSIVE

### Evidence Review (active)

**Spawn Agent 1 — Evidence Collector** (foreground):

Inject: state.yaml, artifacts.md, log.md.

Ask the Collector to:
1. Read actual experiment artifacts (logs, benchmarks, test results)
2. Score each claimed finding: SUPPORTED / UNSUPPORTED / INCONCLUSIVE with actual numbers
3. List raw artifact paths used as evidence
4. Give honest assessment of whether data supports the hypothesis

**Spawn Agent 2 — Reviewer** (foreground, plan mode):

Same as Proposal Review reviewer, with additional rule:
- Evaluate against actual evidence, not promises
- Answer: "Would a skeptical reviewer at <venue> find these numbers convincing?"

### Kill-or-Continue Review (paused)

**Spawn Agent 1 — Status Collector** (foreground):

Inject: state.yaml, artifacts.md, log.md.

Ask the Collector to:
1. Summarize total investment and concrete outputs
2. List remaining gaps for completion
3. Estimate remaining effort with explicit assumptions

**Spawn Agent 2 — Reviewer** (foreground, plan mode):

Same as Proposal Review reviewer, with additional rules:
- MUST argue the case for stopping NOW. Sunk cost is not a reason to continue.
- Answer: "If starting fresh today, would we choose this direction?"

---

## Step 5: Validate reviewer output

Check:
1. Does the output contain artifact verification with ≥3 lines quoted per artifact?
2. Are there ≥2 risks identified?

If ANY check fails, re-spawn with a note that previous output was invalid.

---

## Step 6: Present results

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Review Complete: <DIRECTION_NAME>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Proposer/Collector Assessment
<Agent 1 output>

## Red Team (Reviewer) Assessment
<Agent 2 output>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Recommendation: <RECOMMEND STOP / CONTINUE / INCONCLUSIVE>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your decision: continue / stop / pivot?
```

---

## Step 7: Record the decision

Based on the user's decision:

**If continuing:**
1. Update `state.yaml status` if appropriate (e.g., `exploring` → `active`)
2. Update `index.yaml` to match
3. Append to `log.md`: `- <today>: Review — <recommendation> — user decided: continue`

**If stopping:**
1. Update `state.yaml`: `status: "killed"`, `closed: <today>`, `kill_reason: <from reviewer>`
2. Update `index.yaml` to match
3. Append to `log.md`: `- <today>: Review — RECOMMEND STOP — user accepted. Direction killed.`

**If pivoting:**
1. Record the stop as above
2. Ask the user to describe the pivot. Create a new direction with `origin` pointing to this one.

Commit changes to the DTVM-Papers repo.

---

## Constraints

- **You are the coordinator.** Do NOT evaluate the direction yourself.
- **Coordinator-mediated handoff.** Spawn Agent 1 foreground → collect → spawn Agent 2 foreground.
- **Reviewer is plan mode.** Always use `mode: "plan"` for the reviewer agent.
- **User decides.** Never auto-proceed through a review.
- **Full context in every prompt.** Copy state.yaml, artifacts.md, and relevant content into each agent's prompt.
- **Validate reviewer output.** Check for artifact excerpts before accepting.
