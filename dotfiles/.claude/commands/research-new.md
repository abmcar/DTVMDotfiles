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
This follows a brainstorming process where the terminal state is
**creating direction files + handoff to Gate 1**.

All research files live in the DTVM-Papers repo at `docs/research/`.

## Phase 1: Brainstorm (explore the idea)

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
   with trade-offs and your recommendation.

5. **Converge** — After discussion, confirm with the user:
   - Direction name (short, kebab-case)
   - Hypothesis (one sentence)
   - Target venue
   - Initial kill conditions (≥1 measurable condition)
   - Keywords (for dedup checking)

## Phase 2: Create (scaffold direction files)

Once the user confirms:

### Step 1: Dedup check

Read `docs/research/index.yaml`. Check if any killed/completed direction shares ≥2 keywords.
If overlap found:
- Show the overlap: "This overlaps with direction '<name>' (status: <status>, reason: <kill_reason>)"
- Ask: "Is this genuinely different, or a revival?"

### Step 2: Create directory

```bash
cp -r docs/research/directions/_template docs/research/directions/<name>
```

### Step 3: Fill state.yaml

Edit `docs/research/directions/<name>/state.yaml`:
- `name`: direction name
- `status`: "exploring"
- `created`: today's date
- `target_venue`: from brainstorm
- `origin`: [] (or list prior directions if this is a revival/evolution)
- `hypothesis`: from brainstorm
- `kill_conditions`: from brainstorm
- Leave `conclusion` and `kill_reason` as null

### Step 4: Fill other files

- `README.md`: Update with direction name, hypothesis, approach, links
- `artifacts.md`: Add any existing artifacts mentioned during brainstorm
- `log.md`: Add creation entry with date and summary of brainstorm rationale

### Step 5: Register in index.yaml

Append new entry to `docs/research/index.yaml`:
```yaml
  - name: "<name>"
    path: "directions/<name>"
    status: "exploring"
    hypothesis: "<hypothesis>"
    keywords: [<keywords from brainstorm>]
    kill_reason: null
    conclusion: null
```

### Step 6: Commit to DTVM-Papers repo

```bash
cd docs/research/papers
git add directions/<name>/ index.yaml
git commit -m "research(<name>): create new direction"
```

### Step 7: Handoff

Tell the user:

> Direction `<name>` created at `docs/research/directions/<name>/`.
>
> Next step: run `/research-review <name>` to run an adversarial review.
>
> Want to run the review now?

## Constraints

- **One question at a time** during brainstorm
- **Be honest about prior work** — if the idea is already published, say so during brainstorm, not after creating files
- **Don't skip brainstorm** — even if the user gives a fully formed idea, at minimum do the related work search and dedup check before creating files
