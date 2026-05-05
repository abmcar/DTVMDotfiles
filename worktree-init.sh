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

# Local FetchContent shared-cache hook: copy the env-aware CACHE block from
# main repo's CMakeLists.txt into this worktree, then skip-worktree it so the
# edit stays per-worktree and never gets staged. Without this hook, cmake in
# the worktree ignores FETCHCONTENT_BASE_DIR (skip-worktree is per-worktree
# git index state, not inherited from main). Idempotent.
#
# Rollback (per worktree, three steps — skip any one and the worktree looks
# clean but is not actually restored):
#   git -C <worktree> update-index --no-skip-worktree CMakeLists.txt
#   git -C <worktree> checkout -- CMakeLists.txt
#   # confirm: git -C <worktree> ls-files -v CMakeLists.txt   (expect "H")
MAIN_CML="$(dirname "$SCRIPT_DIR")/CMakeLists.txt"
WT_CML="$WORKTREE_PATH/CMakeLists.txt"
if [ -f "$MAIN_CML" ] && [ -f "$WT_CML" ] && \
   ! grep -q FETCHCONTENT_BASE_DIR "$WT_CML"; then
    PATCH="$(sed -n '/^# Local dev hook: honor FETCHCONTENT_BASE_DIR/,/^endif()/p' "$MAIN_CML")"
    if [ -z "$PATCH" ]; then
        echo "[worktree-init] WARN: FETCHCONTENT marker not found in $MAIN_CML; cmake hook NOT injected (worktree will re-download FetchContent deps)" >&2
    else
        awk -v patch="$PATCH" '
            /^project\(ZetaEngine/ { print; print ""; print patch; next }
            { print }
        ' "$WT_CML" > "$WT_CML.new" && mv "$WT_CML.new" "$WT_CML"
        # Verify awk anchor actually matched before committing to skip-worktree
        if grep -q FETCHCONTENT_BASE_DIR "$WT_CML"; then
            git -C "$WORKTREE_PATH" update-index --skip-worktree CMakeLists.txt
            ACTIONS+=("fetchcontent cmake hook injected")
        else
            echo "[worktree-init] WARN: project(ZetaEngine ...) anchor not found in $WT_CML; cmake hook NOT injected" >&2
        fi
    fi
fi

# Backup: hardlink FetchContent sources from main build/_deps into the
# worktree's build/_deps. Redundant with the env-var hook above, but covers
# the case where FETCHCONTENT_BASE_DIR is unset. Hardlink first; fall back
# to copy on cross-filesystem failure (rm first to avoid partial cp -al state).
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
