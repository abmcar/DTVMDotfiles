#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sync_common.sh
source "$SCRIPT_DIR/lib/sync_common.sh"

if [ ! -d "$PARENT_DIR" ]; then
    echo "Error: Parent DTVM directory not found at $PARENT_DIR"
    exit 1
fi

MANIFEST_PATH="$PARENT_DIR/.claude/$MANIFEST_FILENAME"

echo "Release script - Releasing files from DTVMDotfiles to $PARENT_DIR"
echo ""

declare -A OldManifest=()
readManifest "$MANIFEST_PATH" OldManifest 2>/dev/null || true

declare -A NewManifest=()
syncMirroredItemsWithManifest "$DOTFILES_DIR" "$PARENT_DIR" NewManifest

if [ "${#OldManifest[@]}" -gt 0 ]; then
    cleanRemovedFiles "$PARENT_DIR" OldManifest NewManifest
fi

writeManifest "$MANIFEST_PATH" NewManifest
echo "  Generated: .claude/$MANIFEST_FILENAME (${#NewManifest[@]} files)"

renderExcludeFile "$PARENT_DIR/.git/info/exclude"
echo "  Released: $(basename "$EXCLUDE_MAP_FILE") → .git/info/exclude"
syncClaudeAliases
syncCodexPrompts

echo ""
echo "✓ Release operation complete"
