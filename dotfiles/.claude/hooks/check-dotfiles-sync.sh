#!/bin/bash
# PostToolUse hook: warn when a DTVMDotfiles-managed file is modified.
# Managed items (excluding perf/): .claude/, CLAUDE.md, init.sh
# (CLAUDE.local.md is per-machine since 2026-05-14, not managed)

set -euo pipefail

INPUT=$(cat)
# Extract file_path without jq for lower overhead on every Edit/Write
FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' | head -1) || true

[ -z "$FILE_PATH" ] && exit 0

# Resolve repo root (the directory containing .claude/)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Make path relative to repo root
REL_PATH="${FILE_PATH#"$REPO_ROOT"/}"

# If path didn't change, it's outside the repo
[ "$REL_PATH" = "$FILE_PATH" ] && exit 0

# Check against managed items (no perf/)
MANIFEST="$REPO_ROOT/.claude/.dtvm-manifest.json"
case "$REL_PATH" in
    .claude/*|CLAUDE.md|init.sh)
        # store.sh is manifest-guided — only files in the manifest will be picked up.
        # New files in managed directories need a one-time bootstrap via release.sh.
        if [ -f "$MANIFEST" ] && grep -q "\"$REL_PATH\":" "$MANIFEST"; then
            echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[dotfiles-sync] A DTVMDotfiles-managed file was modified. Remember to run store.sh and push DTVMDotfiles before ending this session."}}'
        else
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"[dotfiles-sync] $REL_PATH is in a managed directory but NOT yet in .claude/.dtvm-manifest.json. store.sh will skip it. Bootstrap once with: cp '$REL_PATH' DTVMDotfiles/dotfiles/'$REL_PATH' && bash DTVMDotfiles/release.sh\"}}"
        fi
        ;;
    docs/research/*)
        echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[paper-repo] docs/research/ is a separate git repo (DTVM-Papers). Remember to commit and push it independently before ending this session."}}'
        ;;
esac

exit 0
