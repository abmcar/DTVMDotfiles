---
name: research-new
description: >
  Brainstorm and create a new research direction. Use when the user has a research idea
  to explore — helps refine the idea through dialogue, then scaffolds the direction files
  and registers in index.yaml. Hands off to /research-review for Gate 1.
argument-hint: topic or idea text
---

# New Research Direction — Brainstorm & Create

You are helping the user turn a research idea into a formal research direction.
This follows the Superpowers brainstorming process, but the terminal state is
**creating direction files + handoff to Gate 1**, not writing-plans.

## Phase 1: Brainstorm (explore the idea)

Follow the brainstorming process:

1. **Parse what the user gave you.** Extract whatever is there — topic, hypothesis,
   venue, related work. Don't ask for things already provided.

2. **Ask clarifying questions** — one at a time, multiple choice when possible:
   - What problem does this solve? What's the gap in existing work?
   - Who is the audience / what venue? (ISSTA, PLDI, CGO, FSE, etc.)
   - What would a successful result look like?
   - What would kill this direction?

3. **Search related work** — Use paper-find MCP tools (search_arxiv, search_semantic,
   search_google_scholar) to quickly scan for prior art. Share what you find.
   Be honest if something very close already exists.

4. **Propose 2-3 angles** — Same idea can have different framings. Present options
   with trade-offs and your recommendation. For example:
   - Angle A: focus on bug-finding (testing venue like ISSTA)
   - Angle B: focus on optimization technique (compiler venue like CGO)
   - Angle C: focus on formalization (PL venue like PLDI)

5. **Converge** — After discussion, confirm with the user:
   - Direction name (short, kebab-case)
   - Hypothesis (one sentence)
   - Target venue
   - Initial kill conditions (≥1 measurable condition)
   - Keywords (for dedup checking)

## Phase 2: Create (scaffold direction files)

Once the user confirms:

### Step 1: Dedup check

Read `docs/research/index.yaml`. Check if any killed direction shares ≥2 keywords.
If overlap found:
- Show the overlap: "This overlaps with killed direction '<name>' (reason: <kill_reason>)"
- Ask: "Is this genuinely different, or a revival?"
- If revival: set lineage.revives and lineage.differentiation

### Step 2: Create directory

```bash
cp -r docs/research/directions/_template docs/research/directions/<name>
mkdir -p docs/research/directions/<name>/amendments
```

### Step 3: Fill state.yaml

Edit `docs/research/directions/<name>/state.yaml`:
- `name`: direction name
- `status`: "exploring"
- `created`: today's date
- `target_venue`: from brainstorm
- `hypothesis`: from brainstorm
- `kill_conditions`: from brainstorm
- Leave `pre_registration` empty — that's Gate 1 Proposer's job
- Set reasonable `gate3_triggers` defaults (engineer_days: 3, prototype_loc: 500, experiment_count: 10, branch_age_days: 14)

### Step 4: Fill other files

- `README.md`: Update with direction name, hypothesis, status
- `artifacts.md`: Add any existing artifacts mentioned during brainstorm
- `log.md`: Add creation entry with date and summary of brainstorm rationale

### Step 5: Register in index.yaml

Append new entry to `docs/research/index.yaml`:
```yaml
  - name: "<name>"
    status: "exploring"
    hypothesis: "<hypothesis>"
    keywords: [<keywords from brainstorm>]
    kill_reason: null
    closest_prior_work: "<from brainstorm search>"
    lineage: null  # or revives/differentiation if revival
```

### Step 6: Handoff

Tell the user:

> Direction `<name>` created at `docs/research/directions/<name>/`.
>
> Next step: run `/research-review <name>` to trigger Gate 1 (adversarial proposal review).
> Gate 1 will fill in pre-registration (baseline, metrics, thresholds) and run a red-team assessment.
>
> Want to run Gate 1 now?

## Constraints

- **One question at a time** during brainstorm
- **Be honest about prior work** — if the idea is already published, say so during brainstorm, not after creating files
- **Don't fill pre_registration** — that's Gate 1's job
- **Don't auto-trigger Gate 1** — ask the user
- **Don't skip brainstorm** — even if the user gives a fully formed idea, at minimum do the related work search and dedup check before creating files
