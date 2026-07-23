#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_link() {
    [ -L "$1" ] || fail "missing symlink: $1"
    [ "$(readlink "$1")" = "$2" ] || fail "wrong symlink target: $1"
}

FAKE_DTVM="$TEST_TMP/dtvm"
ODD_WORKTREE="$TEST_TMP/worktree with \"quote\" and \\slash"
CONTROL_WORKTREE="$TEST_TMP/worktree"$'\v'"control"
ACTIVE_ROOT="$TEST_TMP/source/skills/active"
INCUBATOR_ROOT="$TEST_TMP/source/skills/incubator"
RETIRED_ROOT="$TEST_TMP/source/skills/retired"
MAP_FILE="$TEST_TMP/skills.map.sh"

mkdir -p \
    "$FAKE_DTVM" \
    "$ACTIVE_ROOT/active-one" \
    "$ACTIVE_ROOT/retire-me" \
    "$ACTIVE_ROOT/retire-direct" \
    "$INCUBATOR_ROOT/not-published"
printf '%s\n' '---' 'name: active-one' 'description: test' '---' > "$ACTIVE_ROOT/active-one/SKILL.md"
printf '%s\n' '---' 'name: retire-me' 'description: test' '---' > "$ACTIVE_ROOT/retire-me/SKILL.md"
printf '%s\n' '---' 'name: retire-direct' 'description: test' '---' \
    > "$ACTIVE_ROOT/retire-direct/SKILL.md"
printf '%s\n' '---' 'name: not-published' 'description: test' '---' > "$INCUBATOR_ROOT/not-published/SKILL.md"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'declare -Ag DTVM_SKILLS_MAP=(' \
    '    ["old-analysis"]="legacy-repo"' \
    '    ["old-profile"]="legacy-repo"' \
    ')' > "$MAP_FILE"

git -C "$FAKE_DTVM" init -q
git -C "$FAKE_DTVM" config user.name test
git -C "$FAKE_DTVM" config user.email test@example.com
printf '%s\n' seed > "$FAKE_DTVM/seed"
git -C "$FAKE_DTVM" add seed
git -C "$FAKE_DTVM" commit -qm seed
git -C "$FAKE_DTVM" worktree add -q -b test-odd "$ODD_WORKTREE"
git -C "$FAKE_DTVM" worktree add -q -b test-control "$CONTROL_WORKTREE"

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
[ "$(tail -n 1 "$CONFIG_ONE")" = '# END DTVMDotfiles managed agent skills' ] ||
    fail "managed TOML block is not at EOF"
[ "$(grep -c 'enabled = false' "$CONFIG_ONE")" -eq 6 ] || fail "wrong disabled skill count"
grep -Fq '\"quote\" and \\slash/.agents/skills/old-analysis/SKILL.md' "$CONFIG_ONE" ||
    fail "TOML path was not escaped"
grep -Fq '\u000Bcontrol/.agents/skills/old-analysis/SKILL.md' "$CONFIG_ONE" ||
    fail "TOML control character was not escaped"
python3 - "$CONFIG_ONE" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert config["approval_policy"] == "never"
assert len(config["skills"]["config"]) == 6
assert "approval_policy" not in config["skills"]["config"][-1]
PY
run_skills check >/dev/null
cp "$CONFIG_ONE" "$TEST_TMP/config.before"
run_skills sync >/dev/null
cmp -s "$TEST_TMP/config.before" "$CONFIG_ONE" || fail "sync is not idempotent"

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

# A Git-accepted non-UTF-8 worktree path fails before any user-level write.
INVALID_UTF8_DTVM="$TEST_TMP/dtvm-invalid-utf8"
INVALID_UTF8_WORKTREE="$TEST_TMP/worktree-"$'\xff'
HOME_INVALID_UTF8="$TEST_TMP/home-invalid-utf8"
mkdir -p "$INVALID_UTF8_DTVM"
git -C "$INVALID_UTF8_DTVM" init -q
git -C "$INVALID_UTF8_DTVM" config user.name test
git -C "$INVALID_UTF8_DTVM" config user.email test@example.com
printf '%s\n' seed > "$INVALID_UTF8_DTVM/seed"
git -C "$INVALID_UTF8_DTVM" add seed
git -C "$INVALID_UTF8_DTVM" commit -qm seed
git -C "$INVALID_UTF8_DTVM" worktree add -q -b invalid-utf8 \
    "$INVALID_UTF8_WORKTREE"
if env \
    HOME="$HOME_INVALID_UTF8" \
    DTVMDOTFILES_PARENT_DIR="$INVALID_UTF8_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null 2>&1; then
    fail "non-UTF-8 worktree path unexpectedly succeeded"
fi
[ ! -e "$HOME_INVALID_UTF8" ] ||
    fail "non-UTF-8 worktree path caused user-level writes"

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

# A missing config is created as valid TOML with all known worktree entries.
HOME_VALID_TOML="$TEST_TMP/home-valid-toml"
env \
    HOME="$HOME_VALID_TOML" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    bash "$REPO_DIR/skills.sh" sync >/dev/null
python3 - "$HOME_VALID_TOML/.codex/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
entries = config["skills"]["config"]
assert len(entries) == 6, entries
assert all(entry["enabled"] is False for entry in entries), entries
PY

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
assert_link "$HOME_RELEASE/.agents/skills/active-one" "$ACTIVE_ROOT/active-one"
assert_link "$HOME_RELEASE/.claude/skills/active-one" "$ACTIVE_ROOT/active-one"

# worktree-init propagates reconciler failures, then succeeds end to end.
mkdir -p "$ODD_WORKTREE/evmc/include"
HOME_INIT_COLLISION="$TEST_TMP/home-init-collision"
CODEX_INIT_COLLISION="$HOME_INIT_COLLISION/.agents/skills"
mkdir -p "$CODEX_INIT_COLLISION/active-one"
if env \
    HOME="$HOME_INIT_COLLISION" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    DTVM_WORKTREE_INIT_USE_GIT_MIRRORS=0 \
    bash "$REPO_DIR/worktree-init.sh" --minimal "$ODD_WORKTREE" >/dev/null 2>&1; then
    fail "worktree-init swallowed an agent-skill collision"
fi

HOME_FOUR="$TEST_TMP/home-four"
env \
    HOME="$HOME_FOUR" \
    DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
    DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
    DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
    DTVM_WORKTREE_INIT_USE_GIT_MIRRORS=0 \
    bash "$REPO_DIR/worktree-init.sh" --minimal "$ODD_WORKTREE" >/dev/null
assert_link "$HOME_FOUR/.agents/skills/active-one" "$ACTIVE_ROOT/active-one"
assert_link "$HOME_FOUR/.claude/skills/active-one" "$ACTIVE_ROOT/active-one"
[ -L "$ODD_WORKTREE/AGENTS.md" ] || fail "worktree-init did not link AGENTS.md"

# Removing a worktree prunes only its generated exact-path disables.
git -C "$FAKE_DTVM" worktree remove --force "$ODD_WORKTREE"
git -C "$FAKE_DTVM" worktree remove --force "$CONTROL_WORKTREE"
run_skills sync >/dev/null
[ "$(grep -c 'enabled = false' "$CONFIG_ONE")" -eq 2 ] ||
    fail "removed worktree entries were not pruned"
if grep -Fq 'worktree with' "$CONFIG_ONE"; then
    fail "removed worktree path remained in config"
fi
python3 - "$CONFIG_ONE" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert len(config["skills"]["config"]) == 2
PY

echo "PASS: agent skill integration"
