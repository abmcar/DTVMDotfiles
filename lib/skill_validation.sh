#!/bin/bash

# Read-only validation for active DTVMDotfiles skills.

skillValidationActiveDir() {
    local active_dir
    active_dir="${DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR:-${DTVMDOTFILES_ACTIVE_SKILLS_DIR:-$REPO_DIR/skills/active}}"
    printf '%s' "$active_dir"
}

skillValidationHooksDir() {
    local active_dir
    active_dir="$(skillValidationActiveDir)"
    printf '%s' \
        "${DTVMDOTFILES_SKILL_VALIDATION_HOOKS_DIR:-$(dirname "$active_dir")/validation-hooks}"
}

skillValidationHookRegistry() {
    printf '%s' \
        "${DTVMDOTFILES_SKILL_VALIDATION_HOOK_REGISTRY:-$(skillValidationHooksDir)/registry.txt}"
}

skillValidationTestRegistry() {
    printf '%s' \
        "${DTVMDOTFILES_SKILL_TEST_REGISTRY:-$REPO_DIR/tests/skill-test-registry.txt}"
}

skillValidationTool() {
    printf '%s' "${DTVMDOTFILES_QUICK_VALIDATE:-$REPO_DIR/tools/quick_validate.py}"
}

skillValidationCopyRepo() {
    local destination="$1"
    local entry

    mkdir -p "$destination"
    while IFS= read -r -d '' entry; do
        cp -a "$entry" "$destination/"
    done < <(
        find "$REPO_DIR" -mindepth 1 -maxdepth 1 ! -name .git -print0
    )
}

skillValidationGitState() {
    local git_root

    git_root="$(
        GIT_OPTIONAL_LOCKS=0 git -C "$REPO_DIR" rev-parse --show-toplevel \
            2>/dev/null
    )" || {
        printf '%s' "<no-git-worktree>"
        return 0
    }
    if [ "$(realpath -m -- "$git_root")" != "$(realpath -m -- "$REPO_DIR")" ]; then
        printf '%s' "<no-git-worktree>"
        return 0
    fi
    GIT_OPTIONAL_LOCKS=0 git -C "$REPO_DIR" status \
        --porcelain=v1 --untracked-files=all
}

skillValidationRunHook() {
    local hook="$1"
    local skill_dir="$2"
    local before_repo after_repo before_skill after_skill before_git after_git
    local before_copy_repo after_copy_repo before_copy_skill after_copy_skill
    local temp_root repo_copy hook_copy skill_copy rc=0

    before_repo="$(python3 "$(skillValidationTool)" "$REPO_DIR" --fingerprint)" ||
        return 1
    before_skill="$(python3 "$(skillValidationTool)" "$skill_dir" --fingerprint)" ||
        return 1
    before_git="$(skillValidationGitState)" || return 1
    temp_root="$(mktemp -d)"
    repo_copy="$temp_root/repo"
    mkdir -p "$temp_root/home" "$temp_root/cache" "$repo_copy"
    skillValidationCopyRepo "$repo_copy"

    case "$hook" in
        "$REPO_DIR"/*) hook_copy="$repo_copy/${hook#"$REPO_DIR"/}" ;;
        *)
            hook_copy="$repo_copy/.skill-validation-hook.sh"
            cp -a "$hook" "$hook_copy"
            ;;
    esac
    case "$skill_dir" in
        "$REPO_DIR"/*) skill_copy="$repo_copy/${skill_dir#"$REPO_DIR"/}" ;;
        *)
            skill_copy="$repo_copy/.skill-validation-source"
            mkdir -p "$skill_copy"
            cp -a "$skill_dir/." "$skill_copy/"
            ;;
    esac
    before_copy_repo="$(
        python3 "$(skillValidationTool)" "$repo_copy" --fingerprint
    )" || rc=1
    before_copy_skill="$(
        python3 "$(skillValidationTool)" "$skill_copy" --fingerprint
    )" || rc=1
    (
        cd "$repo_copy"
        env \
            HOME="$temp_root/home" \
            TMPDIR="$temp_root" \
            XDG_CACHE_HOME="$temp_root/cache" \
            PYTHONDONTWRITEBYTECODE=1 \
            bash "$hook_copy" "$skill_copy"
    ) || rc=$?
    after_copy_repo="$(
        python3 "$(skillValidationTool)" "$repo_copy" --fingerprint
    )" || rc=1
    after_copy_skill="$(
        python3 "$(skillValidationTool)" "$skill_copy" --fingerprint
    )" || rc=1
    after_repo="$(python3 "$(skillValidationTool)" "$REPO_DIR" --fingerprint)" || rc=1
    after_skill="$(python3 "$(skillValidationTool)" "$skill_dir" --fingerprint)" || rc=1
    after_git="$(skillValidationGitState)" || rc=1
    rm -rf "$temp_root"

    if [ "$before_copy_repo" != "$after_copy_repo" ] ||
        [ "$before_copy_skill" != "$after_copy_skill" ] ||
        [ "$before_repo" != "$after_repo" ] ||
        [ "$before_skill" != "$after_skill" ] ||
        [ "$before_git" != "$after_git" ]; then
        echo "Error: Skill validation hook modified source state: $hook" >&2
        return 1
    fi
    return "$rc"
}

runRepoSkillTests() {
    local registry validator test_path test_copy
    local before_repo after_repo before_git after_git
    local before_copy after_copy
    local temp_root repo_copy started elapsed rc=0
    local -a registered_tests=()
    local -A seen_tests=()

    registry="$(skillValidationTestRegistry)"
    validator="$(skillValidationTool)"
    if [ ! -f "$registry" ] || [ -L "$registry" ]; then
        echo "Error: Skill test registry not found or is a symlink: $registry" >&2
        return 1
    fi
    while IFS= read -r test_path || [ -n "$test_path" ]; do
        case "$test_path" in
            ""|\#*) continue ;;
        esac
        if [[ ! "$test_path" =~ ^tests/[a-z0-9]+([_-][a-z0-9]+)*\.sh$ ]]; then
            echo "Error: Invalid skill test registry entry: $test_path" >&2
            return 1
        fi
        if [ -n "${seen_tests["$test_path"]+present}" ]; then
            echo "Error: Duplicate skill test registry entry: $test_path" >&2
            return 1
        fi
        test_copy="$REPO_DIR/$test_path"
        if [ ! -f "$test_copy" ] || [ -L "$test_copy" ] || [ ! -x "$test_copy" ]; then
            echo "Error: Registered skill test must be an executable regular file: $test_path" >&2
            return 1
        fi
        bash -n "$test_copy" || return 1
        seen_tests["$test_path"]=1
        registered_tests+=("$test_path")
    done < "$registry"
    if [ "${#registered_tests[@]}" -eq 0 ]; then
        echo "Error: Skill test registry is empty: $registry" >&2
        return 1
    fi

    before_repo="$(python3 "$validator" "$REPO_DIR" --fingerprint)" ||
        return 1
    before_git="$(skillValidationGitState)" || return 1
    temp_root="$(mktemp -d)"
    repo_copy="$temp_root/repo"
    mkdir -p "$temp_root/home" "$temp_root/cache"
    skillValidationCopyRepo "$repo_copy"
    before_copy="$(python3 "$validator" "$repo_copy" --fingerprint)" || rc=1

    for test_path in "${registered_tests[@]}"; do
        started="$SECONDS"
        (
            cd "$repo_copy"
            env \
                HOME="$temp_root/home" \
                TMPDIR="$temp_root" \
                XDG_CACHE_HOME="$temp_root/cache" \
                PYTHONDONTWRITEBYTECODE=1 \
                DTVMDOTFILES_REPO_SKILL_TEST_CHILD=1 \
                DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR="$repo_copy/skills/active" \
                bash "$repo_copy/$test_path"
        ) || {
            rc=$?
            break
        }
        elapsed=$((SECONDS - started))
        echo "PASS: registered skill test $test_path (${elapsed}s)"
    done

    after_copy="$(python3 "$validator" "$repo_copy" --fingerprint)" || rc=1
    after_repo="$(python3 "$validator" "$REPO_DIR" --fingerprint)" || rc=1
    after_git="$(skillValidationGitState)" || rc=1
    rm -rf "$temp_root"

    if [ "$before_copy" != "$after_copy" ] ||
        [ "$before_repo" != "$after_repo" ] ||
        [ "$before_git" != "$after_git" ]; then
        echo "Error: Registered skill test modified source state" >&2
        return 1
    fi
    return "$rc"
}

validateSkillPublishingGate() {
    validateActiveSkills || return 1
    if [ "${DTVMDOTFILES_REPO_SKILL_TEST_CHILD:-0}" = "1" ]; then
        return 0
    fi
    runRepoSkillTests
}

validateActiveSkills() {
    local active_dir hooks_dir registry validator skill_dir skill_name hook
    local registered_name
    local nullglob_was_set=0
    local has_scripts
    local -A registered_hooks=()

    active_dir="$(skillValidationActiveDir)"
    hooks_dir="$(skillValidationHooksDir)"
    registry="$(skillValidationHookRegistry)"
    validator="$(skillValidationTool)"
    if [[ "$active_dir" != /* ]] || [ ! -d "$active_dir" ] || [ -L "$active_dir" ]; then
        echo "Error: Active skills root must be an absolute regular directory: $active_dir" >&2
        return 1
    fi
    if [ ! -f "$validator" ] || [ -L "$validator" ]; then
        echo "Error: Skill validator not found or is a symlink: $validator" >&2
        return 1
    fi
    if [ -e "$hooks_dir" ] && { [ ! -d "$hooks_dir" ] || [ -L "$hooks_dir" ]; }; then
        echo "Error: Skill validation hooks root must be a regular directory: $hooks_dir" >&2
        return 1
    fi
    if [ ! -f "$registry" ] || [ -L "$registry" ]; then
        echo "Error: Skill validation hook registry not found or is a symlink: $registry" >&2
        return 1
    fi

    while IFS= read -r registered_name || [ -n "$registered_name" ]; do
        case "$registered_name" in
            ""|\#*) continue ;;
        esac
        if [[ ! "$registered_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
            echo "Error: Invalid skill validation hook registry entry: $registered_name" >&2
            return 1
        fi
        if [ -n "${registered_hooks["$registered_name"]+present}" ]; then
            echo "Error: Duplicate skill validation hook registry entry: $registered_name" >&2
            return 1
        fi
        hook="$hooks_dir/$registered_name.sh"
        if [ ! -f "$hook" ] || [ -L "$hook" ] || [ ! -x "$hook" ]; then
            echo "Error: Registered skill validation hook must be an executable regular file: $hook" >&2
            return 1
        fi
        bash -n "$hook" || return 1
        registered_hooks["$registered_name"]=1
    done < "$registry"

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob
    for skill_dir in "$active_dir"/*; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        python3 "$validator" --require-openai-yaml "$skill_dir" || {
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        }

        hook="$hooks_dir/$skill_name.sh"
        has_scripts=0
        if [ -d "$skill_dir/scripts" ] &&
            find "$skill_dir/scripts" -type f -print -quit | grep -q .; then
            has_scripts=1
        fi
        if [ "$has_scripts" -eq 1 ] && [ ! -f "$hook" ]; then
            echo "Error: Script-bearing active skill needs a deterministic hook: $hook" >&2
            [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
            return 1
        fi
        if [ -e "$hook" ]; then
            if [ -z "${registered_hooks["$skill_name"]+present}" ]; then
                echo "Error: Active skill validation hook is not registered: $hook" >&2
                [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
                return 1
            fi
            if [ "${DTVMDOTFILES_REPO_SKILL_TEST_CHILD:-0}" != "1" ]; then
                echo "Running validation hook: $skill_name"
                skillValidationRunHook "$hook" "$skill_dir" || {
                    [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
                    return 1
                }
            fi
        fi
    done

    if [ -d "$hooks_dir" ]; then
        for hook in "$hooks_dir"/*.sh; do
            skill_name="$(basename "$hook" .sh)"
            if [ -z "${registered_hooks["$skill_name"]+present}" ]; then
                echo "Error: Unregistered skill validation hook: $hook" >&2
                [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
                return 1
            fi
        done
    fi
    [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
}
