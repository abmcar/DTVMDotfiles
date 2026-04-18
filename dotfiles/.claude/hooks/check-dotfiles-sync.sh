#!/bin/bash
# PostToolUse hook: warn when a DTVMDotfiles-managed file is modified.
# Managed items (excluding perf/): .claude/, CLAUDE.md, CLAUDE.local.md, init.sh

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
case "$REL_PATH" in
    .claude/*|CLAUDE.md|CLAUDE.local.md|init.sh)
        echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[dotfiles-sync] A DTVMDotfiles-managed file was modified. Remember to run store.sh and push DTVMDotfiles before ending this session."}}'
        ;;
    docs/research/*)
        echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[paper-repo] docs/research/ is a separate git repo (DTVM-Papers). Remember to commit and push it independently before ending this session."}}'
        ;;
esac

exit 0
