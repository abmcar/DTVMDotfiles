#!/bin/bash

set -euo pipefail

SKILL_DIR="${1:?skill directory is required}"
COMPARATOR_TEST="$SKILL_DIR/scripts/test_compare_paired_identity.py"
CONTRACT_TEST="$SKILL_DIR/scripts/test_skill_contract.py"

if [ ! -d "$SKILL_DIR/scripts" ]; then
    exit 0
fi
for test_path in "$COMPARATOR_TEST" "$CONTRACT_TEST"; do
    if [ ! -f "$test_path" ] || [ -L "$test_path" ]; then
        echo "Error: Compile-time optimizer test is missing: $test_path" >&2
        exit 1
    fi
done

PYTHONDONTWRITEBYTECODE=1 python3 "$COMPARATOR_TEST"
PYTHONDONTWRITEBYTECODE=1 python3 "$CONTRACT_TEST"
