#!/bin/bash
# SessionStart hook: check for stale items at the beginning of each session.
# Reports: DTVMDotfiles drift, unarchived change docs, paper repo uncommitted changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WARNINGS=""

# 1. DTVMDotfiles drift: check if deployed files differ from dotfiles
if [ -x "$REPO_ROOT/DTVMDotfiles/diff.sh" ]; then
    DRIFT=$(bash "$REPO_ROOT/DTVMDotfiles/diff.sh" 2>/dev/null | grep -c "CHANGED\|MISSING" || true)
    if [ "$DRIFT" -gt 0 ]; then
        WARNINGS="${WARNINGS}[dotfiles-drift] $DRIFT file(s) out of sync with DTVMDotfiles. Run: bash DTVMDotfiles/store.sh\n"
    fi
fi

# 2. Unarchived change docs: check docs/changes/ for Implemented status
if [ -d "$REPO_ROOT/docs/changes" ]; then
    IMPLEMENTED=""
    for f in "$REPO_ROOT"/docs/changes/*/README.md; do
        [ -f "$f" ] || continue
        if grep -q "Status.*Implemented" "$f" 2>/dev/null; then
            SLUG=$(basename "$(dirname "$f")")
            IMPLEMENTED="${IMPLEMENTED}  - $SLUG\n"
        fi
    done
    if [ -n "$IMPLEMENTED" ]; then
        WARNINGS="${WARNINGS}[unarchived] Change docs with status Implemented not yet archived:\n${IMPLEMENTED}"
    fi
fi

# 3. Paper repo uncommitted changes
PAPER_DIR="$REPO_ROOT/docs/research"
if [ -d "$PAPER_DIR/.git" ]; then
    PAPER_DIRTY=$(git -C "$PAPER_DIR" status --porcelain 2>/dev/null | wc -l)
    if [ "$PAPER_DIRTY" -gt 0 ]; then
        WARNINGS="${WARNINGS}[paper-repo] $PAPER_DIRTY uncommitted change(s) in DTVM-Papers.\n"
    fi
fi

# 4. Merged PRs without change docs (check recent merges in last 14 days)
if command -v gh &>/dev/null; then
    RECENT_MERGES=$(gh pr list --repo DTVMStack/DTVM --state merged --author abmcar --limit 10 \
        --json number,title,mergedAt,additions \
        --jq '[.[] | select(.additions > 50)] | length' 2>/dev/null || echo "0")
    # Just a reminder, not an exact check
    if [ "$RECENT_MERGES" -gt 0 ]; then
        WARNINGS="${WARNINGS}[pr-check] $RECENT_MERGES recently merged PR(s) with 50+ additions. Verify change docs and paper directions are up to date.\n"
    fi
fi

if [ -n "$WARNINGS" ]; then
    # Escape for JSON
    JSON_WARNINGS=$(printf "$WARNINGS" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"[session-check] Housekeeping items detected:\\n${JSON_WARNINGS}\"}}"
fi

exit 0
