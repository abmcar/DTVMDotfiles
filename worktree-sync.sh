#!/bin/bash
# Symlink dotfiles-managed configuration from the main DTVM repo into a git worktree.
# Usage: bash DTVMDotfiles/worktree-sync.sh <worktree-path>
#
# Creates exact symlinks for worktree configuration. DTVM-tracked AGENTS.md is
# generated from the DTVMDotfiles source; tracked .claude/skills remains owned
# by the target branch. Run once per worktree.
# User-level skills and client suppression policy are reconciled separately by
# release.sh or skills.sh; their state is independent of the worktree set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sync_common.sh
source "$SCRIPT_DIR/lib/sync_common.sh"

# --- Usage ---

if [ $# -lt 1 ]; then
    echo "Usage: bash DTVMDotfiles/worktree-sync.sh <worktree-path>"
    echo ""
    echo "Symlinks dotfiles configuration from the main repo into a git worktree."
    exit 1
fi

if [ ! -d "$1" ]; then
    echo "Error: $1 is not a valid directory"
    exit 1
fi

WORKTREE_PATH="$(cd "$1" && pwd)"

# --- Validation ---

if [ ! -f "$WORKTREE_PATH/.git" ]; then
    echo "Error: $WORKTREE_PATH does not appear to be a git worktree (no .git file)"
    exit 1
fi

if ! grep -q "^gitdir:" "$WORKTREE_PATH/.git" 2>/dev/null; then
    echo "Error: $WORKTREE_PATH/.git does not contain gitdir: — not a worktree"
    exit 1
fi

MAIN_REPO="$(cd "$PARENT_DIR" && pwd)"

if [ "$WORKTREE_PATH" = "$MAIN_REPO" ]; then
    echo "Error: target is the main repo itself, not a worktree"
    exit 1
fi

echo "Worktree sync: $1 → $MAIN_REPO"
echo ""

# --- Symlink helpers ---

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

MANAGED_PATHS=(
    ".claude/rules"
    ".claude/commands"
    ".claude/hooks"
    ".claude/agents"
    ".claude/skills"
    ".claude/settings.json"
    ".claude/settings.local.json"
    "CLAUDE.md"
    "AGENTS.md"
    "GEMINI.md"
    "init.sh"
    "perf"
)

# Resolve the authority for a managed destination. AGENTS.md is a deterministic
# adapter of the DTVMDotfiles CLAUDE.md SSOT, not a mirror of the main DTVM
# checkout's intentionally dirty generated file.
managed_source_path() {
    case "$1" in
        AGENTS.md) printf '%s' "$SCRIPT_DIR/dotfiles/CLAUDE.md" ;;
        *) printf '%s' "$MAIN_REPO/$1" ;;
    esac
}

git_tracks_path() {
    git -C "$WORKTREE_PATH" ls-files --error-unmatch -- "$1" \
        >/dev/null 2>&1
}

tracked_file_mode_is_current() {
    local display="$1"
    local link_path="$2"
    local index_entry index_mode object_id index_stage index_path

    index_entry="$(git -C "$WORKTREE_PATH" ls-files -s -- "$display")" ||
        return 1
    [[ "$index_entry" != *$'\n'* ]] || return 1
    read -r index_mode object_id index_stage index_path <<< "$index_entry"
    [ "$index_stage" = "0" ] || return 1
    [ "$index_path" = "$display" ] || return 1

    case "$index_mode" in
        100644) [ -f "$link_path" ] && [ ! -x "$link_path" ] ;;
        100755) [ -f "$link_path" ] && [ -x "$link_path" ] ;;
        *) return 1 ;;
    esac
}

# Permit either a clean tracked file that can be safely regenerated or an
# unstaged exact adapter from an earlier initializer run.
tracked_agents_path_is_safe() {
    local link_path="$1"
    local expected="$2"
    local diff_rc

    [ ! -L "$link_path" ] || return 1
    git_tracks_path AGENTS.md || return 1
    git -C "$WORKTREE_PATH" diff --cached --quiet -- AGENTS.md || return 1
    tracked_file_mode_is_current AGENTS.md "$link_path" || return 1

    if git -C "$WORKTREE_PATH" diff --quiet -- AGENTS.md; then
        return 0
    else
        diff_rc=$?
    fi
    [ "$diff_rc" -eq 1 ] || return 1
    cmp -s "$link_path" "$expected"
}

tracked_agents_path_is_current() {
    local link_path="$1"
    local expected="$2"

    [ ! -L "$link_path" ] || return 1
    git_tracks_path AGENTS.md || return 1
    git -C "$WORKTREE_PATH" diff --cached --quiet -- AGENTS.md || return 1
    tracked_file_mode_is_current AGENTS.md "$link_path" || return 1
    cmp -s "$link_path" "$expected"
}

tracked_skills_path_is_current() {
    local link_path="$1"
    local status_output

    [ -d "$link_path" ] && [ ! -L "$link_path" ] || return 1
    git_tracks_path .claude/skills || return 1
    status_output="$(
        git -C "$WORKTREE_PATH" status --porcelain --untracked-files=all -- \
            .claude/skills
    )" || return 1
    [ -z "$status_output" ]
}

agents_authority_is_current() {
    local expected="$1"
    local main_agents="$MAIN_REPO/AGENTS.md"
    local mode_summary

    [ -f "$expected" ] && [ ! -L "$expected" ] || return 1
    [ -f "$main_agents" ] && [ ! -L "$main_agents" ] || return 1
    if git -C "$MAIN_REPO" ls-files --error-unmatch -- AGENTS.md \
        >/dev/null 2>&1; then
        git -C "$MAIN_REPO" diff --cached --quiet -- AGENTS.md || return 1
        mode_summary="$(git -C "$MAIN_REPO" diff --summary -- AGENTS.md)" ||
            return 1
        [ -z "$mode_summary" ] || return 1
    fi
    cmp -s "$main_agents" "$expected"
}

preflight_managed_path() {
    local display="$1"
    local link_path="$WORKTREE_PATH/$display"
    local source
    source="$(managed_source_path "$display")"

    if [ "$display" = "AGENTS.md" ] &&
        ! agents_authority_is_current "$source"; then
        echo "Error: main AGENTS.md is not the deterministic DTVMDotfiles adapter: $MAIN_REPO/AGENTS.md" >&2
        return 1
    fi

    if [ "$display" = "AGENTS.md" ] && git_tracks_path "$display"; then
        if tracked_agents_path_is_safe "$link_path" "$source"; then
            return 0
        fi
        echo "Error: tracked AGENTS.md is not clean or the exact generated adapter: $link_path" >&2
        return 1
    fi

    if [ "$display" = ".claude/skills" ] && git_tracks_path "$display"; then
        if tracked_skills_path_is_current "$link_path"; then
            return 0
        fi
        echo "Error: tracked .claude/skills is not clean in the target worktree: $link_path" >&2
        return 1
    fi

    # Machine-local optional targets are absent on many installations.
    if [ ! -e "$source" ]; then
        if [ "$display" = "AGENTS.md" ]; then
            echo "Error: authoritative AGENTS.md source is missing: $source" >&2
            return 1
        fi
        return 0
    fi
    [ -L "$link_path" ] && return 0
    [ -e "$link_path" ] || return 0

    echo "Error: managed worktree path collision: $link_path" >&2
    echo "  Expected an exact link to $source" >&2
    return 1
}

verify_managed_path() {
    local display="$1"
    local link_path="$WORKTREE_PATH/$display"
    local source
    source="$(managed_source_path "$display")"

    if [ "$display" = "AGENTS.md" ] &&
        ! agents_authority_is_current "$source"; then
        echo "Error: AGENTS.md authority changed during synchronization" >&2
        return 1
    fi

    if [ "$display" = "AGENTS.md" ] && git_tracks_path "$display"; then
        if tracked_agents_path_is_current "$link_path" "$source"; then
            return 0
        fi
        echo "Error: generated AGENTS.md failed verification: $link_path" >&2
        return 1
    fi

    if [ "$display" = ".claude/skills" ] && git_tracks_path "$display"; then
        if tracked_skills_path_is_current "$link_path"; then
            return 0
        fi
        echo "Error: tracked .claude/skills failed verification: $link_path" >&2
        return 1
    fi

    [ -e "$source" ] || return 0

    if [ -L "$link_path" ] &&
        [ "$(readlink "$link_path")" = "$source" ]; then
        return 0
    fi

    echo "Error: managed worktree path failed verification: $link_path" >&2
    return 1
}

# Create a symlink from $1 (link path in worktree) to $2 (managed source).
# Handles conflict detection and reporting.
create_link() {
    local link_path="$1"
    local target="$2"
    local display="${link_path#"$WORKTREE_PATH"/}"

    # Optional source does not exist — skip silently.
    if [ ! -e "$target" ]; then
        return
    fi

    # Existing symlink (valid or dangling) — check target and relink if needed
    if [ -L "$link_path" ]; then
        local current_target
        current_target="$(readlink "$link_path")"
        if [ "$current_target" = "$target" ]; then
            printf "  ${GREEN}✓${NC} %s (already linked)\n" "$display"
            return
        fi

        rm -f "$link_path"
        ln -s "$target" "$link_path"
        printf "  ${CYAN}↻${NC} %s (relinked)\n" "$display"
        return
    fi

    # All tracked exceptions are handled before this generic link path.
    if [ -e "$link_path" ]; then
        echo "Error: managed worktree path changed after preflight: $link_path" >&2
        return 1
    fi

    # Create new symlink
    mkdir -p "$(dirname "$link_path")"
    ln -s "$target" "$link_path"
    printf "  ${GREEN}✓${NC} %s\n" "$display"
}

apply_managed_path() {
    local display="$1"
    local link_path="$WORKTREE_PATH/$display"
    local source
    source="$(managed_source_path "$display")"

    if [ "$display" = "AGENTS.md" ] && git_tracks_path "$display"; then
        tracked_agents_path_is_safe "$link_path" "$source" || return 1
        if cmp -s "$link_path" "$source"; then
            printf "  ${GREEN}✓${NC} %s (generated content current)\n" "$display"
        else
            cp -f "$source" "$link_path"
            printf "  ${CYAN}↻${NC} %s (generated from DTVMDotfiles)\n" "$display"
        fi
        return 0
    fi

    if [ "$display" = ".claude/skills" ] && git_tracks_path "$display"; then
        tracked_skills_path_is_current "$link_path" || return 1
        printf "  ${GREEN}✓${NC} %s (verified tracked branch content)\n" "$display"
        return 0
    fi

    create_link "$link_path" "$source"
}

# Refuse all collisions before changing any worktree-local managed path.
for managed_path in "${MANAGED_PATHS[@]}"; do
    preflight_managed_path "$managed_path"
done

# --- .claude/ subdirectories and files ---

# Ensure .claude/ directory exists (worktree may only have skills/ inside it)
mkdir -p "$WORKTREE_PATH/.claude"

for managed_path in "${MANAGED_PATHS[@]}"; do
    apply_managed_path "$managed_path"
done

# Do not report success unless every present managed target is exact.
for managed_path in "${MANAGED_PATHS[@]}"; do
    verify_managed_path "$managed_path"
done

echo ""
echo "✓ Worktree sync complete"
