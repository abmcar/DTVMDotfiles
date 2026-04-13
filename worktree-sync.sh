#!/bin/bash
# Symlink dotfiles-managed configuration from the main DTVM repo into a git worktree.
# Usage: bash DTVMDotfiles/worktree-sync.sh <worktree-path>
#
# Creates symlinks for rules, commands, hooks, agents, settings, CLAUDE.md, etc.
# so that a Claude Code session in the worktree has full project configuration.
# Symlinks mean changes in the main repo are immediately visible — run once per worktree.

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
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Create a symlink from $1 (link path in worktree) to $2 (target in main repo).
# Handles conflict detection and reporting.
create_link() {
    local link_path="$1"
    local target="$2"
    local display="${link_path#"$WORKTREE_PATH"/}"

    # Target doesn't exist in main repo — skip silently
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

    # Real file or directory exists — do not overwrite
    if [ -e "$link_path" ]; then
        printf "  ${YELLOW}⚠${NC} %s (real file/dir exists, skipped)\n" "$display"
        return
    fi

    # Create new symlink
    mkdir -p "$(dirname "$link_path")"
    ln -s "$target" "$link_path"
    printf "  ${GREEN}✓${NC} %s\n" "$display"
}

# --- .claude/ subdirectories and files ---

# Ensure .claude/ directory exists (worktree may only have skills/ inside it)
mkdir -p "$WORKTREE_PATH/.claude"

# Managed directories — symlink each one
for dir in rules commands hooks agents; do
    create_link "$WORKTREE_PATH/.claude/$dir" "$MAIN_REPO/.claude/$dir"
done

# Managed files inside .claude/
for file in settings.json settings.local.json; do
    create_link "$WORKTREE_PATH/.claude/$file" "$MAIN_REPO/.claude/$file"
done

# Report skipped items
printf "  - .claude/skills/ (git-tracked, skipped)\n"

# --- Root-level files ---

for file in CLAUDE.md CLAUDE.local.md AGENTS.md GEMINI.md init.sh; do
    create_link "$WORKTREE_PATH/$file" "$MAIN_REPO/$file"
done

# perf/ directory
create_link "$WORKTREE_PATH/perf" "$MAIN_REPO/perf"

echo ""
echo "✓ Worktree sync complete"
