#!/bin/bash
# Auto-initialize agent worktrees created by Claude Code's isolation:"worktree" mode.
# Ensures submodules and dotfiles are available for build/test operations.
#
# Called automatically from session-check.sh on SessionStart.
# Can also be run standalone: bash .claude/hooks/agent-worktree-bootstrap.sh

set -euo pipefail

# Only run in agent worktrees (created by Claude Code)
case "$PWD" in
    */.claude/worktrees/agent-*) ;;
    *) exit 0 ;;
esac

WORKTREE_PATH="$PWD"
ACTIONS=""

# Find main repo via git common dir
MAIN_GIT_DIR="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
MAIN_REPO="$(cd "$MAIN_GIT_DIR/.." && pwd)"

# 1. Initialize submodules (evmc/ needed for cmake configure)
if [ ! -d "$WORKTREE_PATH/evmc/include" ]; then
    if git submodule update --init 2>/dev/null; then
        ACTIONS="submodules initialized"
    fi
fi

# 2. Sync dotfiles from main repo (rules, commands, hooks, settings)
SYNC_SCRIPT="$MAIN_REPO/DTVMDotfiles/worktree-sync.sh"
if [ -f "$SYNC_SCRIPT" ] && [ ! -L "$WORKTREE_PATH/.claude/rules" ]; then
    if bash "$SYNC_SCRIPT" "$WORKTREE_PATH" >/dev/null 2>&1; then
        ACTIONS="${ACTIONS:+$ACTIONS, }dotfiles synced"
    fi
fi

if [ -n "$ACTIONS" ]; then
    echo "[worktree-bootstrap] $ACTIONS"
fi
exit 0
