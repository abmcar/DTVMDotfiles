#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
SKILL_DIR="$REPO_DIR/skills/active/dtvm-dev-cycle"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Discovery uses the same active-skill collector as skills.sh.
# shellcheck source=lib/agent_skills.sh
source "$REPO_DIR/lib/agent_skills.sh"
declare -a active_names=()
agentSkillsCollectActive active_names
printf '%s\n' "${active_names[@]}" | grep -Fqx dtvm-dev-cycle ||
    fail "dtvm-dev-cycle is not discoverable from skills/active"

grep -Fqx '  allow_implicit_invocation: false' \
    "$SKILL_DIR/agents/openai.yaml" ||
    fail "dtvm-dev-cycle is not explicitly opt-in"
grep -Fq 'Use $dtvm-dev-cycle' "$SKILL_DIR/agents/openai.yaml" ||
    fail "skill metadata does not invoke dtvm-dev-cycle by name"
grep -Fq 'policy.allow_implicit_invocation: false' "$SKILL_DIR/SKILL.md" ||
    fail "skill does not explain its project-routing opt-in mechanism"

# Lock the DTVM-specific lifecycle contract.
grep -Fq 'docs/changes/YYYY-MM-DD-<slug>/README.md' "$SKILL_DIR/SKILL.md" ||
    fail "change documents are not rooted in docs/changes"
grep -Fq 'Delegate every `src/**` modification to `compiler-agent`' \
    "$SKILL_DIR/SKILL.md" ||
    fail "src ownership is not delegated to compiler-agent"
for gate in \
    'tools/format.sh check' \
    'cmake --build build --target <relevant_target>' \
    'tools/dtvm_local_test.sh --auto'
do
    grep -Fq "$gate" "$SKILL_DIR/SKILL.md" ||
        fail "missing quality gate: $gate"
done
grep -Fq 'Do not automatically commit, archive, push' "$SKILL_DIR/SKILL.md" ||
    fail "local handoff boundary is missing"
grep -Fq 'Keep the change document at `Accepted` throughout local handoff' \
    "$SKILL_DIR/SKILL.md" ||
    fail "local verification does not preserve Accepted status"
grep -Fq 'Only after that merge is verified' "$SKILL_DIR/SKILL.md" ||
    fail "Implemented status is not gated on merge"
grep -Fq 'use `$dtvm-archive`' "$SKILL_DIR/SKILL.md" ||
    fail "post-merge routing does not use dtvm-archive"

# The checked-in Claude source is the exact AGENTS/GEMINI adapter source.
mkdir -p "$TEST_TMP/dtvm"
(
    DTVMDOTFILES_PARENT_DIR="$TEST_TMP/dtvm"
    export DTVMDOTFILES_PARENT_DIR
    # shellcheck source=lib/sync_common.sh
    source "$REPO_DIR/lib/sync_common.sh"
    syncClaudeAliases >/dev/null
)
cmp -s "$REPO_DIR/dotfiles/CLAUDE.md" "$TEST_TMP/dtvm/AGENTS.md" ||
    fail "AGENTS adapter differs from the CLAUDE source"
cmp -s "$REPO_DIR/dotfiles/CLAUDE.md" "$TEST_TMP/dtvm/GEMINI.md" ||
    fail "GEMINI adapter differs from the CLAUDE source"

for adapter in \
    "$REPO_DIR/dotfiles/CLAUDE.md" \
    "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md"
do
    grep -Fq 'dtvm-dev-cycle' "$adapter" ||
        fail "adapter does not route to dtvm-dev-cycle: $adapter"
    if grep -Fq '~/claude-sync/skills/dev-cycle/' "$adapter"; then
        fail "adapter still routes to the missing claude-sync skill: $adapter"
    fi
done

CLAUDE_SOURCE="$REPO_DIR/dotfiles/CLAUDE.md"
grep -Fq 'Project routing must explicitly select `$dtvm-dev-cycle`' \
    "$CLAUDE_SOURCE" ||
    fail "project routing does not select dtvm-dev-cycle for qualifying work"
grep -Fq 'Ordinary improvements and routine fixes stay on' "$CLAUDE_SOURCE" &&
    grep -Fq '`dtvm-dev-workflow`' "$CLAUDE_SOURCE" ||
    fail "ordinary improvements and routine fixes do not remain on dtvm-dev-workflow"

legacy_archive='$'"archive"
for contract_file in \
    "$SKILL_DIR/SKILL.md" \
    "$REPO_DIR/dotfiles/CLAUDE.md" \
    "$REPO_DIR/dotfiles/.claude/agents/doc-agent.md"
do
    grep -Fq '$dtvm-archive' "$contract_file" ||
        fail "contract does not route archival to dtvm-archive: $contract_file"
    if grep -Fq "$legacy_archive" "$contract_file"; then
        fail "legacy archive invocation remains: $contract_file"
    fi
done

echo "PASS: dtvm-dev-cycle discovery and adapters"
