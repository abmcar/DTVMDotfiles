#!/bin/bash
# Initialize a DTVM git worktree: submodules + dotfiles sync.
# Single source of truth shared by:
#   - user-level dtvm-worktree-bootstrap (interactive skill)
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
REPO_ROOT="$(cd "${DTVMDOTFILES_PARENT_DIR:-$SCRIPT_DIR/..}" && pwd)"

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
SUBMODULE_LOG="$(mktemp)"
MIRROR_LOG="$(mktemp)"
GIT_MIRROR_DIR="${DTVM_GIT_MIRROR_DIR:-$HOME/.cache/git-mirrors}"
USE_GIT_MIRRORS="${DTVM_WORKTREE_INIT_USE_GIT_MIRRORS:-1}"
REFRESH_GIT_MIRRORS="${DTVM_WORKTREE_INIT_REFRESH_GIT_MIRRORS:-0}"
GIT_SUBMODULE_CONFIG=(-c protocol.file.allow=always)

FULL_GIT_MIRRORS=(
    "DTVMStack-evmc.git|https://github.com/DTVMStack/evmc.git|https://github.com/DTVMStack/evmc.git|.git/modules/evmc"
    "WebAssembly-spec.git|https://github.com/WebAssembly/spec.git|https://github.com/WebAssembly/spec.git|.git/modules/tests/wast/spec"
    "KaTeX.git|https://github.com/KaTeX/KaTeX.git|https://github.com/KaTeX/KaTeX.git|.git/modules/tests/wast/spec/modules/document/core/util/katex"
    "katex-fonts.git|https://github.com/KaTeX/katex-fonts.git|https://github.com/KaTeX/katex-fonts|.git/modules/tests/wast/spec/modules/document/core/util/katex/modules/submodules/katex-fonts"
    "katex-test-fonts.git|https://github.com/KaTeX/katex-test-fonts.git|https://github.com/KaTeX/katex-test-fonts.git|.git/modules/tests/wast/spec/modules/document/core/util/katex/modules/submodules/katex-test-fonts"
)
MINIMAL_GIT_MIRRORS=(
    "DTVMStack-evmc.git|https://github.com/DTVMStack/evmc.git|https://github.com/DTVMStack/evmc.git|.git/modules/evmc"
)

cleanup() {
    rm -f "$SUBMODULE_LOG" "$MIRROR_LOG"
}
trap cleanup EXIT

isEnabled() {
    case "$1" in
        1 | true | TRUE | yes | YES | on | ON) return 0 ;;
        *) return 1 ;;
    esac
}

warn() {
    echo "Warning: $*" >&2
}

isBareGitRepo() {
    [ -d "$1" ] &&
        git -C "$1" rev-parse --is-bare-repository >/dev/null 2>&1 &&
        [ "$(git -C "$1" rev-parse --is-bare-repository 2>/dev/null)" = "true" ]
}

isGitRepo() {
    [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

addGitMirrorRewrite() {
    local mirror_path="$1"
    local instead_of="$2"
    GIT_SUBMODULE_CONFIG+=(-c "url.$mirror_path.insteadOf=$instead_of")
}

refreshGitMirror() {
    local mirror_path="$1"
    local label="$2"

    : > "$MIRROR_LOG"
    if git -C "$mirror_path" remote update --prune > "$MIRROR_LOG" 2>&1; then
        return 0
    fi

    warn "git mirror refresh failed for $label; using existing mirror contents"
    sed 's/^/  /' "$MIRROR_LOG" >&2
    return 1
}

ensureGitMirror() {
    local dirname="$1"
    local clone_url="$2"
    local instead_of="$3"
    local seed_relpath="$4"
    local mirror_path="$GIT_MIRROR_DIR/$dirname"
    local seed_path="$REPO_ROOT/$seed_relpath"

    if isBareGitRepo "$mirror_path"; then
        if isEnabled "$REFRESH_GIT_MIRRORS"; then
            refreshGitMirror "$mirror_path" "$dirname" || true
        fi
        addGitMirrorRewrite "$mirror_path" "$instead_of"
        return 0
    fi

    if [ -e "$mirror_path" ]; then
        warn "git mirror path exists but is not a bare repository: $mirror_path"
        return 1
    fi

    mkdir -p "$GIT_MIRROR_DIR"

    if isGitRepo "$seed_path"; then
        : > "$MIRROR_LOG"
        if git -c protocol.file.allow=always clone --mirror "$seed_path" "$mirror_path" > "$MIRROR_LOG" 2>&1; then
            ACTIONS+=("git mirror seeded: $dirname")
            addGitMirrorRewrite "$mirror_path" "$instead_of"
            return 0
        fi

        rm -rf "$mirror_path"
        warn "git mirror local seed failed for $dirname; falling back to upstream clone"
        sed 's/^/  /' "$MIRROR_LOG" >&2
    fi

    : > "$MIRROR_LOG"
    if git clone --mirror "$clone_url" "$mirror_path" > "$MIRROR_LOG" 2>&1; then
        ACTIONS+=("git mirror cached: $dirname")
        addGitMirrorRewrite "$mirror_path" "$instead_of"
        return 0
    fi

    rm -rf "$mirror_path"
    warn "git mirror cache unavailable for $clone_url; falling back to configured upstream URL"
    sed 's/^/  /' "$MIRROR_LOG" >&2
    return 1
}

setupGitMirrors() {
    local spec dirname clone_url instead_of seed_relpath mirror_specs

    isEnabled "$USE_GIT_MIRRORS" || return 0

    if [ $MINIMAL -eq 1 ]; then
        mirror_specs=("${MINIMAL_GIT_MIRRORS[@]}")
    else
        mirror_specs=("${FULL_GIT_MIRRORS[@]}")
    fi

    for spec in "${mirror_specs[@]}"; do
        IFS='|' read -r dirname clone_url instead_of seed_relpath <<< "$spec"
        ensureGitMirror "$dirname" "$clone_url" "$instead_of" "$seed_relpath" || true
    done
}

refreshConfiguredGitMirrors() {
    local spec dirname clone_url instead_of seed_relpath mirror_specs mirror_path refreshed=1

    isEnabled "$USE_GIT_MIRRORS" || return 1

    if [ $MINIMAL -eq 1 ]; then
        mirror_specs=("${MINIMAL_GIT_MIRRORS[@]}")
    else
        mirror_specs=("${FULL_GIT_MIRRORS[@]}")
    fi

    for spec in "${mirror_specs[@]}"; do
        IFS='|' read -r dirname clone_url instead_of seed_relpath <<< "$spec"
        mirror_path="$GIT_MIRROR_DIR/$dirname"
        if isBareGitRepo "$mirror_path"; then
            refreshGitMirror "$mirror_path" "$dirname" && refreshed=0
        fi
    done

    return "$refreshed"
}

gitSubmodule() {
    git -C "$WORKTREE_PATH" "${GIT_SUBMODULE_CONFIG[@]}" submodule "$@"
}

printSubmoduleFailure() {
    local description="$1"
    echo "Error: $description failed" >&2
    if [ -s "$SUBMODULE_LOG" ]; then
        sed 's/^/  /' "$SUBMODULE_LOG" >&2
    fi
}

runSubmoduleUpdate() {
    local description="$1"
    shift

    : > "$SUBMODULE_LOG"
    if gitSubmodule update "$@" > "$SUBMODULE_LOG" 2>&1; then
        return 0
    fi

    if isEnabled "$USE_GIT_MIRRORS" && ! isEnabled "$REFRESH_GIT_MIRRORS"; then
        warn "$description failed; refreshing existing git mirrors and retrying once"
        if refreshConfiguredGitMirrors; then
            : > "$SUBMODULE_LOG"
            if gitSubmodule update "$@" > "$SUBMODULE_LOG" 2>&1; then
                ACTIONS+=("git mirrors refreshed")
                return 0
            fi
        fi
    fi

    printSubmoduleFailure "$description"
    return 1
}

# Reuse main repo's submodule clones across worktrees instead of re-cloning per worktree.
if [ "$(git -C "$WORKTREE_PATH" config --get submodule.alternateLocation 2>/dev/null)" != "superproject" ]; then
    git -C "$WORKTREE_PATH" config submodule.alternateLocation superproject
    git -C "$WORKTREE_PATH" config submodule.alternateErrorStrategy info
    ACTIONS+=("submodule alternate enabled")
fi

setupGitMirrors

if [ $MINIMAL -eq 1 ]; then
    if [ ! -d "$WORKTREE_PATH/evmc/include" ]; then
        if runSubmoduleUpdate "evmc submodule init" --init evmc; then
            ACTIONS+=("evmc submodule initialized")
        else
            exit 1
        fi
    fi
else
    if runSubmoduleUpdate "recursive submodule init" --init --recursive; then
        ACTIONS+=("submodules initialized (recursive)")
    else
        exit 1
    fi
fi

if ! bash "$SCRIPT_DIR/worktree-sync.sh" "$WORKTREE_PATH" >/dev/null; then
    echo "Error: worktree dotfiles synchronization failed" >&2
    exit 1
fi
ACTIONS+=("dotfiles synced")

# ccache and versioned FetchContent sharing are configured by the project's
# CMakeLists.txt. Worktrees share source/population data and the ccache object
# store, while each build keeps its own third-party binary directories.

if [ ${#ACTIONS[@]} -gt 0 ]; then
    ( IFS=', '; echo "[worktree-init] ${ACTIONS[*]}" )
fi
exit 0
