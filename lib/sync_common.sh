#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
PARENT_DIR="${DTVMDOTFILES_PARENT_DIR:-$(dirname "$REPO_DIR")}"
EXCLUDE_MAP_FILE="$DOTFILES_DIR/exclude.map.sh"
MANIFEST_FILENAME=".dtvm-manifest.json"

requireBash43() {
    if [ -z "${BASH_VERSINFO:-}" ]; then
        echo "Error: Bash 4.3 or newer is required."
        exit 1
    fi

    if [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
        { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; then
        echo "Error: Bash 4.3 or newer is required. Current version: ${BASH_VERSION:-unknown}"
        exit 1
    fi
}

requireBash43

declare -agr MIRRORED_ITEMS=(
    ".claude"
    "init.sh"
    "CLAUDE.md"
    "perf/record_erc20_perf.sh"
    "perf/record_fibr_perf.sh"
    "perf/erc20.evm.hex"
    "perf/fib.evm.hex"
    "perf/fibr.evm.hex"
    ".agents/skills/worktree-bootstrap"
)

excludeHeader() {
    cat <<'EOF'
# git ls-files --others --exclude-from=.git/info/exclude
# Lines that start with '#' are comments.
# This file is generated from DTVMDotfiles/dotfiles/exclude.map.sh.

EOF
}

warn() {
    echo "Warning: $*"
}

# --- Manifest functions ---

fileHash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -c1-12
    else
        shasum -a 256 "$1" | cut -c1-12
    fi
}

# Machine-local files must never enter the manifest or the dotfiles tree.
isMachineLocalFile() {
    local name
    name="$(basename "$1")"
    case "$name" in
        settings.local.json | CLAUDE.local.md | *.local.md) return 0 ;;
    esac
    return 1
}

collectFiles() {
    local root="$1"
    local rel_path="$2"
    local full_path="$root/$rel_path"

    if [ -f "$full_path" ]; then
        isMachineLocalFile "$rel_path" && return 0
        printf '%s\n' "$rel_path"
    elif [ -d "$full_path" ]; then
        local f
        # BSD find lacks -printf; prefer gfind, else strip the root prefix in-shell.
        while IFS= read -r f; do
            f="${f#"$full_path"/}"
            isMachineLocalFile "$f" && continue
            printf '%s\n' "$rel_path/$f"
        done < <(collectFilesRaw "$full_path" | LC_ALL=C sort)
    fi
}

# List regular files under a directory, one absolute path per line.
# Prune non-managed subtrees: per-worktree checkouts (.claude/worktrees/),
# per-machine agent state (.claude/agent-memory/), and *.bak backups. These are
# never part of the managed dotfiles set and must not be enumerated into it.
# Uses GNU/gfind -printf when available, else a portable plain find.
collectFilesRaw() {
    local dir="$1"
    if command -v gfind >/dev/null 2>&1; then
        gfind "$dir" \( -type d \( -name worktrees -o -name agent-memory \) -prune \) \
            -o \( -type f ! -name '*.bak' -printf '%p\n' \)
    else
        find "$dir" \( -type d \( -name worktrees -o -name agent-memory \) -prune \) \
            -o \( -type f ! -name '*.bak' -print \)
    fi
}

writeManifest() {
    local manifest_path="$1"
    local -n wm_files_ref="$2"
    local tmp_file synced_at first=true

    if [ "${RELEASE_CHECK:-0}" = "1" ]; then
        echo "[release-dry] WOULD update manifest $manifest_path (${#wm_files_ref[@]} files)"
        return 0
    fi

    # date -Iseconds is GNU-only; BSD date needs an explicit ISO 8601 format.
    synced_at="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    tmp_file="$(mktemp)"
    {
        printf '{\n'
        printf '  "version": 1,\n'
        printf '  "synced_at": "%s",\n' "$synced_at"
        printf '  "files": {\n'
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            if [ "$first" = true ]; then
                first=false
            else
                printf ',\n'
            fi
            printf '    "%s": "%s"' "$key" "${wm_files_ref[$key]}"
        done < <(printf '%s\n' "${!wm_files_ref[@]}" | LC_ALL=C sort)
        printf '\n  }\n'
        printf '}\n'
    } > "$tmp_file"
    mv "$tmp_file" "$manifest_path"
}

readManifest() {
    local manifest_path="$1"
    local -n rm_files_ref="$2"
    rm_files_ref=()

    if [ ! -f "$manifest_path" ]; then
        return 1
    fi

    local in_files=false line
    while IFS= read -r line; do
        if [[ "$line" == *'"files"'* ]]; then
            in_files=true
            continue
        fi
        if [ "$in_files" = true ]; then
            if [[ "$line" == *'}'* ]] && [[ "$line" != *':'* ]]; then
                break
            fi
            if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                rm_files_ref["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi
        fi
    done < "$manifest_path"
}

copy_with_gate() {
    local src="$1" dst="$2" old_hash="${3:-}"
    local need_backup=0
    if [ -f "$dst" ] && [ -n "$old_hash" ]; then
        local current_hash
        current_hash="$(fileHash "$dst")"
        if [ "$current_hash" != "$old_hash" ]; then
            if [ "${RELEASE_FORCE:-0}" != "1" ]; then
                echo "[release] ABORT: $dst was modified locally" >&2
                echo "  expected hash $old_hash (from OldManifest)" >&2
                echo "  actual hash   $current_hash" >&2
                echo "  Fix: bash DTVMDotfiles/store.sh   # then retry release.sh" >&2
                echo "  Or:  RELEASE_FORCE=1 bash DTVMDotfiles/release.sh   # overwrite" >&2
                return 1
            fi
            echo "[release] WARN: overwriting locally-modified $dst" >&2
        fi
    elif [ -f "$dst" ] && [ "$(fileHash "$dst")" != "$(fileHash "$src")" ]; then
        # No manifest entry (first deploy): dst is hand-edited and git-unrecoverable.
        # Back it up before overwriting rather than destroying it silently.
        need_backup=1
    fi
    if [ "${RELEASE_CHECK:-0}" = "1" ]; then
        echo "[release-dry] WOULD copy $src → $dst"
        if [ "$need_backup" = "1" ]; then
            echo "[release-dry] WOULD back up $dst → $dst.pre-release.bak"
        fi
        return 0
    fi
    if [ "$need_backup" = "1" ]; then
        echo "[release] NOTICE: backing up un-tracked local edits: $dst → $dst.pre-release.bak" >&2
        cp -f "$dst" "$dst.pre-release.bak"
    fi
    cp -f "$src" "$dst"
}

syncMirroredItemsWithManifest() {
    local src_root="$1"
    local dst_root="$2"
    local -n smiwm_out_ref="$3"
    local -n smiwm_old_ref="$4"
    local rel_item files rel_file

    smiwm_out_ref=()

    for rel_item in "${MIRRORED_ITEMS[@]}"; do
        if [ ! -e "$src_root/$rel_item" ]; then
            warn "Source not found: $src_root/$rel_item"
            continue
        fi

        files="$(collectFiles "$src_root" "$rel_item")"
        while IFS= read -r rel_file; do
            [ -z "$rel_file" ] && continue
            if [ "$rel_file" = ".claude/$MANIFEST_FILENAME" ]; then
                continue
            fi
            mkdir -p "$(dirname "$dst_root/$rel_file")"
            copy_with_gate "$src_root/$rel_file" "$dst_root/$rel_file" "${smiwm_old_ref[$rel_file]:-}" || return 1
            # Under RELEASE_CHECK=1 copy_with_gate skips the cp; dst may not exist.
            if [ -f "$dst_root/$rel_file" ]; then
                smiwm_out_ref["$rel_file"]="$(fileHash "$dst_root/$rel_file")"
            fi
        done <<< "$files"

        echo "  Synced: $rel_item"
    done
}

cleanRemovedFiles() {
    local dst_root="$1"
    local -n crf_old_ref="$2"
    local -n crf_new_ref="$3"
    local old_file target

    for old_file in "${!crf_old_ref[@]}"; do
        # Never delete machine-local files: collectFiles filters them out of
        # NewManifest, so their absence there must not trigger a live deletion.
        isMachineLocalFile "$old_file" && continue
        if [ -z "${crf_new_ref[$old_file]+x}" ]; then
            target="$dst_root/$old_file"
            if [ -f "$target" ]; then
                if [ "${RELEASE_CHECK:-0}" = "1" ]; then
                    echo "[release-dry] WOULD remove $old_file"
                else
                    rm -f "$target"
                    echo "  Removed: $old_file"
                fi
            fi
        fi
    done
}

storeMirroredItemsFromManifest() {
    local src_root="$1"
    local dst_root="$2"
    local manifest_path="$src_root/.claude/$MANIFEST_FILENAME"
    local -A sm_manifest_files=()
    local -A sm_synced_items=()
    local rel_file item rel_item

    if ! readManifest "$manifest_path" sm_manifest_files; then
        echo "Error: No manifest found at $manifest_path"
        echo "Run release.sh first to generate one."
        exit 1
    fi

    # Manifest-bounded copy: the manifest IS the curation boundary (see
    # dtvm-dotfiles-usage.md "store.sh only collects files listed in the
    # manifest"). Only already-tracked files are collected into the SSOT;
    # unmanaged live files are reported below but never swept in.
    for rel_file in "${!sm_manifest_files[@]}"; do
        isMachineLocalFile "$rel_file" && continue
        if [ ! -f "$src_root/$rel_file" ]; then
            warn "Manifest file missing: $rel_file"
            continue
        fi
        mkdir -p "$(dirname "$dst_root/$rel_file")"
        cp -f "$src_root/$rel_file" "$dst_root/$rel_file"

        for item in "${MIRRORED_ITEMS[@]}"; do
            if [[ "$rel_file" == "$item" ]] || [[ "$rel_file" == "$item/"* ]]; then
                sm_synced_items["$item"]=1
                break
            fi
        done
    done

    # Non-destructive drift signal: warn about live files under a managed
    # directory that are not yet in the manifest (add them via release.sh).
    # collectFiles prunes worktrees/, agent-memory/, *.bak and machine-local
    # files, so this never floods on per-worktree checkouts or agent state.
    for rel_item in "${MIRRORED_ITEMS[@]}"; do
        [ -d "$src_root/$rel_item" ] || continue
        while IFS= read -r rel_file; do
            [ -z "$rel_file" ] && continue
            [ "$rel_file" = ".claude/$MANIFEST_FILENAME" ] && continue
            if [ -z "${sm_manifest_files[$rel_file]+x}" ]; then
                warn "Unmanaged file under managed dir (run release.sh to track): $rel_file"
            fi
        done < <(collectFiles "$src_root" "$rel_item")
    done

    while IFS= read -r item; do
        [ -z "$item" ] && continue
        echo "  Synced: $item"
    done < <(printf '%s\n' "${!sm_synced_items[@]}" | LC_ALL=C sort)
}

# --- Supplemental sync ---

syncClaudeAliases() {
    local src="$DOTFILES_DIR/CLAUDE.md"

    if [ ! -f "$src" ]; then
        warn "Source not found: $src"
        return
    fi

    cp -f "$src" "$PARENT_DIR/AGENTS.md"
    echo "  Synced: CLAUDE.md → AGENTS.md"

    cp -f "$src" "$PARENT_DIR/GEMINI.md"
    echo "  Synced: CLAUDE.md → GEMINI.md"
}

syncCodexPrompts() {
    local claude_commands_dir="$DOTFILES_DIR/.claude/commands"
    local codex_prompts_dir="${DTVMDOTFILES_CODEX_PROMPTS_DIR:-$HOME/.codex/prompts}"

    if [ ! -d "$claude_commands_dir" ]; then
        warn ".claude/commands not found in $claude_commands_dir"
        return
    fi

    echo "  Synced: .claude/commands → $codex_prompts_dir"
    mkdir -p "$codex_prompts_dir"
    # File-level overwrite preserves user-added prompts not present in
    # claude_commands_dir. Tradeoff: deletes-in-source no longer prune destination.
    for f in "$claude_commands_dir"/*.md; do
        [ -f "$f" ] || continue
        cp -f "$f" "$codex_prompts_dir/$(basename "$f")"
    done
}

# --- Exclude map functions ---

isLiteralExcludePattern() {
    local pattern="$1"

    [[ "$pattern" != '!'* ]] &&
        [[ "$pattern" != *'*'* ]] &&
        [[ "$pattern" != *'?'* ]] &&
        [[ "$pattern" != *'['* ]]
}

excludePatternPathPart() {
    local pattern="$1"

    if [[ "$pattern" == */ ]] && [[ "$pattern" != "/" ]]; then
        printf '%s' "${pattern%/}"
        return
    fi

    printf '%s' "$pattern"
}

isDirectoryOnlyExcludePattern() {
    local pattern="$1"

    [[ "$pattern" == */ ]] && [[ "$pattern" != "/" ]]
}

isCoveredExcludePattern() {
    local parent_pattern="$1"
    local child_pattern="$2"
    local parent_path
    local child_path

    parent_path="$(excludePatternPathPart "$parent_pattern")"
    child_path="$(excludePatternPathPart "$child_pattern")"

    if [[ "$child_path" == "$parent_path/"* ]]; then
        return 0
    fi

    if ! isDirectoryOnlyExcludePattern "$parent_pattern" &&
        isDirectoryOnlyExcludePattern "$child_pattern" &&
        [ "$parent_path" = "$child_path" ]; then
        return 0
    fi

    return 1
}

compactExcludeMap() {
    local -n map_ref="$1"
    local pattern
    local other_pattern

    for pattern in "${!map_ref[@]}"; do
        if ! isLiteralExcludePattern "$pattern"; then
            continue
        fi

        for other_pattern in "${!map_ref[@]}"; do
            if [ "$pattern" = "$other_pattern" ]; then
                continue
            fi

            if ! isLiteralExcludePattern "$other_pattern"; then
                continue
            fi

            if isCoveredExcludePattern "$other_pattern" "$pattern"; then
                unset 'map_ref[$pattern]'
                break
            fi
        done
    done
}

buildExcludeMapFromFile() {
    local exclude_file="$1"
    local map_name="$2"
    local -n map_ref="$map_name"
    local line
    local pattern

    map_ref=()

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"

        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi

        pattern="$line"
        map_ref["$pattern"]="managed"
    done < "$exclude_file"

    compactExcludeMap "$map_name"
}

writeMapFile() {
    local file_path="$1"
    local var_name="$2"
    local description="$3"
    local -n map_ref="$4"
    local tmp_file

    tmp_file="$(mktemp)"
    {
        printf '%s\n\n' '#!/usr/bin/env bash'
        printf '%s\n' "$description"
        printf 'declare -Ag %s=(\n' "$var_name"
        if [ "${#map_ref[@]}" -gt 0 ]; then
            while IFS= read -r key; do
                printf '    [%q]=%q\n' "$key" "${map_ref[$key]}"
            done < <(printf '%s\n' "${!map_ref[@]}" | LC_ALL=C sort)
        fi
        printf ')\n'
    } > "$tmp_file"

    mv "$tmp_file" "$file_path"
}

loadExcludeMap() {
    declare -gA DTVM_EXCLUDE_MAP=()

    if [ -f "$EXCLUDE_MAP_FILE" ]; then
        # shellcheck source=/dev/null
        source "$EXCLUDE_MAP_FILE"
    fi
}

renderExcludeFile() {
    local dst_path="$1"
    local tmp_file
    local pattern
    local -A render_map=()

    loadExcludeMap

    for pattern in "${!DTVM_EXCLUDE_MAP[@]}"; do
        render_map["$pattern"]="${DTVM_EXCLUDE_MAP[$pattern]}"
    done

    tmp_file="$(mktemp)"
    {
        excludeHeader
        if [ "${#render_map[@]}" -gt 0 ]; then
            while IFS= read -r pattern; do
                [ -n "$pattern" ] && printf '%s\n' "$pattern"
            done < <(printf '%s\n' "${!render_map[@]}" | LC_ALL=C sort)
        fi
    } > "$tmp_file"

    mkdir -p "$(dirname "$dst_path")"
    mv "$tmp_file" "$dst_path"
}
