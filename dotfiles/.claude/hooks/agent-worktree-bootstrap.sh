#!/bin/bash
# Auto-initialize agent worktrees created by Claude Code's isolation:"worktree" mode.
# Delegates to DTVMDotfiles/worktree-init.sh — the single source of truth shared
# with the `worktree-bootstrap` skill.
#
# Called automatically from session-check.sh on SessionStart.
# Can also be run standalone: bash .claude/hooks/agent-worktree-bootstrap.sh

set -euo pipefail

# Only run in agent worktrees (created by Claude Code)
case "$PWD" in
    */.claude/worktrees/agent-*) ;;
    *) exit 0 ;;
esac

# Warm-path: already bootstrapped (dotfiles synced + evmc initialized)
[ -L "$PWD/.claude/rules" ] && [ -e "$PWD/evmc/include" ] && exit 0

# Find main repo by walking up (agent worktrees live under <main-repo>/.claude/worktrees/)
d="$PWD"
while [ "$d" != "/" ] && [ ! -d "$d/DTVMDotfiles" ]; do d="$(dirname "$d")"; done
[ "$d" = "/" ] && exit 0

INIT_SCRIPT="$d/DTVMDotfiles/worktree-init.sh"
[ -f "$INIT_SCRIPT" ] || exit 0

bash "$INIT_SCRIPT" --minimal "$PWD" || true
exit 0
