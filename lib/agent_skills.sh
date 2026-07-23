#!/bin/bash

# User-level agent skill publishing and repository-skill suppression.
# This file is sourced by lib/sync_common.sh.

AGENT_SKILLS_BEGIN_MARKER="# BEGIN DTVMDotfiles managed agent skills"
AGENT_SKILLS_END_MARKER="# END DTVMDotfiles managed agent skills"

agentSkillsActiveDir() {
    printf '%s' "${DTVMDOTFILES_ACTIVE_SKILLS_DIR:-$REPO_DIR/skills/active}"
}

agentSkillsMapFile() {
    printf '%s' "${DTVMDOTFILES_SKILLS_MAP_FILE:-$DOTFILES_DIR/skills.map.sh}"
}

agentSkillsCodexDir() {
    printf '%s' "${DTVMDOTFILES_CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
}

agentSkillsClaudeDir() {
    printf '%s' "${DTVMDOTFILES_CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
}

agentSkillsConfigFile() {
    printf '%s' "${DTVMDOTFILES_CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"
}

agentSkillsDeclaredName() {
    local skill_file="$1"
    awk '
        NR == 1 {
            if ($0 != "---") {
                exit 1
            }
            next
        }
        $0 == "---" {
            closed = 1
            exit
        }
        /^name:[[:space:]]*/ {
            if (found) {
                exit 1
            }
            sub(/^name:[[:space:]]*/, "")
            print
            found = 1
        }
        END {
            if (!found || !closed) {
                exit 1
            }
        }
    ' "$skill_file"
}

agentSkillsCollectActive() {
    local -n active_names_ref="$1"
    local active_dir skill_dir skill_name declared_name
    local nullglob_was_set=0

    active_names_ref=()
    active_dir="$(agentSkillsActiveDir)"
    if [[ "$active_dir" != /* ]]; then
        echo "Error: Active skills root must be an absolute path: $active_dir" >&2
        return 1
    fi
    if [ -L "$active_dir" ]; then
        echo "Error: Active skills root must not be a symlink: $active_dir" >&2
        return 1
    fi
    if [ ! -d "$active_dir" ]; then
        echo "Error: Active skills directory not found: $active_dir" >&2
        return 1
    fi

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob
    for skill_dir in "$active_dir"/*; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        if [ -L "$skill_dir" ]; then
            echo "Error: Active skill must be a directory in DTVMDotfiles, not a symlink: $skill_dir" >&2
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        fi
        if [[ ! "$skill_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
            echo "Error: Invalid active skill name: $skill_name" >&2
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        fi
        if [ ! -f "$skill_dir/SKILL.md" ]; then
            echo "Error: Active skill is missing SKILL.md: $skill_dir" >&2
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        fi
        if ! declared_name="$(agentSkillsDeclaredName "$skill_dir/SKILL.md")"; then
            echo "Error: Active skill has invalid frontmatter: $skill_dir/SKILL.md" >&2
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        fi
        if [ "$declared_name" != "$skill_name" ]; then
            echo "Error: Active skill directory and frontmatter name differ: $skill_name != $declared_name" >&2
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        fi
        active_names_ref+=("$skill_name")
    done
    [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
    if [ "${#active_names_ref[@]}" -gt 0 ]; then
        mapfile -t active_names_ref < <(printf '%s\n' "${active_names_ref[@]}" | LC_ALL=C sort)
    fi
}

agentSkillsCollectLegacy() {
    local -n legacy_names_ref="$1"
    local map_file key
    local -a names=()

    legacy_names_ref=()
    map_file="$(agentSkillsMapFile)"
    if [ ! -f "$map_file" ]; then
        echo "Error: Skill map not found: $map_file" >&2
        return 1
    fi

    unset DTVM_SKILLS_MAP
    # shellcheck source=/dev/null
    source "$map_file"
    if ! declare -p DTVM_SKILLS_MAP >/dev/null 2>&1; then
        echo "Error: $map_file must declare DTVM_SKILLS_MAP" >&2
        return 1
    fi

    for key in "${!DTVM_SKILLS_MAP[@]}"; do
        [ "${DTVM_SKILLS_MAP[$key]}" = "legacy-repo" ] || continue
        if [[ ! "$key" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
            echo "Error: Invalid legacy repository skill name: $key" >&2
            return 1
        fi
        names+=("$key")
    done
    if [ "${#names[@]}" -gt 0 ]; then
        mapfile -t legacy_names_ref < <(printf '%s\n' "${names[@]}" | LC_ALL=C sort)
    fi
}

agentSkillsCollectWorktrees() {
    local repo="$1"
    local -n worktrees_ref="$2"
    local field worktree

    worktrees_ref=()
    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: DTVM repository not found at $repo" >&2
        return 1
    fi
    if ! command -v iconv >/dev/null 2>&1; then
        echo "Error: iconv is required to validate Codex skill paths" >&2
        return 1
    fi

    while IFS= read -r -d '' field; do
        case "$field" in
            worktree\ *)
                worktree="${field#worktree }"
                if ! LC_ALL=C printf '%s' "$worktree" |
                    iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
                    printf 'Error: DTVM worktree path is not valid UTF-8: %q\n' \
                        "$worktree" >&2
                    return 1
                fi
                worktrees_ref+=("$worktree")
                ;;
        esac
    done < <(git -C "$repo" worktree list --porcelain -z)

    if [ "${#worktrees_ref[@]}" -eq 0 ]; then
        echo "Error: No DTVM worktrees discovered from $repo" >&2
        return 1
    fi
}

agentSkillsTomlEscape() {
    local value="$1"
    local result="" char escaped ordinal i

    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        case "$char" in
            \\) escaped='\\' ;;
            '"') escaped='\"' ;;
            $'\b') escaped='\b' ;;
            $'\t') escaped='\t' ;;
            $'\n') escaped='\n' ;;
            $'\f') escaped='\f' ;;
            $'\r') escaped='\r' ;;
            *)
                printf -v ordinal '%d' "'$char"
                if [ "$ordinal" -lt 32 ] || [ "$ordinal" -eq 127 ]; then
                    printf -v escaped '\\u%04X' "$ordinal"
                else
                    escaped="$char"
                fi
                ;;
        esac
        result+="$escaped"
    done
    printf '%s' "$result"
}

agentSkillsRequireSafePath() {
    local path="$1"
    local label="$2"
    local remaining component current=""

    if [[ "$path" != /* ]]; then
        echo "Error: $label must be an absolute path: $path" >&2
        return 1
    fi

    remaining="${path#/}"
    while [ -n "$remaining" ]; do
        if [[ "$remaining" == */* ]]; then
            component="${remaining%%/*}"
            remaining="${remaining#*/}"
        else
            component="$remaining"
            remaining=""
        fi
        [ -n "$component" ] || continue
        if [ "$component" = "." ] || [ "$component" = ".." ]; then
            echo "Error: $label contains a non-canonical component: $path" >&2
            return 1
        fi
        current="$current/$component"
        if [ -L "$current" ]; then
            echo "Error: $label contains a symlink component: $current" >&2
            return 1
        fi
    done
}

agentSkillsBuildBlock() {
    local repo="$1"
    local -a legacy_names=()
    local -a worktrees=()
    local worktree skill path

    agentSkillsCollectLegacy legacy_names || return 1
    agentSkillsCollectWorktrees "$repo" worktrees || return 1

    printf '%s\n' "$AGENT_SKILLS_BEGIN_MARKER"
    printf '%s\n' "# Generated by DTVMDotfiles; edit dotfiles/skills.map.sh, not this block."
    for worktree in "${worktrees[@]}"; do
        for skill in "${legacy_names[@]}"; do
            path="$worktree/.agents/skills/$skill/SKILL.md"
            printf '%s\n' '[[skills.config]]'
            printf 'path = "%s"\n' "$(agentSkillsTomlEscape "$path")"
            printf '%s\n' 'enabled = false'
        done
    done
    printf '%s\n' "$AGENT_SKILLS_END_MARKER"
}

agentSkillsConfigMarkers() {
    local config_file="$1"
    local -n begin_ref="$2"
    local -n end_ref="$3"
    local -a begins=()
    local -a ends=()

    begin_ref=0
    end_ref=0
    [ -e "$config_file" ] || return 0
    if [ -L "$config_file" ] || [ ! -f "$config_file" ]; then
        echo "Error: Codex config must be a regular, non-symlink file: $config_file" >&2
        return 1
    fi
    mapfile -t begins < <(grep -nFxe "$AGENT_SKILLS_BEGIN_MARKER" "$config_file" 2>/dev/null | cut -d: -f1)
    mapfile -t ends < <(grep -nFxe "$AGENT_SKILLS_END_MARKER" "$config_file" 2>/dev/null | cut -d: -f1)
    if [ "${#begins[@]}" -ne "${#ends[@]}" ] || [ "${#begins[@]}" -gt 1 ]; then
        echo "Error: Malformed DTVMDotfiles managed block in $config_file" >&2
        return 1
    fi
    if [ "${#begins[@]}" -eq 1 ]; then
        begin_ref="${begins[0]}"
        end_ref="${ends[0]}"
        if [ "$begin_ref" -ge "$end_ref" ]; then
            echo "Error: Malformed DTVMDotfiles managed block in $config_file" >&2
            return 1
        fi
    fi
}

agentSkillsIsManagedLink() {
    local link="$1"
    local target="$2"
    local active_dir skill_name
    active_dir="$(agentSkillsActiveDir)"
    skill_name="$(basename "$link")"
    [[ "$skill_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || return 1
    [ "$target" = "$active_dir/$skill_name" ]
}

agentSkillsPreflightRoot() {
    local root="$1"
    shift
    local skill source link target

    agentSkillsRequireSafePath "$root" "Agent skills destination" || return 1
    if [ -e "$root" ] && [ ! -d "$root" ]; then
        echo "Error: Agent skills destination is not a directory: $root" >&2
        return 1
    fi
    for skill in "$@"; do
        source="$(agentSkillsActiveDir)/$skill"
        link="$root/$skill"
        if [ -L "$link" ]; then
            target="$(readlink "$link")"
            if [ "$target" = "$source" ] &&
                agentSkillsIsManagedLink "$link" "$target"; then
                continue
            fi
            echo "Error: Foreign skill symlink collision: $link -> $target" >&2
            return 1
        fi
        if [ -e "$link" ]; then
            echo "Error: Foreign skill target collision: $link" >&2
            return 1
        fi
    done
}

agentSkillsPreflight() {
    local repo="${1:-$PARENT_DIR}"
    local -a active_names=()
    local -a legacy_names=()
    local -a worktrees=()
    local config_file config_dir begin_line end_line

    agentSkillsCollectActive active_names || return 1
    agentSkillsCollectLegacy legacy_names || return 1
    agentSkillsCollectWorktrees "$repo" worktrees || return 1
    agentSkillsPreflightRoot "$(agentSkillsCodexDir)" "${active_names[@]}" || return 1
    agentSkillsPreflightRoot "$(agentSkillsClaudeDir)" "${active_names[@]}" || return 1

    config_file="$(agentSkillsConfigFile)"
    config_dir="$(dirname "$config_file")"
    agentSkillsRequireSafePath "$config_file" "Codex config path" || return 1
    if [ -e "$config_dir" ] && [ ! -d "$config_dir" ]; then
        echo "Error: Codex config parent is not a directory: $config_dir" >&2
        return 1
    fi
    agentSkillsConfigMarkers "$config_file" begin_line end_line || return 1
}

agentSkillsSyncRoot() {
    local root="$1"
    shift
    local -a active_names=("$@")
    local active_dir skill source link target entry entry_target

    active_dir="$(agentSkillsActiveDir)"
    if [ ! -d "$root" ]; then
        if [ "${RELEASE_CHECK:-0}" = "1" ]; then
            echo "[release-dry] WOULD create $root"
        else
            mkdir -p "$root"
        fi
    fi

    for skill in "${active_names[@]}"; do
        source="$active_dir/$skill"
        link="$root/$skill"
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$source" ]; then
            continue
        fi
        if [ "${RELEASE_CHECK:-0}" = "1" ]; then
            echo "[release-dry] WOULD link $link → $source"
        else
            [ -L "$link" ] && rm -f "$link"
            ln -s "$source" "$link"
            echo "  Linked: $link → $source"
        fi
    done

    [ -d "$root" ] || return 0
    while IFS= read -r -d '' entry; do
        entry_target="$(readlink "$entry")"
        agentSkillsIsManagedLink "$entry" "$entry_target" || continue
        for skill in "${active_names[@]}"; do
            [ "$entry" = "$root/$skill" ] && continue 2
        done
        if [ "${RELEASE_CHECK:-0}" = "1" ]; then
            echo "[release-dry] WOULD remove stale managed link $entry"
        else
            rm -f "$entry"
            echo "  Removed stale skill link: $entry"
        fi
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type l -print0)
}

agentSkillsConfigMatches() {
    local repo="$1"
    local config_file begin_line end_line existing_block expected_block
    config_file="$(agentSkillsConfigFile)"
    [ -f "$config_file" ] && [ ! -L "$config_file" ] || return 1
    agentSkillsConfigMarkers "$config_file" begin_line end_line || return 2
    [ "$begin_line" -gt 0 ] || return 1
    [ "$(tail -n 1 "$config_file")" = "$AGENT_SKILLS_END_MARKER" ] || return 1
    existing_block="$(sed -n "${begin_line},${end_line}p" "$config_file")"
    expected_block="$(agentSkillsBuildBlock "$repo")" || return 2
    [ "$existing_block" = "$expected_block" ]
}

agentSkillsWriteConfig() {
    local repo="$1"
    local config_file config_dir begin_line end_line tmp_file last_char
    config_file="$(agentSkillsConfigFile)"
    config_dir="$(dirname "$config_file")"
    agentSkillsConfigMarkers "$config_file" begin_line end_line || return 1

    if agentSkillsConfigMatches "$repo"; then
        return 0
    fi
    if [ "${RELEASE_CHECK:-0}" = "1" ]; then
        echo "[release-dry] WOULD update managed block in $config_file"
        return 0
    fi

    mkdir -p "$config_dir"
    tmp_file="$(mktemp "$config_dir/.config.toml.dtvm.XXXXXX")"
    : > "$tmp_file"
    if [ "$begin_line" -gt 0 ]; then
        head -n "$((begin_line - 1))" "$config_file" >> "$tmp_file"
        tail -n "+$((end_line + 1))" "$config_file" >> "$tmp_file"
    elif [ -f "$config_file" ]; then
        cat "$config_file" >> "$tmp_file"
    fi
    if [ -s "$tmp_file" ]; then
        last_char="$(tail -c 1 "$tmp_file")"
        [ -z "$last_char" ] || printf '\n' >> "$tmp_file"
    fi
    agentSkillsBuildBlock "$repo" >> "$tmp_file"
    mv "$tmp_file" "$config_file"
    echo "  Updated: $config_file"
}

syncAgentSkills() {
    local repo="${1:-$PARENT_DIR}"
    local -a active_names=()

    agentSkillsPreflight "$repo" || return 1
    agentSkillsCollectActive active_names || return 1
    agentSkillsSyncRoot "$(agentSkillsCodexDir)" "${active_names[@]}"
    agentSkillsSyncRoot "$(agentSkillsClaudeDir)" "${active_names[@]}"
    agentSkillsWriteConfig "$repo"
}

checkAgentSkills() {
    local repo="${1:-$PARENT_DIR}"
    local -a active_names=()
    local root skill source entry entry_target drift=0

    agentSkillsPreflight "$repo" || return 1
    agentSkillsCollectActive active_names || return 1
    for root in "$(agentSkillsCodexDir)" "$(agentSkillsClaudeDir)"; do
        if [ ! -d "$root" ]; then
            echo "Drift: missing agent skills directory: $root" >&2
            drift=1
            continue
        fi
        for skill in "${active_names[@]}"; do
            source="$(agentSkillsActiveDir)/$skill"
            if [ ! -L "$root/$skill" ] || [ "$(readlink "$root/$skill" 2>/dev/null)" != "$source" ]; then
                echo "Drift: $root/$skill is not linked to $source" >&2
                drift=1
            fi
        done
        while IFS= read -r -d '' entry; do
            entry_target="$(readlink "$entry")"
            agentSkillsIsManagedLink "$entry" "$entry_target" || continue
            for skill in "${active_names[@]}"; do
                [ "$entry" = "$root/$skill" ] && continue 2
            done
            echo "Drift: stale managed skill link: $entry" >&2
            drift=1
        done < <(find "$root" -mindepth 1 -maxdepth 1 -type l -print0)
    done
    if ! agentSkillsConfigMatches "$repo"; then
        echo "Drift: Codex managed skill block is not current" >&2
        drift=1
    fi
    [ "$drift" -eq 0 ]
}
