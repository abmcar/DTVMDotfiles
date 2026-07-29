#!/bin/bash

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HOOK_DIR/../.." && pwd)"

bash "$REPO_DIR/tests/profile_cold_compile_test.sh"
