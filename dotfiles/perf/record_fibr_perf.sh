#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DTVM_BIN="${REPO_ROOT}/build/dtvm"
EVM_HEX="${SCRIPT_DIR}/fibr.evm.hex"

# Default mode is interpreter.
MODE="${1:-interpreter}"
case "${MODE}" in
  multipass|interpreter) ;;
  *)
    echo "Usage: $(basename "$0") [multipass|interpreter]" >&2
    exit 1
    ;;
esac

exec perf record -g -- "${DTVM_BIN}" --format evm -m "${MODE}" "${EVM_HEX}" \
  --gas-limit 0xFFFFFFFFFFFF \
  --calldata c6c2ea170000000000000000000000000000000000000000000000000000000000080003 \
  --enable-statistics

