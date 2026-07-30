#!/bin/bash

set -euo pipefail

SKILL_DIR="${1:?skill directory is required}"
TEST_DIR="$SKILL_DIR/scripts/tests"
CONTRACT_TEST="$TEST_DIR/test_validate_replay_perf_contract.py"
RESULTS_TEST="$TEST_DIR/test_validate_replay_perf_results.py"

for test_path in "$CONTRACT_TEST" "$RESULTS_TEST"; do
    if [ ! -f "$test_path" ] || [ -L "$test_path" ]; then
        echo "Error: Replay performance test is missing: $test_path" >&2
        exit 1
    fi
done

PYTHONDONTWRITEBYTECODE=1 python3 "$CONTRACT_TEST"
PYTHONDONTWRITEBYTECODE=1 python3 "$RESULTS_TEST"
