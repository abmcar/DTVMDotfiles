#!/usr/bin/env bash

# SSOT for repository-owned skills suppressed by name in Codex and Claude Code.
# `bash skills.sh sync` renders both client adapters from this map.
declare -Ag DTVM_SKILLS_MAP=(
    ["archive"]="legacy-repo"
    ["dev-workflow"]="legacy-repo"
    ["dmir-compiler-analysis"]="legacy-repo"
    ["dtvm-perf-profile"]="legacy-repo"
)
