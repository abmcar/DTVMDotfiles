#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
VALIDATOR="$REPO_DIR/tools/quick_validate.py"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

write_valid_skill() {
    local root="$1"
    local name="$2"
    mkdir -p "$root/$name/agents" "$root/$name/references"
    printf '%s\n' \
        '---' \
        "name: $name" \
        'description: Validate a deterministic fixture when testing skill publication.' \
        '---' \
        '' \
        '# Fixture Skill' \
        '' \
        'Read [the fixture](references/fixture.md).' \
        > "$root/$name/SKILL.md"
    printf '%s\n' fixture > "$root/$name/references/fixture.md"
    {
        printf '%s\n' \
            'interface:' \
            '  display_name: "Fixture Skill"' \
            '  short_description: "Validate a deterministic fixture"'
        printf '  default_prompt: "Use $%s to validate this fixture."\n' "$name"
    } > "$root/$name/agents/openai.yaml"
}

assert_invalid() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$label unexpectedly passed"
    fi
}

ACTIVE_ROOT="$TEST_TMP/skills/active"
HOOKS_ROOT="$TEST_TMP/skills/validation-hooks"
mkdir -p "$ACTIVE_ROOT" "$HOOKS_ROOT"
write_valid_skill "$ACTIVE_ROOT" valid-skill
python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/valid-skill" >/dev/null

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/bad-yaml"
printf '%s\n' \
    '---' \
    'name: bad-yaml' \
    'description: first' \
    'description: duplicate' \
    '---' \
    '# Bad YAML' \
    > "$ACTIVE_ROOT/bad-yaml/SKILL.md"
assert_invalid duplicate-yaml \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/bad-yaml"

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/empty-description"
sed -i \
    -e 's/name: valid-skill/name: empty-description/' \
    -e 's/description: Validate.*/description: ""/' \
    "$ACTIVE_ROOT/empty-description/SKILL.md"
sed -i \
    's/\\$valid-skill/\\$empty-description/' \
    "$ACTIVE_ROOT/empty-description/agents/openai.yaml"
grep -Fqx 'description: ""' "$ACTIVE_ROOT/empty-description/SKILL.md" ||
    fail "empty-description fixture was not created"
assert_invalid empty-description \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/empty-description"

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/empty-body"
printf '%s\n' \
    '---' \
    'name: empty-body' \
    'description: Validate an intentionally empty instruction body.' \
    '---' \
    > "$ACTIVE_ROOT/empty-body/SKILL.md"
sed -i 's/\\$valid-skill/\\$empty-body/' \
    "$ACTIVE_ROOT/empty-body/agents/openai.yaml"
assert_invalid empty-body \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/empty-body"

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/broken-resource"
sed -i \
    -e 's/name: valid-skill/name: broken-resource/' \
    -e 's#references/fixture.md#references/missing.md#' \
    "$ACTIVE_ROOT/broken-resource/SKILL.md"
sed -i \
    's/\\$valid-skill/\\$broken-resource/' \
    "$ACTIVE_ROOT/broken-resource/agents/openai.yaml"
grep -Fq 'references/missing.md' "$ACTIVE_ROOT/broken-resource/SKILL.md" ||
    fail "broken-resource fixture was not created"
assert_invalid broken-resource \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/broken-resource"

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/escaping-resource"
sed -i \
    -e 's/name: valid-skill/name: escaping-resource/' \
    -e 's#references/fixture.md#../../outside.md#' \
    "$ACTIVE_ROOT/escaping-resource/SKILL.md"
sed -i 's/\\$valid-skill/\\$escaping-resource/' \
    "$ACTIVE_ROOT/escaping-resource/agents/openai.yaml"
assert_invalid escaping-resource \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/escaping-resource"

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/bad-openai"
sed -i \
    's/name: valid-skill/name: bad-openai/' \
    "$ACTIVE_ROOT/bad-openai/SKILL.md"
sed -i \
    -e 's/"Fixture Skill"/Fixture Skill/' \
    -e 's/\\$valid-skill/\\$wrong-skill/' \
    "$ACTIVE_ROOT/bad-openai/agents/openai.yaml"
grep -Fqx 'name: bad-openai' "$ACTIVE_ROOT/bad-openai/SKILL.md" ||
    fail "bad-openai name fixture was not created"
grep -Fqx '  display_name: Fixture Skill' \
    "$ACTIVE_ROOT/bad-openai/agents/openai.yaml" ||
    fail "bad-openai interface fixture was not created"
assert_invalid bad-openai \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/bad-openai"

cp -a "$ACTIVE_ROOT/valid-skill" "$ACTIVE_ROOT/generated-mirror"
printf '%s\n' \
    '<!-- Generated from .agents/skills/generated-mirror/SKILL.md -->' \
    '# generated-mirror' \
    'This is only a pointer.' \
    > "$ACTIVE_ROOT/generated-mirror/SKILL.md"
assert_invalid generated-mirror \
    python3 "$VALIDATOR" --require-openai-yaml "$ACTIVE_ROOT/generated-mirror"

SCRIPT_ROOT="$TEST_TMP/script-skills/active"
SCRIPT_HOOKS="$TEST_TMP/script-skills/validation-hooks"
mkdir -p "$SCRIPT_HOOKS"
printf '%s\n' script-skill > "$SCRIPT_HOOKS/registry.txt"
write_valid_skill "$SCRIPT_ROOT" script-skill
mkdir -p "$SCRIPT_ROOT/script-skill/scripts"
printf '%s\n' '#!/bin/bash' 'printf "ok\\n"' \
    > "$SCRIPT_ROOT/script-skill/scripts/check.sh"
chmod +x "$SCRIPT_ROOT/script-skill/scripts/check.sh"

BAD_SCRIPT_ROOT="$TEST_TMP/bad-script-skills"
mkdir -p "$BAD_SCRIPT_ROOT"
cp -a "$SCRIPT_ROOT/script-skill" "$BAD_SCRIPT_ROOT/bad-script"
sed -i 's/name: script-skill/name: bad-script/' \
    "$BAD_SCRIPT_ROOT/bad-script/SKILL.md"
sed -i 's/\\$script-skill/\\$bad-script/' \
    "$BAD_SCRIPT_ROOT/bad-script/agents/openai.yaml"
printf '%s\n' '#!/bin/bash' 'if then' \
    > "$BAD_SCRIPT_ROOT/bad-script/scripts/check.sh"
chmod +x "$BAD_SCRIPT_ROOT/bad-script/scripts/check.sh"
grep -Fqx 'name: bad-script' "$BAD_SCRIPT_ROOT/bad-script/SKILL.md" ||
    fail "bad-script name fixture was not created"
if bash -n "$BAD_SCRIPT_ROOT/bad-script/scripts/check.sh" >/dev/null 2>&1; then
    fail "bad-script syntax fixture was not created"
fi
assert_invalid bad-script \
    python3 "$VALIDATOR" --require-openai-yaml "$BAD_SCRIPT_ROOT/bad-script"

mkdir -p "$SCRIPT_ROOT/script-skill/scripts/tests"
printf '%s\n' '#!/usr/bin/env python3' 'assert True' \
    > "$SCRIPT_ROOT/script-skill/scripts/tests/test_check.py"
chmod -x "$SCRIPT_ROOT/script-skill/scripts/tests/test_check.py"
python3 "$VALIDATOR" --require-openai-yaml \
    "$SCRIPT_ROOT/script-skill" >/dev/null

assert_invalid missing-hook env \
    DTVMDOTFILES_REPO_SKILL_TEST_CHILD=0 \
    DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR="$SCRIPT_ROOT" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$SCRIPT_ROOT" \
    DTVMDOTFILES_SKILL_VALIDATION_HOOKS_DIR="$SCRIPT_HOOKS" \
    bash -c 'source "$1/lib/sync_common.sh"; validateActiveSkills' \
    _ "$REPO_DIR"

printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '"$1/scripts/check.sh" >/dev/null' \
    > "$SCRIPT_HOOKS/script-skill.sh"
chmod +x "$SCRIPT_HOOKS/script-skill.sh"
env \
    DTVMDOTFILES_REPO_SKILL_TEST_CHILD=0 \
    DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR="$SCRIPT_ROOT" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$SCRIPT_ROOT" \
    DTVMDOTFILES_SKILL_VALIDATION_HOOKS_DIR="$SCRIPT_HOOKS" \
    bash -c 'source "$1/lib/sync_common.sh"; validateActiveSkills' \
    _ "$REPO_DIR" >/dev/null

printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "mutation\\n" >> "$1/SKILL.md"' \
    > "$SCRIPT_HOOKS/script-skill.sh"
chmod +x "$SCRIPT_HOOKS/script-skill.sh"
cp "$SCRIPT_ROOT/script-skill/SKILL.md" "$TEST_TMP/script-skill.before"
assert_invalid mutating-hook env \
    DTVMDOTFILES_REPO_SKILL_TEST_CHILD=0 \
    DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR="$SCRIPT_ROOT" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$SCRIPT_ROOT" \
    DTVMDOTFILES_SKILL_VALIDATION_HOOKS_DIR="$SCRIPT_HOOKS" \
    bash -c 'source "$1/lib/sync_common.sh"; validateActiveSkills' \
    _ "$REPO_DIR"
cmp -s "$TEST_TMP/script-skill.before" "$SCRIPT_ROOT/script-skill/SKILL.md" ||
    fail "mutating hook reached the real skill source"

# Release rejects invalid source before writing either the project checkout or
# the configured home directory.
INVALID_RELEASE_ROOT="$TEST_TMP/invalid-release/active"
INVALID_RELEASE_HOME="$TEST_TMP/invalid-release-home"
INVALID_RELEASE_DTVM="$TEST_TMP/invalid-release-dtvm"
INVALID_RELEASE_MAP="$TEST_TMP/invalid-release.map.sh"
mkdir -p "$INVALID_RELEASE_ROOT/generated-mirror" "$INVALID_RELEASE_DTVM"
printf '%s\n' '# Not a valid skill package' \
    > "$INVALID_RELEASE_ROOT/generated-mirror/SKILL.md"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'declare -Ag DTVM_SKILLS_MAP=()' \
    > "$INVALID_RELEASE_MAP"
assert_invalid release-invalid-source env \
    HOME="$INVALID_RELEASE_HOME" \
    DTVMDOTFILES_PARENT_DIR="$INVALID_RELEASE_DTVM" \
    DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR="$INVALID_RELEASE_ROOT" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$INVALID_RELEASE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$INVALID_RELEASE_MAP" \
    DTVMDOTFILES_REPO_SKILL_TEST_CHILD=0 \
    bash "$REPO_DIR/release.sh"
[ ! -e "$INVALID_RELEASE_HOME" ] ||
    fail "invalid release source wrote under HOME"
[ -z "$(find "$INVALID_RELEASE_DTVM" -mindepth 1 -print -quit)" ] ||
    fail "invalid release source changed the project checkout"

echo "PASS: skill validation"
