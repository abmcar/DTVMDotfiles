#!/usr/bin/env bash

# Documentation-only: records which .agents/skills/ entries are tracked
# by the upstream DTVM repo. Skills formerly marked "managed" have been
# migrated to .claude/rules/ and .claude/commands/ (synced via MIRRORED_ITEMS).
declare -Ag DTVM_SKILLS_MAP=(
    ["dmir-compiler-analysis"]="external"
    ["dtvm-perf-profile"]="external"
)
