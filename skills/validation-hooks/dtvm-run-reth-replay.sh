#!/bin/bash

set -euo pipefail

SKILL_DIR="${1:?skill directory is required}"
RESTORE="$SKILL_DIR/scripts/restore-reth-replay-suite.sh"
VERIFY="$SKILL_DIR/scripts/verify-hermetic-suite.sh"

if [ ! -d "$SKILL_DIR/scripts" ]; then
    exit 0
fi
if [ ! -f "$RESTORE" ] || [ -L "$RESTORE" ] ||
    [ ! -f "$VERIFY" ] || [ -L "$VERIFY" ]; then
    echo "Error: Reth replay restore or hermetic verification script is missing" >&2
    exit 1
fi

SCRATCH="$(mktemp -d)"
trap 'chmod -R u+w -- "$SCRATCH" 2>/dev/null || true; rm -rf -- "$SCRATCH"' EXIT
SUITE="$SCRATCH/reth-replay-suite"

bash "$RESTORE" install "$SUITE" >/dev/null
bash "$RESTORE" check "$SUITE" >/dev/null
PYTHONDONTWRITEBYTECODE=1 bash "$VERIFY" "$SUITE"
