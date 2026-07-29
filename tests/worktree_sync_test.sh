#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
CHANGE_DOC="$REPO_DIR/docs/changes/2026-07-28-worktree-managed-content/README.md"
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

[ "$(grep -Ec '^- \*\*Status\*\*: ' "$CHANGE_DOC")" -eq 1 ] ||
    fail "worktree change doc must declare exactly one status"
grep -Fqx -- '- **Status**: Accepted' "$CHANGE_DOC" ||
    fail "unmerged worktree change doc must remain Accepted"
if grep -Fqx -- '- **Status**: Implemented' "$CHANGE_DOC"; then
    fail "unmerged worktree change doc must not be Implemented"
fi

FAKE_DTVM="$TEST_TMP/dtvm"
WORKTREE="$TEST_TMP/worktree"
HOME_INIT="$TEST_TMP/home"
ACTIVE_ROOT="$TEST_TMP/source/skills/active"
MAP_FILE="$TEST_TMP/skills.map.sh"
TRACKED_SKILL_REL=".claude/skills/legacy-skill/SKILL.md"

mkdir -p \
    "$FAKE_DTVM/$(dirname "$TRACKED_SKILL_REL")" \
    "$ACTIVE_ROOT/active-one"
printf '%s\n' 'tracked agents' > "$FAKE_DTVM/AGENTS.md"
printf '%s\n' 'tracked skill' > "$FAKE_DTVM/$TRACKED_SKILL_REL"
printf '%s\n' '---' 'name: active-one' 'description: test' '---' \
    > "$ACTIVE_ROOT/active-one/SKILL.md"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'declare -Ag DTVM_SKILLS_MAP=(' \
    '    ["legacy-skill"]="legacy-repo"' \
    ')' > "$MAP_FILE"

git -C "$FAKE_DTVM" init -q
git -C "$FAKE_DTVM" config user.name test
git -C "$FAKE_DTVM" config user.email test@example.com
git -C "$FAKE_DTVM" add AGENTS.md "$TRACKED_SKILL_REL"
git -C "$FAKE_DTVM" commit -qm 'tracked managed paths'
git -C "$FAKE_DTVM" worktree add -q -b test-worktree "$WORKTREE"

# Model a normal release: the main checkout gets the deterministic AGENTS.md
# adapter and is dirty relative to DTVM HEAD. The clean worktree still holds
# the committed version. Main-checkout .claude/skills drift is not authoritative
# for the target branch and must not block initialization.
cp "$REPO_DIR/dotfiles/CLAUDE.md" "$FAKE_DTVM/AGENTS.md"
printf '%s\n' 'main checkout skill drift' \
    > "$FAKE_DTVM/$TRACKED_SKILL_REL"
[ "$(git -C "$FAKE_DTVM" status --short -- AGENTS.md)" = " M AGENTS.md" ] ||
    fail "release-state fixture did not produce a dirty main AGENTS.md"
[ -z "$(git -C "$WORKTREE" status --short -- AGENTS.md .claude/skills)" ] ||
    fail "release-state fixture did not leave the worktree clean"
if cmp -s "$FAKE_DTVM/AGENTS.md" "$WORKTREE/AGENTS.md"; then
    fail "release-state fixture did not preserve distinct main/worktree bytes"
fi

# These main-checkout-only sources must become exact absolute links.
printf '%s\n' 'claude source' > "$FAKE_DTVM/CLAUDE.md"
mkdir -p "$FAKE_DTVM/.claude"
printf '%s\n' '{}' > "$FAKE_DTVM/.claude/settings.json"
mkdir -p "$WORKTREE/evmc/include"

run_init() {
    env \
        HOME="$HOME_INIT" \
        DTVMDOTFILES_PARENT_DIR="$FAKE_DTVM" \
        DTVMDOTFILES_ACTIVE_SKILLS_DIR="$ACTIVE_ROOT" \
        DTVMDOTFILES_SKILLS_MAP_FILE="$MAP_FILE" \
        DTVM_WORKTREE_INIT_USE_GIT_MIRRORS=0 \
        bash "$REPO_DIR/worktree-init.sh" --minimal "$WORKTREE"
}

run_init >/dev/null
[ ! -L "$WORKTREE/AGENTS.md" ] ||
    fail "tracked AGENTS.md was replaced with a symlink"
[ ! -L "$WORKTREE/.claude/skills" ] ||
    fail "tracked .claude/skills was replaced with a symlink"
cmp -s "$WORKTREE/AGENTS.md" "$REPO_DIR/dotfiles/CLAUDE.md" ||
    fail "tracked AGENTS.md was not generated from DTVMDotfiles"
[ "$(git -C "$WORKTREE" status --short -- AGENTS.md)" = " M AGENTS.md" ] ||
    fail "generated worktree AGENTS.md was not retained as a derived diff"
grep -Fqx 'tracked skill' "$WORKTREE/$TRACKED_SKILL_REL" ||
    fail "main-checkout skill drift changed the target branch content"
[ -z "$(git -C "$WORKTREE" status --short -- .claude/skills)" ] ||
    fail "tracked .claude/skills was not kept clean"
assert_link "$WORKTREE/CLAUDE.md" "$FAKE_DTVM/CLAUDE.md"
assert_link \
    "$WORKTREE/.claude/settings.json" \
    "$FAKE_DTVM/.claude/settings.json"
run_init >/dev/null

# A late collision is discovered before any newly managed path is written.
printf '%s\n' 'gemini source' > "$FAKE_DTVM/GEMINI.md"
printf '%s\n' 'tampered main agents' > "$FAKE_DTVM/AGENTS.md"
if run_init >/dev/null 2>&1; then
    fail "worktree-init accepted non-generated main AGENTS.md drift"
fi
[ ! -e "$WORKTREE/GEMINI.md" ] ||
    fail "main AGENTS.md collision was detected after worktree writes"
grep -Fqx 'tampered main agents' "$FAKE_DTVM/AGENTS.md" ||
    fail "failed main AGENTS.md preflight changed the tampered file"
cp "$REPO_DIR/dotfiles/CLAUDE.md" "$FAKE_DTVM/AGENTS.md"

printf '%s\n' 'tampered worktree agents' > "$WORKTREE/AGENTS.md"
if run_init >/dev/null 2>&1; then
    fail "worktree-init accepted non-generated AGENTS.md drift"
fi
[ ! -e "$WORKTREE/GEMINI.md" ] ||
    fail "tracked collision was detected after worktree writes"
grep -Fqx 'tampered worktree agents' "$WORKTREE/AGENTS.md" ||
    fail "failed AGENTS.md preflight changed the tampered file"
cp "$REPO_DIR/dotfiles/CLAUDE.md" "$WORKTREE/AGENTS.md"

printf '%s\n' 'tampered worktree skill' > "$WORKTREE/$TRACKED_SKILL_REL"
if run_init >/dev/null 2>&1; then
    fail "worktree-init accepted dirty tracked .claude/skills"
fi
grep -Fqx 'tampered worktree skill' "$WORKTREE/$TRACKED_SKILL_REL" ||
    fail "failed skill preflight changed the tampered file"

echo "PASS: worktree sync"
