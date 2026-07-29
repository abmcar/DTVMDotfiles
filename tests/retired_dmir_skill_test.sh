#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
LEGACY_SKILL="dmir-compiler-analysis"
REPLACEMENT_SKILL="dtvm-compiler-path-analysis"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

unset DTVM_SKILLS_MAP
# shellcheck source=/dev/null
source "$REPO_DIR/dotfiles/skills.map.sh"

[ "${DTVM_SKILLS_MAP[$LEGACY_SKILL]:-}" = "legacy-repo" ] ||
    fail "Codex suppression map lost $LEGACY_SKILL"

rg -qF "\`$LEGACY_SKILL\` skills are historical artifacts" \
    "$REPO_DIR/dotfiles/CLAUDE.md" ||
    fail "Claude project policy lost $LEGACY_SKILL"
rg -qF "Do not invoke them" "$REPO_DIR/dotfiles/CLAUDE.md" ||
    fail "Claude project policy no longer disables legacy workflow entry"

[ -f "$REPO_DIR/skills/retired/$LEGACY_SKILL/SKILL.md" ] ||
    fail "retired skill record is missing"
[ ! -e "$REPO_DIR/skills/active/$LEGACY_SKILL" ] ||
    fail "legacy skill is still active"
[ -f "$REPO_DIR/skills/active/$REPLACEMENT_SKILL/SKILL.md" ] ||
    fail "replacement skill is not active"

if rg -nF ".agents/skills/$LEGACY_SKILL" \
    "$REPO_DIR/dotfiles/.claude/agents" \
    "$REPO_DIR/dotfiles/CLAUDE.md" >/dev/null; then
    fail "a delegated workflow still reads the legacy skill entry"
fi

rg -qF "$REPLACEMENT_SKILL" \
    "$REPO_DIR/dotfiles/.claude/agents/compiler-agent.md" ||
    fail "compiler-agent does not route to the replacement"
rg -qF "$REPLACEMENT_SKILL" \
    "$REPO_DIR/dotfiles/.claude/agents/perf-agent.md" ||
    fail "perf-agent does not route to the replacement"
rg -qF "$REPLACEMENT_SKILL" "$REPO_DIR/dotfiles/CLAUDE.md" ||
    fail "AGENTS deployment source does not route to the replacement"

echo "PASS: retired dMIR skill policy and routing"
