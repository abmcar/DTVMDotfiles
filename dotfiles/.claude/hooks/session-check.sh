#!/bin/bash
# SessionStart hook: bootstrap agent worktrees + emit cached housekeeping report.
# Zero network calls, zero file hashing — just reads files.

set -euo pipefail

OUTPUT=""

# Part 0: Auto-bootstrap agent worktrees (submodule init + dotfiles sync)
BOOTSTRAP_HOOK="$(dirname "${BASH_SOURCE[0]}")/agent-worktree-bootstrap.sh"
if [ -f "$BOOTSTRAP_HOOK" ]; then
    BOOTSTRAP_OUT="$(bash "$BOOTSTRAP_HOOK" 2>/dev/null)" || true
    if [ -n "${BOOTSTRAP_OUT:-}" ]; then
        OUTPUT="$BOOTSTRAP_OUT"
    fi
fi

# Part 1: Cached housekeeping report (from daily cron)
REPORT="$HOME/.claude/session-check-report.txt"
if [ -f "$REPORT" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        AGE=$(( ${EPOCHSECONDS:-$(date +%s)} - $(stat -f %m "$REPORT") ))
    else
        AGE=$(( ${EPOCHSECONDS:-$(date +%s)} - $(stat -c %Y "$REPORT") ))
    fi
    if [ "$AGE" -le 86400 ]; then
        CONTENT=$(<"$REPORT")
        if [ -n "$CONTENT" ]; then
            if [ -n "$OUTPUT" ]; then
                OUTPUT="$OUTPUT
$CONTENT"
            else
                OUTPUT="$CONTENT"
            fi
        fi
    fi
fi

# Emit combined output — use printf for portable JSON encoding
[ -z "$OUTPUT" ] && exit 0

# Escape for JSON: backslash, double-quote, then convert newlines
JSON_OUTPUT="${OUTPUT//\\/\\\\}"
JSON_OUTPUT="${JSON_OUTPUT//\"/\\\"}"
JSON_OUTPUT="${JSON_OUTPUT//$'\t'/\\t}"
JSON_OUTPUT="${JSON_OUTPUT//$'\n'/\\n}"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$JSON_OUTPUT"
exit 0
