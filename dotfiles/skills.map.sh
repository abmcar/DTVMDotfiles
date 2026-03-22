#!/usr/bin/env bash

# Mark skills as managed to sync them through DTVMDotfiles.
# Use "external" for skills that are owned by another git workflow.
# The current DTVM repo skills are tracked by git already, so they stay external here.
declare -Ag DTVM_SKILLS_MAP=(
    ["dmir-compiler-analysis"]="external"
    ["dtvm-perf-profile"]="external"
)
