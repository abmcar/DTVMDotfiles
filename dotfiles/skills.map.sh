#!/usr/bin/env bash

# Mark skills as managed to sync them through DTVMDotfiles.
# Managed skills are also auto-added to the parent .git/info/exclude.
# Use "external" for skills that are owned by another git workflow.
# Skills already tracked in the DTVM repo stay external here.
# Local DTVM skills that are ignored by the main repo should be managed here.
declare -Ag DTVM_SKILLS_MAP=(
    ["dtvm-dotfiles-usage"]="managed"
    ["dmir-compiler-analysis"]="external"
    ["dtvm-build-config"]="managed"
    ["dtvm-evmone-benchmark"]="managed"
    ["dtvm-jit-lowering-inspection"]="managed"
    ["dtvm-perf-profile"]="external"
    ["dtvm-perf-worktree-lab"]="managed"
)
