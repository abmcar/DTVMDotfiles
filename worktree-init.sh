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

# Reuse main repo's submodule clones across worktrees instead of re-cloning per worktree.
if [ "$(git -C "$WORKTREE_PATH" config --get submodule.alternateLocation 2>/dev/null)" != "superproject" ]; then
    git -C "$WORKTREE_PATH" config submodule.alternateLocation superproject
    git -C "$WORKTREE_PATH" config submodule.alternateErrorStrategy info
    ACTIONS+=("submodule alternate enabled")
fi

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

# Seed CMake FetchContent sources from main build. CMake does not read
# FETCHCONTENT_BASE_DIR from env, so manual seeding is the only reliable
# cross-worktree source cache. Hardlink first; fall back to copy on
# cross-filesystem failure (rm first to avoid partial cp -al state).
MAIN_DEPS="$(dirname "$SCRIPT_DIR")/build/_deps"
if [ -d "$MAIN_DEPS" ]; then
    mkdir -p "$WORKTREE_PATH/build/_deps"
    SEEDED=0
    for src in "$MAIN_DEPS"/*-src; do
        [ -d "$src" ] || continue
        name="$(basename "$src")"
        target="$WORKTREE_PATH/build/_deps/$name"
        [ -e "$target" ] && continue
        if cp -al "$src" "$target" 2>/dev/null; then
            SEEDED=$((SEEDED + 1))
        elif rm -rf "$target" 2>/dev/null && cp -a "$src" "$target" 2>/dev/null; then
            SEEDED=$((SEEDED + 1))
        fi
    done
    if [ $SEEDED -gt 0 ]; then
        ACTIONS+=("fetchcontent seeded ($SEEDED dep(s))")
    fi
fi

if [ ${#ACTIONS[@]} -gt 0 ]; then
    ( IFS=', '; echo "[worktree-init] ${ACTIONS[*]}" )
fi
exit 0
