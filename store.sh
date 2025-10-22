#!/bin/bash

# Store script for DTVMDotfiles
# This script syncs files from the parent DTVM directory to the dotfiles folder
# Usage: ./store.sh (when running from DTVMDotfiles directory)

set -e

# Get the script's directory and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Define files and directories to sync from parent to dotfiles
# Array of (source in parent, destination in dotfiles) pairs
SYNC_ITEMS=(
    ".claude:dotfiles/.claude"
    ".claude/settings.local.json:dotfiles/.claude/settings.local.json"
    ".git/info/exclude:dotfiles/.git/info/exclude"
    "qa.md:dotfiles/qa.md"
    "init.sh:dotfiles/init.sh"
    "CLAUDE.md:dotfiles/CLAUDE.md"
)

echo "Store script - Syncing files from $PARENT_DIR to $DOTFILES_DIR"
echo ""

# Store files from parent directory to dotfiles
for item in "${SYNC_ITEMS[@]}"; do
    IFS=':' read -r src dst <<< "$item"

    src_path="$PARENT_DIR/$src"
    dst_path="$DOTFILES_DIR/${dst#dotfiles/}"

    if [ ! -e "$src_path" ]; then
        echo "Warning: Source not found: $src_path"
        continue
    fi

    # Create destination directory if needed
    dst_dir=$(dirname "$dst_path")
    mkdir -p "$dst_dir"

    if [ -d "$src_path" ]; then
        # Sync directory
        echo "  Storing directory: $src → ${dst#dotfiles/}"
        rm -rf "$dst_path"
        cp -r "$src_path" "$dst_path"
    else
        # Sync file
        echo "  Storing file: $src → ${dst#dotfiles/}"
        cp -f "$src_path" "$dst_path"
    fi
done

echo ""
echo "✓ Store operation complete"
echo "Files have been synced to dotfiles folder"
