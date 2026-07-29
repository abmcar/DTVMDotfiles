#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" ||
        fail "$path does not route through $text"
}

assert_absent() {
    local path="$1"
    local text="$2"
    if grep -Fq -- "$text" "$path"; then
        fail "$path still contains legacy routing: $text"
    fi
}

assert_absent_regex() {
    local path="$1"
    local pattern="$2"
    if grep -Eq -- "$pattern" "$path"; then
        fail "$path still matches legacy routing: $pattern"
    fi
}

PERF_AGENT="$REPO_DIR/dotfiles/.claude/agents/perf-agent.md"
COMPILER_AGENT="$REPO_DIR/dotfiles/.claude/agents/compiler-agent.md"
PERF_LAB="$REPO_DIR/dotfiles/.claude/rules/dtvm-perf-worktree-lab.md"
BENCH_COMPARE="$REPO_DIR/dotfiles/.claude/commands/bench-compare.md"
DOTFILES_COMMAND="$REPO_DIR/dotfiles/.claude/commands/dotfiles.md"
WORKTREE_HOOK="$REPO_DIR/dotfiles/.claude/hooks/agent-worktree-bootstrap.sh"
LOCAL_TEMPLATE="$REPO_DIR/dotfiles/CLAUDE.local.md.template"
RETIRED_SKILL="$REPO_DIR/skills/retired/dtvm-perf-profile/SKILL.md"

for replacement in \
    '$dtvm-cold-compile-profile' \
    '$dtvm-compiler-path-analysis' \
    '$dtvm-compile-time-optimize' \
    '$dtvm-worktree-bootstrap'; do
    assert_contains "$PERF_AGENT" "$replacement"
done

for source in \
    "$PERF_AGENT" \
    "$COMPILER_AGENT" \
    "$PERF_LAB" \
    "$BENCH_COMPARE"; do
    assert_absent "$source" '.agents/skills/dtvm-perf-profile'
    assert_absent "$source" '.agents/skills/dmir-compiler-analysis'
    assert_absent "$source" 'git worktree add "$'
    assert_absent "$source" 'git worktree add .worktrees/'
    assert_absent "$source" 'rm -rf <path>'
    assert_absent "$source" 'rm -rf "$BASE_WT"'
    assert_absent "$source" 'git worktree prune'
    assert_absent "$source" '.worktrees/baseline-main'
    assert_absent "$source" '~/dtvm-baseline'
    assert_absent_regex "$source" \
        '(^|[^[:alnum:]-])worktree-bootstrap([^[:alnum:]-]|$)'
done

assert_contains "$PERF_LAB" '$dtvm-worktree-bootstrap'
assert_contains "$BENCH_COMPARE" '$dtvm-worktree-bootstrap'
assert_contains "$COMPILER_AGENT" '$dtvm-compiler-path-analysis'
assert_contains "$COMPILER_AGENT" '$dtvm-worktree-bootstrap'
assert_contains "$DOTFILES_COMMAND" '$dtvm-worktree-bootstrap'
assert_contains "$WORKTREE_HOOK" '$dtvm-worktree-bootstrap'
assert_contains "$PERF_AGENT" 'git worktree remove --force <path>'
assert_contains "$COMPILER_AGENT" 'git worktree remove --force <path>'
assert_contains "$PERF_LAB" 'git worktree remove --force <path>'
assert_contains "$BENCH_COMPARE" 'git worktree remove --force "$BASE_WT"'
assert_absent "$LOCAL_TEMPLATE" '~/dtvm-baseline'

[ -f "$RETIRED_SKILL" ] || fail "missing retired historical reference"
[ ! -e "$REPO_DIR/skills/active/dtvm-perf-profile" ] ||
    fail "legacy profiling skill was re-enabled under skills/active"

(
    unset DTVM_SKILLS_MAP
    # shellcheck source=/dev/null
    source "$REPO_DIR/dotfiles/skills.map.sh"
    [ "${DTVM_SKILLS_MAP[dtvm-perf-profile]:-}" = "legacy-repo" ] ||
        fail "static Codex suppression for dtvm-perf-profile was removed"
)

python3 - "$REPO_DIR/dotfiles/.claude/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as settings_file:
    settings = json.load(settings_file)
overrides = settings.get("skillOverrides")
if overrides is not None:
    assert overrides["dtvm-perf-profile"] == "off"
PY

echo "PASS: delegated perf workflow uses current replacements"
