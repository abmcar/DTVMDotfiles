#!/usr/bin/env bash

# Mark skills as managed to sync them through DTVMDotfiles.
# Use "external" for skills that are owned by another git workflow.
declare -Ag DTVM_SKILLS_MAP=(
    ["dmir-compiler-analysis"]="managed"
    ["dtvm-perf-profile"]="managed"
)
