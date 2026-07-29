#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR="${DTVMDOTFILES_VALIDATION_ACTIVE_SKILLS_DIR:-$REPO_DIR/skills/active}"
export DTVMDOTFILES_REPO_SKILL_TEST_CHILD="${DTVMDOTFILES_REPO_SKILL_TEST_CHILD:-1}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep_flat() {
    tr '\n\t' '  ' < "$1" | tr -s ' ' | grep -Fq -- "$2"
}

# Keep the reader-facing inventory aligned with the lifecycle directories and
# the single suppression-policy map.
expected_active=(
    dtvm-archive
    dtvm-cold-compile-profile
    dtvm-compile-time-optimize
    dtvm-compiler-path-analysis
    dtvm-dev-cycle
    dtvm-dev-workflow
    dtvm-run-reth-replay
    dtvm-worktree-bootstrap
    dtvm-write-report
)
expected_retired=(
    dmir-compiler-analysis
    dtvm-perf-profile
)
expected_suppressed=(
    archive
    dev-workflow
    dmir-compiler-analysis
    dtvm-perf-profile
)
mapfile -t actual_active < <(
    find "$REPO_DIR/skills/active" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' | LC_ALL=C sort
)
mapfile -t actual_retired < <(
    find "$REPO_DIR/skills/retired" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' | LC_ALL=C sort
)
[ "${actual_active[*]}" = "${expected_active[*]}" ] ||
    fail "active skill inventory drifted"
[ "${actual_retired[*]}" = "${expected_retired[*]}" ] ||
    fail "retired skill inventory drifted"

inventory_docs=(
    "$REPO_DIR/README.md"
    "$REPO_DIR/SETUP_GUIDE.md"
    "$REPO_DIR/dotfiles/.claude/rules/dtvm-dotfiles-usage.md"
    "$REPO_DIR/dotfiles/CLAUDE.md"
    "$REPO_DIR/docs/changes/2026-07-23-personal-agent-skills/README.md"
)
for inventory_doc in "${inventory_docs[@]}"; do
    for skill_name in "${expected_active[@]}" "${expected_retired[@]}" \
        "${expected_suppressed[@]}"; do
        grep -Fq "$skill_name" "$inventory_doc" ||
            fail "skill inventory missing $skill_name: $inventory_doc"
    done
done
[ "$(grep -Fc -- '- **`dtvm-dev-cycle`**:' "$REPO_DIR/dotfiles/CLAUDE.md")" -eq 1 ] ||
    fail "project routing must list dtvm-dev-cycle exactly once"
grep -Fqx -- '- **Status**: Accepted' \
    "$REPO_DIR/docs/changes/2026-07-23-personal-agent-skills/README.md" ||
    fail "unmerged personal-skill change must remain Accepted"

# The DTVM-owned replacement must publish under a distinct active name while
# the repository-owned workflow name remains suppressed. The checked-in
# Claude adapter must also equal, not merely contain, the policy rendered from
# the shared map.
(
    unset DTVM_SKILLS_MAP
    # shellcheck source=/dev/null
    source "$REPO_DIR/dotfiles/skills.map.sh"
    [ "${DTVM_SKILLS_MAP[dev-workflow]:-}" = "legacy-repo" ] ||
        fail "repository dev-workflow is not suppressed"
    [ -z "${DTVM_SKILLS_MAP[dtvm-dev-workflow]+x}" ] ||
        fail "personal dtvm-dev-workflow is suppressed by name"
    [ -f "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" ] ||
        fail "personal dtvm-dev-workflow is not active"
    grep_flat "$REPO_DIR/dotfiles/CLAUDE.md" \
        'ordinary improvements and routine fixes is driven by the DTVMDotfiles-owned `dtvm-dev-workflow` skill' ||
        fail "project routing does not select dtvm-dev-workflow"
    grep_flat "$REPO_DIR/dotfiles/CLAUDE.md" \
        'For feature implementation, a new feature, an architecture change, a breaking change, or an explicit `/dev-cycle` invocation' ||
        fail "project routing does not escalate feature work"
    grep_flat "$REPO_DIR/dotfiles/CLAUDE.md" \
        'Do not auto-invoke it for ordinary improvements or routine fixes.' ||
        fail "project routing does not preserve the routine-work boundary"
    grep_flat "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
        'For feature implementation, a new feature, an architecture change, a breaking change, or an explicit `dev-cycle` request' ||
        fail "workflow skill does not escalate feature work"
    grep_flat "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
        'If `dtvm-dev-cycle` is not discoverable, state that once and continue here at Full tier.' ||
        fail "workflow skill is missing the Full-tier fallback"
    grep_flat "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md" \
        'Feature implementation, new features, architecture changes, breaking changes, and explicit `/dev-cycle` requests' ||
        fail "doc-agent routing does not escalate feature work"
    grep_flat "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
        'Until merge, report implementation and verification as complete while leaving the status `Accepted`.' ||
        fail "workflow skill does not preserve Accepted until merge"
    grep_flat "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md" \
        'set `Implemented` only after verified implementation is merged.' ||
        fail "doc-agent marks changes Implemented before merge"
    if grep -Fq '.agents/skills/dev-workflow/' \
        "$REPO_DIR/dotfiles/CLAUDE.md" \
        "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md"; then
        fail "deployed guidance still depends on upstream dev-workflow"
    fi
    if grep -Fq '~/claude-sync/skills/dev-cycle/' \
        "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
        "$REPO_DIR/dotfiles/CLAUDE.md" \
        "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md"; then
        fail "deployed routing depends on a machine-local dev-cycle path"
    fi
    if grep -Fq 'use `archive`' \
        "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
        "$REPO_DIR/dotfiles/CLAUDE.md" \
        "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md" ||
        grep -Fq 'invoke `archive`' \
            "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
            "$REPO_DIR/dotfiles/CLAUDE.md" \
            "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md" ||
        grep -Fq '$archive' \
        "$REPO_DIR/skills/active/dtvm-dev-workflow/SKILL.md" \
        "$REPO_DIR/dotfiles/CLAUDE.md" \
        "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md"; then
        fail "deployed routing uses the legacy archive skill name"
    fi
    expected_overrides="$(
        printf '%s\n' "${!DTVM_SKILLS_MAP[@]}" |
            LC_ALL=C sort |
            jq -Rn 'reduce inputs as $name ({}; .[$name] = "off")'
    )"
    actual_overrides="$(
        jq -cS '.skillOverrides // {}' \
            "$REPO_DIR/dotfiles/.claude/settings.json"
    )"
    expected_overrides="$(jq -cS . <<< "$expected_overrides")"
    [ "$actual_overrides" = "$expected_overrides" ] ||
        fail "checked-in Claude overrides differ from the shared skill map"
    for skill_name in "${!DTVM_SKILLS_MAP[@]}"; do
        [ "${DTVM_SKILLS_MAP[$skill_name]}" = "legacy-repo" ] ||
            fail "unexpected skill-map ownership: $skill_name"
    done
    mapfile -t actual_suppressed < <(
        printf '%s\n' "${!DTVM_SKILLS_MAP[@]}" | LC_ALL=C sort
    )
    [ "${actual_suppressed[*]}" = "${expected_suppressed[*]}" ] ||
        fail "suppression-policy inventory drifted"
)

write_skill_fixture() {
    local root="$1"
    local name="$2"
    mkdir -p "$root/$name/agents"
    printf '%s\n' \
        '---' \
        "name: $name" \
        'description: Validate an isolated agent-skill publication fixture.' \
        '---' \
        '' \
        '# Fixture Skill' \
        '' \
        'Validate publication behavior without touching live user state.' \
        > "$root/$name/SKILL.md"
    {
        printf '%s\n' \
            'interface:' \
            '  display_name: "Fixture Skill"' \
            '  short_description: "Validate isolated skill publication"'
        printf '  default_prompt: "Use $%s to validate this fixture."\n' "$name"
    } > "$root/$name/agents/openai.yaml"
}

assert_link() {
    [ -L "$1" ] || fail "missing symlink: $1"
    [ "$(readlink "$1")" = "$2" ] || fail "wrong symlink target: $1"
}

FAKE_DTVM="$TEST_TMP/dtvm"
INIT_WORKTREE="$TEST_TMP/worktree-init"
DYNAMIC_WORKTREE="$TEST_TMP/worktree-dynamic"
ACTIVE_ROOT="$TEST_TMP/source/skills/active"
INCUBATOR_ROOT="$TEST_TMP/source/skills/incubator"
RETIRED_ROOT="$TEST_TMP/source/skills/retired"
MAP_FILE="$TEST_TMP/skills.map.sh"
CLAUDE_SETTINGS_FILE="$TEST_TMP/source/settings.json"

mkdir -p \
    "$FAKE_DTVM" \
    "$INCUBATOR_ROOT/not-published"
write_skill_fixture "$ACTIVE_ROOT" active-one
write_skill_fixture "$ACTIVE_ROOT" retire-me
write_skill_fixture "$ACTIVE_ROOT" retire-direct
printf '%s\n' '---' 'name: not-published' 'description: test' '---' \
    > "$INCUBATOR_ROOT/not-published/SKILL.md"
cp "$REPO_DIR/dotfiles/skills.map.sh" "$MAP_FILE"
printf '%s\n' \
    '{' \
    '  "skillOverrides": {' \
    '    "stale-policy": "off"' \
    '  },' \
    '  "preserved": true' \
    '}' > "$CLAUDE_SETTINGS_FILE"
unset DTVM_SKILLS_MAP
# shellcheck source=/dev/null
source "$MAP_FILE"
mapfile -t EXPECTED_LEGACY_NAMES < <(
    printf '%s\n' "${!DTVM_SKILLS_MAP[@]}" | LC_ALL=C sort
)
EXPECTED_OVERRIDES="$(
    printf '%s\n' "${EXPECTED_LEGACY_NAMES[@]}" |
        jq -Rn 'reduce inputs as $name ({}; .[$name] = "off")'
)"
export DTVMDOTFILES_CLAUDE_SETTINGS_FILE="$CLAUDE_SETTINGS_FILE"

git -C "$FAKE_DTVM" init -q
git -C "$FAKE_DTVM" config user.name test
git -C "$FAKE_DTVM" config user.email test@example.com
printf '%s\n' seed > "$FAKE_DTVM/seed"
git -C "$FAKE_DTVM" add seed
git -C "$FAKE_DTVM" commit -qm seed
git -C "$FAKE_DTVM" worktree add -q -b test-init "$INIT_WORKTREE"

HOME_ONE="$TEST_TMP/home-one"
CODEX_ONE="$HOME_ONE/.agents/skills"
CLAUDE_ONE="$HOME_ONE/.claude/skills"
CONFIG_ONE="$HOME_ONE/.codex/config.toml"
mkdir -p "$CODEX_ONE" "$CLAUDE_ONE" "$(dirname "$CONFIG_ONE")"
ln -s "$ACTIVE_ROOT/stale-skill" "$CODEX_ONE/stale-skill"
ln -s "$ACTIVE_ROOT/active-one" "$CODEX_ONE/my-alias"
ln -s "$TEST_TMP/unrelated-owner" "$CODEX_ONE/unrelated-skill"
printf '%s\n' \
    'model = "keep-before"' \
    '# outside-before = \literal' \
    '# BEGIN DTVMDotfiles managed agent skills' \
    'stale = true' \
    '# END DTVMDotfiles managed agent skills' \
    'approval_policy = "never"' > "$CONFIG_ONE"

run_skills() {
    env \
        HOME="$HOME_ONE" \
        DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
        DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
        DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
        DTVMDOTFILES_CODEX_SKILLS_DIR="$CODEX_ONE" \
        DTVMDOTFILES_CLAUDE_SKILLS_DIR="$CLAUDE_ONE" \
        DTVMDOTFILES_CODEX_CONFIG_FILE="$CONFIG_ONE" \
        bash "$REPO_DIR/skills.sh" "$@"
}

run_skills sync >/dev/null
jq -e --argjson expected "$EXPECTED_OVERRIDES" '
    .skillOverrides == $expected and .preserved == true
' "$CLAUDE_SETTINGS_FILE" >/dev/null ||
    fail "Claude policy was not rendered from the shared map"
jq '.skillOverrides["stale-again"] = "off"' \
    "$CLAUDE_SETTINGS_FILE" > "$TEST_TMP/settings.with-stale.json"
mv "$TEST_TMP/settings.with-stale.json" "$CLAUDE_SETTINGS_FILE"
if run_skills check >/dev/null 2>&1; then
    fail "Claude policy check accepted a stale override"
fi
run_skills sync >/dev/null
jq -e --argjson expected "$EXPECTED_OVERRIDES" \
    '.skillOverrides == $expected' "$CLAUDE_SETTINGS_FILE" >/dev/null ||
    fail "Claude policy sync retained a stale override"
assert_link "$CODEX_ONE/active-one" "$ACTIVE_ROOT/active-one"
assert_link "$CLAUDE_ONE/active-one" "$ACTIVE_ROOT/active-one"
assert_link "$CODEX_ONE/retire-me" "$ACTIVE_ROOT/retire-me"
assert_link "$CLAUDE_ONE/retire-me" "$ACTIVE_ROOT/retire-me"
assert_link "$CODEX_ONE/retire-direct" "$ACTIVE_ROOT/retire-direct"
assert_link "$CLAUDE_ONE/retire-direct" "$ACTIVE_ROOT/retire-direct"
[ ! -e "$CODEX_ONE/not-published" ] || fail "incubator skill was published"
[ ! -L "$CODEX_ONE/stale-skill" ] || fail "stale managed link was retained"
[ "$(readlink "$CODEX_ONE/my-alias")" = "$ACTIVE_ROOT/active-one" ] ||
    fail "foreign alias to an active skill was changed"
[ "$(readlink "$CODEX_ONE/unrelated-skill")" = "$TEST_TMP/unrelated-owner" ] ||
    fail "unrelated foreign link was changed"
grep -Fqx 'model = "keep-before"' "$CONFIG_ONE" || fail "config prefix changed"
grep -Fqx '# outside-before = \literal' "$CONFIG_ONE" || fail "config prefix bytes changed"
grep -Fqx 'approval_policy = "never"' "$CONFIG_ONE" || fail "config suffix changed"
[ "$(tail -n 1 "$CONFIG_ONE")" = '# DTVMDotfiles agent skills tail anchor' ] ||
    fail "managed TOML tail anchor is not at EOF"
[ "$(grep -c 'enabled = false' "$CONFIG_ONE")" -eq "${#EXPECTED_LEGACY_NAMES[@]}" ] ||
    fail "wrong disabled skill count"
python3 - "$CONFIG_ONE" "${EXPECTED_LEGACY_NAMES[@]}" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert config["approval_policy"] == "never"
expected = [{"name": name, "enabled": False} for name in sys.argv[2:]]
assert config["skills"]["config"] == expected
PY
run_skills check >/dev/null
cp "$CONFIG_ONE" "$TEST_TMP/config.before"
run_skills sync >/dev/null
cmp -s "$TEST_TMP/config.before" "$CONFIG_ONE" || fail "sync is not idempotent"

# Preserve Codex-owned tables inserted before the tail anchor, outside the
# closed managed block.
sed -i '$i\
\
[plugins."outside-managed-block"]\
enabled = true' "$CONFIG_ONE"
cp "$CONFIG_ONE" "$TEST_TMP/config.codex-owned-outside"
run_skills check >/dev/null
run_skills sync >/dev/null
cmp -s "$TEST_TMP/config.codex-owned-outside" "$CONFIG_ONE" ||
    fail "sync changed a Codex-owned table outside the managed block"

# Migrate tables that an older EOF-only block accidentally enclosed instead of
# deleting client-owned configuration.
sed -i '/# END DTVMDotfiles managed agent skills/i\
\
  [plugins."inside-old-managed-block"]  \
enabled = true' "$CONFIG_ONE"
run_skills sync >/dev/null
python3 - "$CONFIG_ONE" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert config["plugins"]["outside-managed-block"]["enabled"] is True
assert config["plugins"]["inside-old-managed-block"]["enabled"] is True
PY
inside_line="$(grep -nF '  [plugins."inside-old-managed-block"]  ' "$CONFIG_ONE" | cut -d: -f1)"
begin_line="$(grep -nF '# BEGIN DTVMDotfiles managed agent skills' "$CONFIG_ONE" | cut -d: -f1)"
[ "$inside_line" -lt "$begin_line" ] ||
    fail "Codex-owned table was not moved outside the managed block"
run_skills check >/dev/null

# Worktree additions and removals do not affect the static name policy.
cp "$CONFIG_ONE" "$TEST_TMP/config.worktree-independent"
git -C "$FAKE_DTVM" worktree add -q -b test-dynamic "$DYNAMIC_WORKTREE"
run_skills sync >/dev/null
cmp -s "$TEST_TMP/config.worktree-independent" "$CONFIG_ONE" ||
    fail "adding a worktree changed the static skill policy"
git -C "$FAKE_DTVM" worktree remove --force "$DYNAMIC_WORKTREE"
run_skills sync >/dev/null
cmp -s "$TEST_TMP/config.worktree-independent" "$CONFIG_ONE" ||
    fail "removing a worktree changed the static skill policy"

# Moving an active skill out of the lifecycle removes only its managed links.
mv "$ACTIVE_ROOT/retire-me" "$INCUBATOR_ROOT/retire-me"
mkdir -p "$RETIRED_ROOT"
mv "$ACTIVE_ROOT/retire-direct" "$RETIRED_ROOT/retire-direct"
run_skills sync >/dev/null
[ ! -L "$CODEX_ONE/retire-me" ] || fail "retired Codex skill link was retained"
[ ! -L "$CLAUDE_ONE/retire-me" ] || fail "retired Claude skill link was retained"
[ ! -L "$CODEX_ONE/retire-direct" ] ||
    fail "directly retired Codex skill link was retained"
[ ! -L "$CLAUDE_ONE/retire-direct" ] ||
    fail "directly retired Claude skill link was retained"
[ "$(readlink "$CODEX_ONE/unrelated-skill")" = "$TEST_TMP/unrelated-owner" ] ||
    fail "lifecycle reconciliation changed an unrelated link"
run_skills check >/dev/null

# A collision of any foreign object shape aborts before destination/config writes.
assert_foreign_collision() {
    local shape="$1"
    local home="$TEST_TMP/home-collision-$shape"
    local codex="$home/.agents/skills"
    local claude="$home/.claude/skills"
    local config="$home/.codex/config.toml"

    mkdir -p "$codex" "$(dirname "$config")"
    case "$shape" in
        directory)
            mkdir "$codex/active-one"
            printf '%s\n' foreign > "$codex/active-one/owner"
            ;;
        file) printf '%s\n' foreign > "$codex/active-one" ;;
        symlink) ln -s "$TEST_TMP/foreign-skill" "$codex/active-one" ;;
        lexical) ln -s "$ACTIVE_ROOT/../foreign-skill" "$codex/active-one" ;;
        *) fail "unknown collision shape: $shape" ;;
    esac
    printf '%s\n' untouched > "$config"

    if env \
        HOME="$home" \
        DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
        DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
        DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
        DTVMDOTFILES_CODEX_SKILLS_DIR="$codex" \
        DTVMDOTFILES_CLAUDE_SKILLS_DIR="$claude" \
        DTVMDOTFILES_CODEX_CONFIG_FILE="$config" \
        bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
        fail "foreign $shape collision unexpectedly succeeded"
    fi
    [ ! -e "$claude" ] || fail "$shape collision caused writes to second harness"
    [ "$(cat "$config")" = "untouched" ] || fail "$shape collision changed config"
    case "$shape" in
        directory)
            grep -Fqx foreign "$codex/active-one/owner" ||
                fail "foreign directory content changed"
            ;;
        file)
            grep -Fqx foreign "$codex/active-one" ||
                fail "foreign file content changed"
            ;;
        symlink | lexical)
            local expected_target="$TEST_TMP/foreign-skill"
            [ "$shape" = "lexical" ] &&
                expected_target="$ACTIVE_ROOT/../foreign-skill"
            [ "$(readlink "$codex/active-one")" = "$expected_target" ] ||
                fail "foreign symlink target changed"
            ;;
    esac
}

assert_foreign_collision directory
assert_foreign_collision file
assert_foreign_collision symlink
assert_foreign_collision lexical

# A link to an older DTVMDotfiles checkout remains foreign until explicitly removed.
OLD_ACTIVE_ROOT="$TEST_TMP/old-checkout/skills/active"
HOME_RELOCATED="$TEST_TMP/home-relocated"
CODEX_RELOCATED="$HOME_RELOCATED/.agents/skills"
CLAUDE_RELOCATED="$HOME_RELOCATED/.claude/skills"
CONFIG_RELOCATED="$HOME_RELOCATED/.codex/config.toml"
mkdir -p "$OLD_ACTIVE_ROOT/active-one" "$CODEX_RELOCATED" "$(dirname "$CONFIG_RELOCATED")"
printf '%s\n' '---' 'name: active-one' 'description: old' '---' \
    > "$OLD_ACTIVE_ROOT/active-one/SKILL.md"
ln -s "$OLD_ACTIVE_ROOT/active-one" "$CODEX_RELOCATED/active-one"
printf '%s\n' untouched > "$CONFIG_RELOCATED"
if env \
    HOME="$HOME_RELOCATED" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    DTVMDOTFILES_CODEX_SKILLS_DIR="$CODEX_RELOCATED" \
    DTVMDOTFILES_CLAUDE_SKILLS_DIR="$CLAUDE_RELOCATED" \
    DTVMDOTFILES_CODEX_CONFIG_FILE="$CONFIG_RELOCATED" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "old-checkout link was silently claimed"
fi
[ "$(readlink "$CODEX_RELOCATED/active-one")" = "$OLD_ACTIVE_ROOT/active-one" ] ||
    fail "old-checkout link changed"
[ ! -e "$CLAUDE_RELOCATED" ] || fail "relocation collision caused second-harness writes"
[ "$(cat "$CONFIG_RELOCATED")" = "untouched" ] ||
    fail "relocation collision changed config"

# The discovery namespace itself must be a real directory, not a symlink.
HOME_ROOT_LINK="$TEST_TMP/home-root-link"
ROOT_LINK_OWNER="$TEST_TMP/root-link-owner"
CODEX_ROOT_LINK="$HOME_ROOT_LINK/.agents/skills"
CLAUDE_ROOT_LINK="$HOME_ROOT_LINK/.claude/skills"
CONFIG_ROOT_LINK="$HOME_ROOT_LINK/.codex/config.toml"
mkdir -p "$HOME_ROOT_LINK/.agents" "$ROOT_LINK_OWNER" "$(dirname "$CONFIG_ROOT_LINK")"
ln -s "$ROOT_LINK_OWNER" "$CODEX_ROOT_LINK"
printf '%s\n' untouched > "$CONFIG_ROOT_LINK"
if env \
    HOME="$HOME_ROOT_LINK" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    DTVMDOTFILES_CODEX_SKILLS_DIR="$CODEX_ROOT_LINK" \
    DTVMDOTFILES_CLAUDE_SKILLS_DIR="$CLAUDE_ROOT_LINK" \
    DTVMDOTFILES_CODEX_CONFIG_FILE="$CONFIG_ROOT_LINK" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "symlinked discovery root unexpectedly succeeded"
fi
[ -z "$(find "$ROOT_LINK_OWNER" -mindepth 1 -print -quit)" ] ||
    fail "symlinked discovery root received writes"
[ ! -e "$CLAUDE_ROOT_LINK" ] || fail "root collision caused writes to second harness"
[ "$(cat "$CONFIG_ROOT_LINK")" = "untouched" ] || fail "root collision changed config"

# A symlinked ancestor cannot redirect discovery writes.
HOME_ANCESTOR_LINK="$TEST_TMP/home-ancestor-link"
ANCESTOR_LINK_OWNER="$TEST_TMP/ancestor-link-owner"
mkdir -p "$HOME_ANCESTOR_LINK" "$ANCESTOR_LINK_OWNER"
ln -s "$ANCESTOR_LINK_OWNER" "$HOME_ANCESTOR_LINK/.agents"
if env \
    HOME="$HOME_ANCESTOR_LINK" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "symlinked discovery ancestor unexpectedly succeeded"
fi
[ -z "$(find "$ANCESTOR_LINK_OWNER" -mindepth 1 -print -quit)" ] ||
    fail "symlinked discovery ancestor received writes"

# A symlinked Codex-config ancestor is also rejected before link writes.
HOME_CONFIG_LINK="$TEST_TMP/home-config-link"
CONFIG_LINK_OWNER="$TEST_TMP/config-link-owner"
mkdir -p "$HOME_CONFIG_LINK/.agents/skills" "$HOME_CONFIG_LINK/.claude/skills" "$CONFIG_LINK_OWNER"
ln -s "$CONFIG_LINK_OWNER" "$HOME_CONFIG_LINK/.codex"
if env \
    HOME="$HOME_CONFIG_LINK" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "symlinked config ancestor unexpectedly succeeded"
fi
[ -z "$(find "$CONFIG_LINK_OWNER" -mindepth 1 -print -quit)" ] ||
    fail "symlinked config ancestor received writes"
[ -z "$(find "$HOME_CONFIG_LINK/.agents/skills" -mindepth 1 -print -quit)" ] ||
    fail "config ancestor failure caused Codex link writes"
[ -z "$(find "$HOME_CONFIG_LINK/.claude/skills" -mindepth 1 -print -quit)" ] ||
    fail "config ancestor failure caused Claude link writes"

# Invalid active metadata fails before user state is created.
BAD_ACTIVE="$TEST_TMP/source/skills/bad-active"
mkdir -p "$BAD_ACTIVE/name-mismatch"
printf '%s\n' '---' 'name: another-name' 'description: test' '---' \
    > "$BAD_ACTIVE/name-mismatch/SKILL.md"
HOME_BAD_ACTIVE="$TEST_TMP/home-bad-active"
if env \
    HOME="$HOME_BAD_ACTIVE" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$BAD_ACTIVE" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "frontmatter name mismatch unexpectedly succeeded"
fi
[ ! -e "$HOME_BAD_ACTIVE" ] || fail "invalid active metadata caused writes"

# An unknown ownership value in the policy map fails closed instead of
# silently removing a suppression rule from both clients.
BAD_MAP="$TEST_TMP/skills.bad.map.sh"
HOME_BAD_MAP="$TEST_TMP/home-bad-map"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'declare -Ag DTVM_SKILLS_MAP=(' \
    '    ["old-profile"]="legacy-reop"' \
    ')' > "$BAD_MAP"
cp "$CLAUDE_SETTINGS_FILE" "$TEST_TMP/settings.before-bad-map.json"
if env \
    HOME="$HOME_BAD_MAP" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$BAD_MAP" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "unknown skill-map ownership unexpectedly succeeded"
fi
[ ! -e "$HOME_BAD_MAP" ] || fail "invalid skill map caused user-level writes"
cmp -s "$TEST_TMP/settings.before-bad-map.json" "$CLAUDE_SETTINGS_FILE" ||
    fail "invalid skill map changed the Claude adapter"

# All ambiguous marker shapes fail closed without creating link roots.
assert_bad_markers() {
    local label="$1"
    shift
    local home="$TEST_TMP/home-bad-markers-$label"
    local config="$home/.codex/config.toml"

    mkdir -p "$(dirname "$config")"
    printf '%s\n' "$@" > "$config"
    cp "$config" "$TEST_TMP/bad-markers-$label.before"
    if env \
        HOME="$home" \
        DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
        DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
        DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
        bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
        fail "$label managed markers unexpectedly succeeded"
    fi
    cmp -s "$TEST_TMP/bad-markers-$label.before" "$config" ||
        fail "$label marker failure changed config"
    [ ! -e "$home/.agents" ] || fail "$label markers caused Codex link writes"
    [ ! -e "$home/.claude" ] || fail "$label markers caused Claude link writes"
}

assert_bad_markers duplicate-start \
    '# BEGIN DTVMDotfiles managed agent skills' \
    '# BEGIN DTVMDotfiles managed agent skills' \
    '# END DTVMDotfiles managed agent skills'
assert_bad_markers partial \
    '# BEGIN DTVMDotfiles managed agent skills'
assert_bad_markers reversed \
    '# END DTVMDotfiles managed agent skills' \
    '# BEGIN DTVMDotfiles managed agent skills'
assert_bad_markers duplicate-end \
    '# BEGIN DTVMDotfiles managed agent skills' \
    '# END DTVMDotfiles managed agent skills' \
    '# END DTVMDotfiles managed agent skills'
assert_bad_markers orphan-tail \
    '# DTVMDotfiles agent skills tail anchor'
assert_bad_markers misplaced-tail \
    '# BEGIN DTVMDotfiles managed agent skills' \
    '# DTVMDotfiles agent skills tail anchor' \
    '# END DTVMDotfiles managed agent skills'
assert_bad_markers duplicate-tail \
    '# BEGIN DTVMDotfiles managed agent skills' \
    '# END DTVMDotfiles managed agent skills' \
    '# DTVMDotfiles agent skills tail anchor' \
    '# DTVMDotfiles agent skills tail anchor'

# RELEASE_CHECK is a complete no-write reconciliation.
HOME_THREE="$TEST_TMP/home-three"
if env \
    HOME="$HOME_THREE" \
    RELEASE_CHECK=1 \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null; then
    [ ! -e "$HOME_THREE/.agents" ] || fail "dry-run created Codex skill directory"
    [ ! -e "$HOME_THREE/.claude" ] || fail "dry-run created Claude skill directory"
    [ ! -e "$HOME_THREE/.codex" ] || fail "dry-run created Codex config directory"
else
    fail "dry-run failed"
fi

# A missing config is created as valid TOML with the static name policy.
HOME_VALID_TOML="$TEST_TMP/home-valid-toml"
env \
    HOME="$HOME_VALID_TOML" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null
python3 - \
    "$HOME_VALID_TOML/.codex/config.toml" \
    "${EXPECTED_LEGACY_NAMES[@]}" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
entries = config["skills"]["config"]
expected = [{"name": name, "enabled": False} for name in sys.argv[2:]]
assert entries == expected, entries
PY
[ "$(tail -n 1 "$HOME_VALID_TOML/.codex/config.toml")" = \
    '# DTVMDotfiles agent skills tail anchor' ] ||
    fail "new Codex config is missing the tail anchor"

# release refuses a stale generated Claude adapter before touching either the
# project checkout or user state.
HOME_STALE_RELEASE="$TEST_TMP/home-stale-release"
STALE_RELEASE_STATUS="$(git -C "$FAKE_DTVM" status --porcelain)"
jq '.skillOverrides["stale-before-release"] = "off"' \
    "$CLAUDE_SETTINGS_FILE" > "$TEST_TMP/settings.stale-before-release.json"
mv "$TEST_TMP/settings.stale-before-release.json" "$CLAUDE_SETTINGS_FILE"
if env \
    HOME="$HOME_STALE_RELEASE" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "release accepted a stale Claude skill adapter"
fi
[ "$(git -C "$FAKE_DTVM" status --porcelain)" = "$STALE_RELEASE_STATUS" ] ||
    fail "stale Claude adapter changed the DTVM repository"
[ ! -e "$HOME_STALE_RELEASE" ] ||
    fail "stale Claude adapter caused user-level writes"
run_skills sync >/dev/null

# The release entry point also keeps RELEASE_CHECK fully read-only.
HOME_FIVE="$TEST_TMP/home-five"
STATUS_BEFORE="$(git -C "$FAKE_DTVM" status --porcelain)"
env \
    HOME="$HOME_FIVE" \
    RELEASE_CHECK=1 \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null
[ "$(git -C "$FAKE_DTVM" status --porcelain)" = "$STATUS_BEFORE" ] ||
    fail "release dry-run changed the DTVM repository"
[ ! -e "$HOME_FIVE" ] || fail "release dry-run wrote under HOME"

# Removed manifest files retain the same local-modification gate as copied files.
REMOVED_REL=".agents/skills/worktree-bootstrap/SKILL.md"
REMOVED_PATH="$FAKE_DTVM/$REMOVED_REL"
REMOVED_ORIGINAL_HASH="$(printf '%s\n' original | sha256sum | cut -c1-12)"
mkdir -p "$(dirname "$REMOVED_PATH")" "$FAKE_DTVM/.claude"
printf '%s\n' 'locally modified bootstrap' > "$REMOVED_PATH"
printf '%s\n' \
    '{' \
    '  "version": 1,' \
    '  "synced_at": "test",' \
    '  "files": {' \
    "    \"$REMOVED_REL\": \"$REMOVED_ORIGINAL_HASH\"" \
    '  }' \
    '}' > "$FAKE_DTVM/.claude/.dtvm-manifest.json"

HOME_RELEASE="$TEST_TMP/home-release"
if env \
    HOME="$HOME_RELEASE" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "release removed a locally modified retired manifest file"
fi
grep -Fqx 'locally modified bootstrap' "$REMOVED_PATH" ||
    fail "failed release changed the retired manifest file"
[ ! -e "$FAKE_DTVM/CLAUDE.md" ] ||
    fail "removed-file preflight happened after project writes"
[ ! -e "$HOME_RELEASE" ] ||
    fail "removed-file preflight caused user-level writes"

# Even an explicit recovery override cannot redirect personal content into DTVM.
if env \
    HOME="$HOME_RELEASE" \
    RELEASE_FORCE=1 \
    DTVMDOTFILES_RECOVERY_DIR="$FAKE_DTVM/recovery" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "recovery directory inside DTVM unexpectedly succeeded"
fi
grep -Fqx 'locally modified bootstrap' "$REMOVED_PATH" ||
    fail "unsafe recovery override changed the retired manifest file"
[ ! -e "$FAKE_DTVM/recovery" ] ||
    fail "unsafe recovery override wrote inside DTVM"

# Lexically different but equivalent paths cannot bypass containment.
EQUIVALENT_RECOVERY="$(dirname "$FAKE_DTVM")//$(basename "$FAKE_DTVM")/recovery-equivalent"
if env \
    HOME="$HOME_RELEASE" \
    RELEASE_FORCE=1 \
    DTVMDOTFILES_RECOVERY_DIR="$EQUIVALENT_RECOVERY" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "non-canonical recovery path inside DTVM unexpectedly succeeded"
fi
grep -Fqx 'locally modified bootstrap' "$REMOVED_PATH" ||
    fail "equivalent recovery path changed the retired manifest file"
[ ! -e "$FAKE_DTVM/recovery-equivalent" ] ||
    fail "equivalent recovery path wrote inside DTVM"

# A recovery path that cannot be a directory fails before removal.
RECOVERY_FILE="$TEST_TMP/recovery-file"
printf '%s\n' occupied > "$RECOVERY_FILE"
if env \
    HOME="$HOME_RELEASE" \
    RELEASE_FORCE=1 \
    DTVMDOTFILES_RECOVERY_DIR="$RECOVERY_FILE" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "non-directory recovery path unexpectedly succeeded"
fi
grep -Fqx 'locally modified bootstrap' "$REMOVED_PATH" ||
    fail "recovery preflight failure removed the source"

# A tracked path is never treated as DTVMDotfiles-owned, even when its content
# exactly matches the old manifest.
TRACKED_DTVM="$TEST_TMP/dtvm-tracked-removal"
TRACKED_REMOVED_PATH="$TRACKED_DTVM/$REMOVED_REL"
HOME_TRACKED_RELEASE="$TEST_TMP/home-tracked-release"
mkdir -p "$(dirname "$TRACKED_REMOVED_PATH")" "$TRACKED_DTVM/.claude"
git -C "$TRACKED_DTVM" init -q
git -C "$TRACKED_DTVM" config user.name test
git -C "$TRACKED_DTVM" config user.email test@example.com
printf '%s\n' original > "$TRACKED_REMOVED_PATH"
git -C "$TRACKED_DTVM" add "$REMOVED_REL"
git -C "$TRACKED_DTVM" commit -qm 'tracked skill fixture'
printf '%s\n' \
    '{' \
    '  "version": 1,' \
    '  "synced_at": "test",' \
    '  "files": {' \
    "    \"$REMOVED_REL\": \"$REMOVED_ORIGINAL_HASH\"" \
    '  }' \
    '}' > "$TRACKED_DTVM/.claude/.dtvm-manifest.json"
if env \
    HOME="$HOME_TRACKED_RELEASE" \
    DTVMDOTFILES_PARENT_DIR="$TRACKED_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "release removed a DTVM-tracked retired manifest file"
fi
git -C "$TRACKED_DTVM" diff --quiet -- "$REMOVED_REL" ||
    fail "tracked retired manifest file changed"
grep -Fqx original "$TRACKED_REMOVED_PATH" ||
    fail "tracked retired manifest file content changed"
[ ! -e "$HOME_TRACKED_RELEASE" ] ||
    fail "tracked-path preflight caused user-level writes"

# A symlinked ancestor cannot redirect old-manifest deletion outside DTVM.
SYMLINK_DTVM="$TEST_TMP/dtvm-symlink-removal"
SYMLINK_EXTERNAL="$TEST_TMP/symlink-removal-external"
SYMLINK_REL="managed/file"
SYMLINK_HASH="$(printf '%s\n' external | sha256sum | cut -c1-12)"
mkdir -p "$SYMLINK_DTVM/.claude" "$SYMLINK_EXTERNAL"
git -C "$SYMLINK_DTVM" init -q
git -C "$SYMLINK_DTVM" config user.name test
git -C "$SYMLINK_DTVM" config user.email test@example.com
printf '%s\n' seed > "$SYMLINK_DTVM/seed"
git -C "$SYMLINK_DTVM" add seed
git -C "$SYMLINK_DTVM" commit -qm seed
printf '%s\n' external > "$SYMLINK_EXTERNAL/file"
ln -s "$SYMLINK_EXTERNAL" "$SYMLINK_DTVM/managed"
printf '%s\n' \
    '{' \
    '  "version": 1,' \
    '  "synced_at": "test",' \
    '  "files": {' \
    "    \"$SYMLINK_REL\": \"$SYMLINK_HASH\"" \
    '  }' \
    '}' > "$SYMLINK_DTVM/.claude/.dtvm-manifest.json"
if env \
    HOME="$TEST_TMP/home-symlink-removal" \
    DTVMDOTFILES_PARENT_DIR="$SYMLINK_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "symlinked old-manifest ancestor unexpectedly succeeded"
fi
grep -Fqx external "$SYMLINK_EXTERNAL/file" ||
    fail "old-manifest cleanup followed an external symlink"

# Git ownership lookup errors fail closed instead of becoming "untracked".
BROKEN_INDEX_DTVM="$TEST_TMP/dtvm-broken-index"
BROKEN_INDEX_PATH="$BROKEN_INDEX_DTVM/$REMOVED_REL"
mkdir -p "$(dirname "$BROKEN_INDEX_PATH")" "$BROKEN_INDEX_DTVM/.claude"
git -C "$BROKEN_INDEX_DTVM" init -q
git -C "$BROKEN_INDEX_DTVM" config user.name test
git -C "$BROKEN_INDEX_DTVM" config user.email test@example.com
printf '%s\n' original > "$BROKEN_INDEX_PATH"
git -C "$BROKEN_INDEX_DTVM" add "$REMOVED_REL"
git -C "$BROKEN_INDEX_DTVM" commit -qm 'broken index fixture'
printf '%s\n' \
    '{' \
    '  "version": 1,' \
    '  "synced_at": "test",' \
    '  "files": {' \
    "    \"$REMOVED_REL\": \"$REMOVED_ORIGINAL_HASH\"" \
    '  }' \
    '}' > "$BROKEN_INDEX_DTVM/.claude/.dtvm-manifest.json"
printf '%s\n' corrupt > "$BROKEN_INDEX_DTVM/.git/index"
if env \
    HOME="$TEST_TMP/home-broken-index" \
    DTVMDOTFILES_PARENT_DIR="$BROKEN_INDEX_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null 2>&1; then
    fail "release ignored a Git ownership lookup error"
fi
grep -Fqx original "$BROKEN_INDEX_PATH" ||
    fail "Git ownership lookup failure removed the source"

# A forced migration backs up the exact removed file before a real release.
env \
    HOME="$HOME_RELEASE" \
    RELEASE_FORCE=1 \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/release.sh" >/dev/null
[ ! -e "$REMOVED_PATH" ] || fail "forced migration retained the removed file"
REMOVED_BACKUP="$(
    find "$HOME_RELEASE/.local/state/DTVMDotfiles/release-backups" \
        -type f -name 'SKILL.md.pre-release.*' -print -quit
)"
[ -n "$REMOVED_BACKUP" ] || fail "forced migration did not create a recovery backup"
grep -Fqx 'locally modified bootstrap' "$REMOVED_BACKUP" ||
    fail "forced migration did not preserve the removed file backup"
[ -z "$(git -C "$FAKE_DTVM" status --porcelain -- .agents/skills)" ] ||
    fail "forced migration left personal skill source in DTVM"
cmp -s "$FAKE_DTVM/CLAUDE.md" "$FAKE_DTVM/AGENTS.md" ||
    fail "release did not generate AGENTS.md from CLAUDE.md"
cmp -s "$FAKE_DTVM/CLAUDE.md" "$FAKE_DTVM/GEMINI.md" ||
    fail "release did not generate GEMINI.md from CLAUDE.md"
cmp -s \
    "$REPO_DIR/dotfiles/.claude/settings.json" \
    "$FAKE_DTVM/.claude/settings.json" ||
    fail "release did not deploy Claude skill overrides"
assert_link "$HOME_RELEASE/.agents/skills/active-one" "$ACTIVE_ROOT/active-one"
assert_link "$HOME_RELEASE/.claude/skills/active-one" "$ACTIVE_ROOT/active-one"

# worktree-init is independent of global personal-skill reconciliation.
mkdir -p "$INIT_WORKTREE/evmc/include"
HOME_INIT_COLLISION="$TEST_TMP/home-init-collision"
CODEX_INIT_COLLISION="$HOME_INIT_COLLISION/.agents/skills"
CONFIG_INIT_COLLISION="$HOME_INIT_COLLISION/.codex/config.toml"
mkdir -p "$CODEX_INIT_COLLISION/active-one"
mkdir -p "$(dirname "$CONFIG_INIT_COLLISION")"
printf '%s\n' foreign > "$CODEX_INIT_COLLISION/active-one/owner"
printf '%s\n' untouched > "$CONFIG_INIT_COLLISION"
env \
    HOME="$HOME_INIT_COLLISION" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    DTVM_WORKTREE_INIT_USE_GIT_MIRRORS=0 \
    bash "$REPO_DIR/worktree-init.sh" --minimal "$INIT_WORKTREE" >/dev/null
grep -Fqx foreign "$CODEX_INIT_COLLISION/active-one/owner" ||
    fail "worktree-init changed the global skill collision"
[ "$(find "$CODEX_INIT_COLLISION" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] ||
    fail "worktree-init published user-level Codex skill links"
[ ! -e "$HOME_INIT_COLLISION/.claude" ] ||
    fail "worktree-init published user-level Claude skill links"
[ "$(cat "$CONFIG_INIT_COLLISION")" = "untouched" ] ||
    fail "worktree-init changed the user-level Codex config"
[ -L "$INIT_WORKTREE/AGENTS.md" ] || fail "worktree-init did not link AGENTS.md"

bash "$REPO_DIR/tests/worktree_sync_test.sh"

echo "PASS: agent skill integration"
