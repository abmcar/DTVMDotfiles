#!/bin/bash
# Stop hook: write a bare-bones session summary from git state.
# No AI — pure shell. The intelligent summary is /session-summary.

set -euo pipefail

# Only run in git repos
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Derive paths (bash builtins, no sed forks)
PROJECT_SLUG="${PWD//\//-}"
SUMMARY_DIR="$HOME/.claude/projects/$PROJECT_SLUG/session-summaries"
mkdir -p "$SUMMARY_DIR"

BRANCH=$(git branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
    SHORT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BRANCH="detached-$SHORT_HASH"
fi
# Sanitize branch: / → --, strip non-alphanumeric (bash builtins)
SANITIZED_BRANCH="${BRANCH//\//-}"
SANITIZED_BRANCH="${SANITIZED_BRANCH//[^a-zA-Z0-9._-]/}"

NOW=$(date '+%Y-%m-%d-%H-%M-%S')
SESSION_PREFIX="${EPOCHSECONDS:-$(date +%s)}"
SESSION_PREFIX="${SESSION_PREFIX: -8}"
FILENAME="${NOW}-${SESSION_PREFIX}-${SANITIZED_BRANCH}.md"
DATE_DISPLAY="${NOW:0:10} ${NOW:11:2}:${NOW:14:2}"

# Gather git state
GIT_STATUS=$(git status -s 2>/dev/null || echo "(no git status)")
GIT_LOG=$(git log --oneline -10 2>/dev/null || echo "(no git log)")
GIT_DIFF_STAT=$(git diff --stat 2>/dev/null || echo "(no changes)")
GIT_DIFF_CACHED=$(git diff --cached --stat 2>/dev/null || echo "(no staged changes)")

cat > "$SUMMARY_DIR/$FILENAME" << SUMMARY
# Session Summary: $BRANCH
**Date:** $DATE_DISPLAY
**Type:** Auto-generated (git state only — run /session-summary for intelligent summary)

## Recent Commits
\`\`\`
$GIT_LOG
\`\`\`

## Uncommitted Changes
\`\`\`
$GIT_STATUS
\`\`\`

## Diff Stats
**Unstaged:**
\`\`\`
$GIT_DIFF_STAT
\`\`\`

**Staged:**
\`\`\`
$GIT_DIFF_CACHED
\`\`\`
SUMMARY

exit 0
