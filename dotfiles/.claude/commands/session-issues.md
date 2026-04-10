---
description: Review and resolve rule/memory/skill consistency issues, or run a full audit
---

# Session Issues

The user invoked `/session-issues` with arguments: $ARGUMENTS

## Determine Mode

- If `$ARGUMENTS` contains "audit" → run **Full Audit** mode
- Otherwise → run **Review & Resolve** mode

## Review & Resolve Mode (default)

1. Derive the project slug: run `echo "$PWD" | sed 's|/|-|g'`
2. List all files in `~/.claude/projects/{project-slug}/session-issues/`
3. If no files exist, report "No unresolved issues." and stop.
4. For each issue file:
   a. Read and display the issue content
   b. Ask the user: fix it, skip it, or delete it?
   c. If fix: apply the suggested fix to the source rule/memory/skill file, then delete the issue file
   d. If delete: remove the issue file without fixing
   e. If skip: move to the next issue
5. Report summary: N fixed, N skipped, N deleted, N remaining.

## Full Audit Mode (`/session-issues audit`)

Proactively scan all configuration files for stale or incorrect content:

1. **Rules** (`.claude/rules/*.md`): For each rule, check any file paths, function names, or directory references it mentions. Verify they exist in the current codebase using Glob/Grep.

2. **Memory** (`~/.claude/projects/{project-slug}/memory/*.md`): For each memory file, check any concrete claims (file paths, function names, tool names). Verify they still hold.

3. **Skills** (`.agents/skills/*/SKILL.md`): For each skill, check referenced paths, commands, or assumptions. Verify they match current reality.

For each issue found, write to `~/.claude/projects/{project-slug}/session-issues/{YYYY-MM-DD}-{slug}.md` with format:

```
# Issue: {short description}
**Date:** {YYYY-MM-DD}
**Source:** {rule|memory|skill}: {filename}

## Expected (per rule/memory/skill)
{what it says}

## Actual
{what reality is}

## Suggested Fix
{how to update it}
```

After the scan, report: N issues found. Run `/session-issues` to review and fix them.

## Rules
- Be thorough but fast in audit mode — check concrete verifiable claims, not subjective opinions
- In resolve mode, always show the issue before asking what to do
- After fixing a source file, verify the fix is correct before deleting the issue
