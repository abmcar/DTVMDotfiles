#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
SKILL_FILE="$REPO_DIR/skills/active/dtvm-archive/SKILL.md"
METADATA_FILE="$REPO_DIR/skills/active/dtvm-archive/agents/openai.yaml"
MAP_FILE="$REPO_DIR/dotfiles/skills.map.sh"
GUIDE_FILE="$REPO_DIR/dotfiles/CLAUDE.md"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -Fqx 'name: dtvm-archive' "$SKILL_FILE" ||
    fail "skill name is not dtvm-archive"
grep -Fq 'Use only when the user explicitly asks' "$SKILL_FILE" ||
    fail "description does not require an explicit archive request"
grep -Fq 'never invoke automatically from dtvm-dev-workflow, dtvm-dev-cycle' "$SKILL_FILE" ||
    fail "description does not block automatic workflow invocation"
grep -Fq 'git mv "docs/changes/YYYY-MM-DD-<slug>"' "$SKILL_FILE" ||
    fail "skill does not define the local git mv boundary"
grep -Fq '"docs/_archive/<YYYY-MM>/<slug>"' "$SKILL_FILE" ||
    fail "skill does not use the exact DTVM archive destination"
if grep -Fq 'archive-YYYY-MM' "$SKILL_FILE"; then
    fail "skill adds an archive- prefix to the YYYY-MM directory"
fi
grep -Fq 'Do not update `docs/_archive/README.md`' "$SKILL_FILE" ||
    fail "skill does not prohibit archive index updates"
grep -Fqx '  allow_implicit_invocation: false' "$METADATA_FILE" ||
    fail "skill UI metadata permits implicit invocation"

(
    unset DTVM_SKILLS_MAP
    # shellcheck source=/dev/null
    source "$MAP_FILE"
    [ "${DTVM_SKILLS_MAP[archive]:-}" = "legacy-repo" ]
) || fail "legacy archive skill is not suppressed"

grep -Fq '**`dtvm-archive`**' "$GUIDE_FILE" ||
    fail "deployment guide does not route to dtvm-archive"
grep -Fq 'Completion of `dtvm-dev-workflow` or `dtvm-dev-cycle` is not an' "$GUIDE_FILE" ||
    fail "deployment guide does not preserve the explicit trigger boundary"
if grep -Fq 'use the `archive` skill' "$GUIDE_FILE"; then
    fail "deployment guide still routes work to the legacy archive skill"
fi

echo "DTVM archive skill tests passed."
