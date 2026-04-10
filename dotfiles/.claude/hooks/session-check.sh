#!/bin/bash
# SessionStart hook: display cached housekeeping report + check for unresolved issues.
# Zero network calls, zero file hashing — just reads files.

set -euo pipefail

OUTPUT=""

# Part 1: Cached housekeeping report (from daily cron)
REPORT="$HOME/.claude/session-check-report.txt"
if [ -f "$REPORT" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        AGE=$(( $(date +%s) - $(stat -f %m "$REPORT") ))
    else
        AGE=$(( $(date +%s) - $(stat -c %Y "$REPORT") ))
    fi
    if [ "$AGE" -le 86400 ]; then
        CONTENT=$(cat "$REPORT")
        [ -n "$CONTENT" ] && OUTPUT="$CONTENT"
    fi
fi

# Part 2: Unresolved session issues
PROJECT_SLUG=$(echo "$PWD" | sed 's|/|-|g')
ISSUES_DIR="$HOME/.claude/projects/$PROJECT_SLUG/session-issues"
if [ -d "$ISSUES_DIR" ]; then
    ISSUE_COUNT=$(find "$ISSUES_DIR" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$ISSUE_COUNT" -gt 0 ]; then
        ISSUE_MSG="[issues] $ISSUE_COUNT unresolved rule/memory/skill issue(s) — run /session-issues to review"
        if [ -n "$OUTPUT" ]; then
            OUTPUT="$OUTPUT
$ISSUE_MSG"
        else
            OUTPUT="$ISSUE_MSG"
        fi
    fi
fi

# Emit combined output
[ -z "$OUTPUT" ] && exit 0
JSON_OUTPUT=$(echo "$OUTPUT" | sed 's/\\/\\\\/g; s/"/\\"/g; :a; N; $!ba; s/\n/\\n/g')
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$JSON_OUTPUT\"}}"
exit 0
