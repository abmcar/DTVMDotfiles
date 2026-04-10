---
description: Summarize the current session, review memory, and audit rule/memory/skill consistency
---

# Session Summary

Generate a concise summary of this session, review memory, and audit consistency.

**IMPORTANT: Do ALL tool calls first (git commands, memory reads/writes, issue file writes), then output the full summary as one final text block at the very end. This prevents the summary text from being collapsed between tool calls in the UI.**

## Step 1: Gather Context (silent — no text output yet)

1. Run `git diff --stat` to see file changes
2. Run `git log --oneline -10` to see recent commits
3. Run `git status -s` to see working tree state
4. Check the task list if any tasks exist

If not in a git repo, skip git commands and rely on conversation context only.

## Step 2: Memory Review (silent — no text output yet)

Review this session for anything worth saving to memory:

- Pain points or frustrations the user expressed
- User preferences or workflow corrections
- Non-obvious decisions that should inform future sessions

If anything qualifies, read existing memory files to check for duplicates, then write to memory per existing conventions. If nothing notable, note "no memory updates" for the final output.

## Step 3: Consistency Audit (silent — no text output yet)

Review this session's conversation for any moments where a rule (`.claude/rules/`), memory file, or skill conflicted with actual reality. Examples:

- A rule referenced a path that doesn't exist
- A memory recorded a stale function name or outdated fact
- A skill assumed a directory structure that has changed

If conflicts were encountered, write each to the session-issues directory:
- Derive project slug: `echo "$PWD" | sed 's|/|-|g'`
- Path: `~/.claude/projects/{project-slug}/session-issues/{YYYY-MM-DD}-{slug}.md`
- Create directory if needed
- Use the issue file format defined in `/session-issues` (sections: Issue title, Date, Source, Expected, Actual, Suggested Fix)

## Step 4: Output Everything (ALL text output happens here)

Print the complete summary as one block:

```
## Session Summary

### One-Line Summary
{one sentence}

### Key Changes
{chronological list — skip if no git changes}

### Current Status
{pending work, PRs, CI, blockers}

### Next Steps
{what to do next}

### Memory Review
{what was saved, or "No memory updates needed."}

### Consistency Audit
{what issues were found and filed, or "No consistency issues found."}
```

## Rules
- Be concise — each section should be 2-5 bullet points max
- Use conversation context as the primary source for all steps
- Steps 2 and 3 are about this session only — don't do a full-scan audit (use `/session-issues audit` for that)
- Do NOT output any summary text until Step 4 — all earlier steps are tool-only
