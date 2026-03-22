#!/usr/bin/env bash

# Mark skills as managed to sync them through DTVMDotfiles.
# Managed skills are also auto-added to the parent .git/info/exclude.
# Use "external" for skills that are owned by another git workflow.
# The current DTVM repo skills are tracked by git already, so they stay external here.
declare -Ag DTVM_SKILLS_MAP=(
    ["dmir-compiler-analysis"]="external"
    ["dtvm-perf-profile"]="external"
)
