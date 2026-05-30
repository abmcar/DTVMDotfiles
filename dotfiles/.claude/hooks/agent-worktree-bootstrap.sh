#!/bin/bash
# Auto-initialize agent worktrees created by Claude Code's isolation:"worktree" mode.
# Delegates to DTVMDotfiles/worktree-init.sh — the single source of truth shared
# with the `worktree-bootstrap` skill.
#
# Called automatically from session-check.sh on SessionStart.
# Can also be run standalone: bash .claude/hooks/agent-worktree-bootstrap.sh

set -euo pipefail

# Only run in worktrees created by Claude Code (named <adjective>-<surname>-<hex>,
# e.g. bold-gagarin-c3db96 — no fixed prefix) and user-created worktrees, all of
# which live directly under .claude/worktrees/.
case "$PWD" in
    */.claude/worktrees/*) ;;
    *) exit 0 ;;
esac

# Sanity check: only act inside a real git worktree (avoid false matches such as
# a stale plain directory left under .claude/worktrees/).
git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Warm-path: already fully bootstrapped. Gated on a sentinel written only after a
# fully-successful worktree-init below, so a prior run that linked some symlinks
# but skipped others does not get locked in.
[ -e "$PWD/.claude/.worktree-bootstrapped" ] && exit 0

# Find main repo by walking up (agent worktrees live under <main-repo>/.claude/worktrees/)
d="$PWD"
while [ "$d" != "/" ] && [ ! -d "$d/DTVMDotfiles" ]; do d="$(dirname "$d")"; done
[ "$d" = "/" ] && exit 0

INIT_SCRIPT="$d/DTVMDotfiles/worktree-init.sh"
[ -f "$INIT_SCRIPT" ] || exit 0

# Write the warm-path sentinel only on a fully-successful init/sync. worktree-init.sh
# swallows BOTH worktree-sync and evmc-submodule failures and still exits 0, so
# require the critical dotfiles symlink AND the evmc submodule to actually exist
# (the two things --minimal sets up) — otherwise a partial init (e.g. a transient
# submodule-clone failure) would get locked in and never retried on a later session.
if bash "$INIT_SCRIPT" --minimal "$PWD" && [ -L "$PWD/.claude/rules" ] && [ -e "$PWD/evmc/include" ]; then
    mkdir -p "$PWD/.claude"
    touch "$PWD/.claude/.worktree-bootstrapped"
fi
exit 0
