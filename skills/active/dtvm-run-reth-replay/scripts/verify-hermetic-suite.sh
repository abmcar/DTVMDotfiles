#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: $0 RESTORED_SUITE_DIR" >&2
    exit 2
fi

suite_root="$(realpath -m -s -- "$1")"
skill_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ ! -d "${suite_root}" || -L "${suite_root}" ||
      "$(realpath -m -- "${suite_root}")" != "${suite_root}" ]]; then
    echo "restored suite directory is missing or symlinked" >&2
    exit 1
fi

export PYTHONDONTWRITEBYTECODE=1
export DTVM_REPLAY_STATE_VALIDATOR="${DTVM_REPLAY_STATE_VALIDATOR:-${suite_root}/tools/validate-replay-state.py}"

bash "${skill_root}/scripts/tests/restore_reth_replay_suite_test.sh"
bash "${skill_root}/scripts/tests/run_frozen_replay_test.sh"
python3 "${skill_root}/scripts/tests/validate_replay_state_test.py"
python3 "${suite_root}/tests/reth_rpc_ha_test.py"
bash "${suite_root}/tests/fetch-witness.sh"
bash "${suite_root}/tests/capture-window.sh"
bash "${suite_root}/tests/replay-tip.sh"

if find "${suite_root}" \
    \( -type d -name __pycache__ -o -type f -name '*.pyc' \) \
    -print -quit | grep -q .; then
    echo "hermetic verification generated Python bytecode" >&2
    exit 1
fi

echo "DTVM-Reth restored Python/shell adapter checks: PASS"
