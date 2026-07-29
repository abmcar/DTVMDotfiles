#!/bin/bash

set -euo pipefail

SKILL_DIR="${1:?skill directory is required}"

python3 "$SKILL_DIR/scripts/test_lint_report.py"
