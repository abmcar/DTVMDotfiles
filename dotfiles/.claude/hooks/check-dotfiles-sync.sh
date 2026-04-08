#!/bin/bash
# PostToolUse hook: warn when a DTVMDotfiles-managed file is modified.
# Managed items (excluding perf/): .claude/, CLAUDE.md, CLAUDE.local.md, init.sh

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

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
esac

exit 0
