---
description: Summarize the current session, review memory, and audit rule/memory/skill consistency
---

# Session Summary

Generate a concise summary of this session, then review memory and audit consistency. Three phases executed in order.

## Phase 1: Summary

### Gather Context

1. Run `git diff --stat` to see file changes
2. Run `git log --oneline -10` to see recent commits
3. Run `git status -s` to see working tree state
4. Check the task list if any tasks exist

If not in a git repo, skip git commands and rely on conversation context only.

### Output Format

Print the summary directly to the terminal:

#### One-Line Summary
One sentence: what this session is/was about.

#### Key Changes
Chronological list of what was done. If no git changes exist, skip this section entirely.

#### Current Status
- Pending work, uncommitted changes
- Open PRs or CI status (if relevant)
- Blockers or issues encountered

#### Next Steps
- What should be done next
- Suggested follow-up tasks or investigations

## Phase 2: Memory Review

After printing the summary, review this session for anything worth saving to memory:

- Pain points or frustrations the user expressed
- User preferences or workflow corrections (e.g., "don't do X", "always do Y")
- Non-obvious decisions that should inform future sessions

If anything qualifies, write to memory per the existing memory conventions (check existing memory files first to avoid duplicates, update existing ones if needed).

If nothing notable, say "No memory updates needed." and move on. Do NOT force-write.

## Phase 3: Consistency Audit

Review this session's conversation for any moments where a rule (`.claude/rules/`), memory file, or skill conflicted with actual reality. Examples:

- A rule referenced a path that doesn't exist
- A memory recorded a stale function name or outdated fact
- A skill assumed a directory structure that has changed

If conflicts were encountered, write each to the session-issues directory:
- Derive project slug: `echo "$PWD" | sed 's|/|-|g'`
- Path: `~/.claude/projects/{project-slug}/session-issues/{YYYY-MM-DD}-{slug}.md`
- Create directory if needed
- Use the issue file format defined in `/session-issues` (sections: Issue title, Date, Source, Expected, Actual, Suggested Fix)

If no conflicts were encountered, say "No consistency issues found." and finish.

## Rules
- Be concise — summary sections should be 2-5 bullet points max
- Use conversation context as the primary source for all three phases
- Phase 2 and 3 are about this session only — don't do a full-scan audit (use `/session-issues audit` for that)
