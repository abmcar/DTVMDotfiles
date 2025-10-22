#!/bin/bash

# Release script for DTVMDotfiles
# This script releases files from DTVMDotfiles/dotfiles to the external DTVM directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"

# Check if parent DTVM directory exists
if [ ! -d "$PARENT_DIR" ]; then
    echo "Error: Parent DTVM directory not found at $PARENT_DIR"
    exit 1
fi

# Define files and directories to release
# Array of (source in dotfiles, destination in parent) pairs
RELEASE_ITEMS=(
    "dotfiles/.claude:.claude"
    "dotfiles/.git/info/exclude:.git/info/exclude"
    "dotfiles/qa.md:qa.md"
    "dotfiles/init.sh:init.sh"
    "dotfiles/CLAUDE.md:CLAUDE.md"
)

echo "Release script - Releasing files from DTVMDotfiles to $PARENT_DIR"
echo ""

# Release files from dotfiles to parent directory
for item in "${RELEASE_ITEMS[@]}"; do
    IFS=':' read -r src dst <<< "$item"

    src_path="$SCRIPT_DIR/$src"
    dst_path="$PARENT_DIR/$dst"

    if [ ! -e "$src_path" ]; then
        echo "Warning: Source not found: $src_path"
        continue
    fi

    # Create destination directory if needed
    dst_dir=$(dirname "$dst_path")
    mkdir -p "$dst_dir"

    if [ -d "$src_path" ]; then
        # Release directory
        echo "  Releasing directory: $src → $dst"
        rm -rf "$dst_path"
        cp -r "$src_path" "$dst_path"
    else
        # Release file
        echo "  Releasing file: $src → $dst"
        cp -f "$src_path" "$dst_path"
    fi
done

echo ""
echo "✓ Release operation complete"
