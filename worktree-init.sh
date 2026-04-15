#!/bin/bash
# Initialize a DTVM git worktree: submodules + dotfiles sync.
# Single source of truth shared by:
#   - .agents/skills/worktree-bootstrap (interactive skill)
#   - .claude/hooks/agent-worktree-bootstrap.sh (SessionStart hook)
#
# Usage:
#   bash DTVMDotfiles/worktree-init.sh [--minimal] <worktree-path>
#
# Flags:
#   --minimal   Only init evmc/ submodule (fast path for agent sessions).
#               Default: recursive init (evmc/ + tests/wast/spec).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MINIMAL=0
if [ "${1:-}" = "--minimal" ]; then
    MINIMAL=1
    shift
fi

if [ $# -lt 1 ]; then
    echo "Usage: bash DTVMDotfiles/worktree-init.sh [--minimal] <worktree-path>"
    exit 1
fi

WORKTREE_PATH="$(cd "$1" && pwd)"
ACTIONS=()

if [ $MINIMAL -eq 1 ]; then
    if [ ! -d "$WORKTREE_PATH/evmc/include" ]; then
        if git -C "$WORKTREE_PATH" submodule update --init evmc >/dev/null 2>&1; then
            ACTIONS+=("evmc submodule initialized")
        fi
    fi
else
    if git -C "$WORKTREE_PATH" submodule update --init --recursive >/dev/null 2>&1; then
        ACTIONS+=("submodules initialized (recursive)")
    else
        echo "Error: submodule init failed" >&2
        exit 1
    fi
fi

if bash "$SCRIPT_DIR/worktree-sync.sh" "$WORKTREE_PATH" >/dev/null 2>&1; then
    ACTIONS+=("dotfiles synced")
fi

if [ ${#ACTIONS[@]} -gt 0 ]; then
    ( IFS=', '; echo "[worktree-init] ${ACTIONS[*]}" )
fi
exit 0
