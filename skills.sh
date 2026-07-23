#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sync_common.sh
source "$SCRIPT_DIR/lib/sync_common.sh"

case "${1:-}" in
    check)
        checkAgentSkills "$PARENT_DIR"
        echo "✓ Agent skills are current"
        ;;
    sync)
        syncAgentSkills "$PARENT_DIR"
        echo "✓ Agent skills synchronized"
        ;;
    *)
        echo "Usage: bash DTVMDotfiles/skills.sh {check|sync}" >&2
        exit 2
        ;;
esac
