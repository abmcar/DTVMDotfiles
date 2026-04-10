#!/bin/bash
# Stop hook: write a bare-bones session summary from git state.
# No AI — pure shell. The intelligent summary is /session-summary.

set -euo pipefail

# Only run in git repos
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Derive paths
PROJECT_SLUG=$(echo "$PWD" | sed 's|/|-|g')
SUMMARY_DIR="$HOME/.claude/projects/$PROJECT_SLUG/session-summaries"
mkdir -p "$SUMMARY_DIR"

BRANCH=$(git branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
    SHORT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BRANCH="detached-$SHORT_HASH"
fi
SANITIZED_BRANCH=$(echo "$BRANCH" | sed 's|/|--|g; s|[^a-zA-Z0-9._-]||g')

TIMESTAMP=$(date '+%Y-%m-%d-%H-%M-%S')
SESSION_PREFIX=$(date +%s | tail -c 9)
FILENAME="${TIMESTAMP}-${SESSION_PREFIX}-${SANITIZED_BRANCH}.md"

# Gather git state
GIT_STATUS=$(git status -s 2>/dev/null || echo "(no git status)")
GIT_LOG=$(git log --oneline -10 2>/dev/null || echo "(no git log)")
GIT_DIFF_STAT=$(git diff --stat 2>/dev/null || echo "(no changes)")
GIT_DIFF_CACHED=$(git diff --cached --stat 2>/dev/null || echo "(no staged changes)")

cat > "$SUMMARY_DIR/$FILENAME" << SUMMARY
# Session Summary: $BRANCH
**Date:** $(date '+%Y-%m-%d %H:%M')
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

# Also output context for the Stop prompt (memory review + audit still need AI)
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":\"[session-summary] Summary saved to $SUMMARY_DIR/$FILENAME. Now review this session for: (1) Memory: any pain points, user preferences, or workflow corrections worth saving to memory. (2) Consistency audit: any moments where a rule (.claude/rules/), memory file, or skill conflicted with actual reality — if so, write issues to ~/.claude/projects/$PROJECT_SLUG/session-issues/. Be fast and autonomous.\"}}"

exit 0
