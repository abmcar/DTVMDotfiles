#!/usr/bin/env bash

# Repository-owned skills suppressed in every worktree in Codex config.
declare -Ag DTVM_SKILLS_MAP=(
    ["dmir-compiler-analysis"]="legacy-repo"
    ["dtvm-perf-profile"]="legacy-repo"
)
