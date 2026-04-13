#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sync_common.sh
source "$SCRIPT_DIR/lib/sync_common.sh"

MANIFEST_PATH="$PARENT_DIR/.claude/$MANIFEST_FILENAME"

echo "Drift report (dotfiles ↔ deployed)"
echo ""

declare -A ManifestFiles=()
if ! readManifest "$MANIFEST_PATH" ManifestFiles; then
    echo "  No manifest found. Run release.sh first."
    exit 1
fi

# Collect dotfiles file names (no hashing — manifest serves as snapshot)
declare -A DotfilesNames=()
for rel_item in "${MIRRORED_ITEMS[@]}"; do
    if [ ! -e "$DOTFILES_DIR/$rel_item" ]; then
        continue
    fi
    while IFS= read -r rel_file; do
        [ -z "$rel_file" ] && continue
        if [ "$rel_file" = ".claude/$MANIFEST_FILENAME" ]; then
            continue
        fi
        DotfilesNames["$rel_file"]=1
    done < <(collectFiles "$DOTFILES_DIR" "$rel_item")
done

modified_locally=()
deleted_locally=()
in_sync=0

for rel_file in "${!ManifestFiles[@]}"; do
    manifest_hash="${ManifestFiles[$rel_file]}"
    deployed_path="$PARENT_DIR/$rel_file"

    if [ ! -f "$deployed_path" ]; then
        deleted_locally+=("$rel_file")
        continue
    fi

    current_hash="$(fileHash "$deployed_path")"
    if [ "$current_hash" != "$manifest_hash" ]; then
        modified_locally+=("$rel_file")
    else
        ((in_sync++)) || true
    fi
done

# Files in dotfiles but not in manifest
new_in_dotfiles=()
for rel_file in "${!DotfilesNames[@]}"; do
    if [ -z "${ManifestFiles[$rel_file]+x}" ]; then
        new_in_dotfiles+=("$rel_file")
    fi
done

# Unmanaged files in deployed .claude/
unmanaged=()
if [ -d "$PARENT_DIR/.claude" ]; then
    while IFS= read -r rel_file; do
        [ -z "$rel_file" ] && continue
        if [ "$rel_file" = ".claude/$MANIFEST_FILENAME" ]; then
            continue
        fi
        if [ -z "${ManifestFiles[$rel_file]+x}" ]; then
            unmanaged+=("$rel_file")
        fi
    done < <(collectFiles "$PARENT_DIR" ".claude")
fi

has_drift=false

print_category() {
    local label="$1"; shift
    (( $# == 0 )) && return
    has_drift=true
    for f; do printf '  %-22s%s\n' "$label" "$f"; done
}

print_category "modified locally:" "${modified_locally[@]+"${modified_locally[@]}"}"
print_category "deleted locally:" "${deleted_locally[@]+"${deleted_locally[@]}"}"
print_category "new in dotfiles:" "${new_in_dotfiles[@]+"${new_in_dotfiles[@]}"}"

if [ ${#unmanaged[@]} -gt 0 ]; then
    echo ""
    printf '  unmanaged (%d):\n' "${#unmanaged[@]}"
    for f in "${unmanaged[@]}"; do
        printf '    %s\n' "$f"
    done
fi

echo ""
if [ "$has_drift" = true ]; then
    printf '  ✓ %d files in sync, drift detected above\n' "$in_sync"
else
    printf '  ✓ %d files in sync, no drift\n' "$in_sync"
fi
