#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
PARENT_DIR="${DTVMDOTFILES_PARENT_DIR:-$(dirname "$REPO_DIR")}"
EXCLUDE_MAP_FILE="$DOTFILES_DIR/exclude.map.sh"
SKILLS_MAP_FILE="$DOTFILES_DIR/skills.map.sh"

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
    "openspec"
    "perf/record_erc20_perf.sh"
    "perf/record_fibr_perf.sh"
    "perf/erc20.evm.hex"
    "perf/fib.evm.hex"
    "perf/fibr.evm.hex"
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

copyPath() {
    local src_path="$1"
    local dst_path="$2"
    local dst_dir

    if [ ! -e "$src_path" ]; then
        warn "Source not found: $src_path"
        return 1
    fi

    dst_dir="$(dirname "$dst_path")"
    mkdir -p "$dst_dir"

    if [ -d "$src_path" ]; then
        rm -rf "$dst_path"
        cp -r "$src_path" "$dst_path"
    else
        cp -f "$src_path" "$dst_path"
    fi
}

syncMirroredItems() {
    local src_root="$1"
    local dst_root="$2"
    local rel_path

    for rel_path in "${MIRRORED_ITEMS[@]}"; do
        if copyPath "$src_root/$rel_path" "$dst_root/$rel_path"; then
            echo "  Synced: $rel_path"
        fi
    done
}

syncClaudeAliases() {
    local claude_path="$DOTFILES_DIR/CLAUDE.md"

    if copyPath "$claude_path" "$PARENT_DIR/AGENTS.md"; then
        echo "  Synced: CLAUDE.md → AGENTS.md"
    fi

    if copyPath "$claude_path" "$PARENT_DIR/GEMINI.md"; then
        echo "  Synced: CLAUDE.md → GEMINI.md"
    fi
}

syncCodexPrompts() {
    local claude_commands_dir="$DOTFILES_DIR/.claude/commands"
    local codex_prompts_dir="${DTVMDOTFILES_CODEX_PROMPTS_DIR:-$HOME/.codex/prompts}"

    if [ ! -d "$claude_commands_dir" ]; then
        warn ".claude/commands not found in $claude_commands_dir"
        return
    fi

    echo "  Synced: .claude/commands → $codex_prompts_dir"
    mkdir -p "$(dirname "$codex_prompts_dir")"
    rm -rf "$codex_prompts_dir"
    cp -r "$claude_commands_dir" "$codex_prompts_dir"
}

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

    loadExcludeMap

    tmp_file="$(mktemp)"
    {
        excludeHeader
        if [ "${#DTVM_EXCLUDE_MAP[@]}" -gt 0 ]; then
            while IFS= read -r pattern; do
                [ -n "$pattern" ] && printf '%s\n' "$pattern"
            done < <(printf '%s\n' "${!DTVM_EXCLUDE_MAP[@]}" | LC_ALL=C sort)
        fi
    } > "$tmp_file"

    mkdir -p "$(dirname "$dst_path")"
    mv "$tmp_file" "$dst_path"
}

loadSkillsMap() {
    declare -gA DTVM_SKILLS_MAP=()

    if [ -f "$SKILLS_MAP_FILE" ]; then
        # shellcheck source=/dev/null
        source "$SKILLS_MAP_FILE"
    fi
}

managedSkillNames() {
    local skill_name

    loadSkillsMap
    if [ "${#DTVM_SKILLS_MAP[@]}" -eq 0 ]; then
        return
    fi

    while IFS= read -r skill_name; do
        [ "${DTVM_SKILLS_MAP[$skill_name]}" = "managed" ] && printf '%s\n' "$skill_name"
    done < <(printf '%s\n' "${!DTVM_SKILLS_MAP[@]}" | LC_ALL=C sort)
}

storeManagedSkills() {
    local parent_skills_dir="$PARENT_DIR/.agents/skills"
    local dotfiles_skills_dir="$DOTFILES_DIR/.agents/skills"
    local temp_skills_dir
    local skill_name
    local skipped_skills=()

    loadSkillsMap
    temp_skills_dir="$(mktemp -d)"

    while IFS= read -r skill_name; do
        if [ -e "$parent_skills_dir/$skill_name" ]; then
            copyPath "$parent_skills_dir/$skill_name" "$temp_skills_dir/$skill_name"
            echo "  Stored managed skill: $skill_name"
            continue
        fi

        if [ -e "$dotfiles_skills_dir/$skill_name" ]; then
            copyPath "$dotfiles_skills_dir/$skill_name" "$temp_skills_dir/$skill_name"
            warn "Managed skill missing in parent, kept existing dotfiles copy: $skill_name"
            continue
        fi

        warn "Managed skill not found in parent or dotfiles: $skill_name"
    done < <(managedSkillNames)

    rm -rf "$dotfiles_skills_dir"
    mkdir -p "$(dirname "$dotfiles_skills_dir")"
    mv "$temp_skills_dir" "$dotfiles_skills_dir"

    if [ -d "$parent_skills_dir" ]; then
        while IFS= read -r skill_name; do
            if [ "${DTVM_SKILLS_MAP[$skill_name]:-unmanaged}" != "managed" ]; then
                skipped_skills+=("$skill_name")
            fi
        done < <(find "$parent_skills_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)
    fi

    if [ "${#skipped_skills[@]}" -gt 0 ]; then
        echo "  Skipped unmanaged skills: ${skipped_skills[*]}"
    fi
}

releaseManagedSkills() {
    local parent_skills_dir="$PARENT_DIR/.agents/skills"
    local dotfiles_skills_dir="$DOTFILES_DIR/.agents/skills"
    local skill_name

    mkdir -p "$parent_skills_dir"

    while IFS= read -r skill_name; do
        if copyPath "$dotfiles_skills_dir/$skill_name" "$parent_skills_dir/$skill_name"; then
            echo "  Released managed skill: $skill_name"
        fi
    done < <(managedSkillNames)
}
