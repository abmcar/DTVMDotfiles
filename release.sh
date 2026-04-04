#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sync_common.sh
source "$SCRIPT_DIR/lib/sync_common.sh"

if [ ! -d "$PARENT_DIR" ]; then
    echo "Error: Parent DTVM directory not found at $PARENT_DIR"
    exit 1
fi

echo "Release script - Releasing files from DTVMDotfiles to $PARENT_DIR"
echo ""

syncMirroredItems "$DOTFILES_DIR" "$PARENT_DIR"
renderExcludeFile "$PARENT_DIR/.git/info/exclude"
echo "  Released: $(basename "$EXCLUDE_MAP_FILE") → .git/info/exclude"
syncClaudeAliases
syncCodexPrompts

echo ""
echo "✓ Release operation complete"
