#!/usr/bin/env bash
set -euo pipefail

skill_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

suite_root="${test_root}/suite"
marker="${test_root}/tampered-client-executed"
config="${skill_root}/assets/reth-rpc-ha.example.json"

bash "${skill_root}/scripts/restore-reth-replay-suite.sh" \
    install "${suite_root}" >/dev/null
{
    printf '%s\n' \
        '#!/usr/bin/env python3' \
        'import os' \
        'from pathlib import Path' \
        'Path(os.environ["DTVM_TAMPER_MARKER"]).write_text("executed")' \
        'print("{}")'
} >"${suite_root}/reth_rpc_ha.py"
chmod 700 "${suite_root}/reth_rpc_ha.py"

if DTVM_RETH_SUITE_ROOT="${suite_root}" \
    RETH_RPC_HA_CONFIG="${config}" \
    DTVM_TAMPER_MARKER="${marker}" \
    bash "${skill_root}/scripts/run-frozen-replay.sh" readiness \
        >/dev/null 2>&1; then
    echo "tampered suite unexpectedly passed wrapper preflight" >&2
    exit 1
fi
if [[ -e "${marker}" ]]; then
    echo "tampered HA client executed before manifest verification" >&2
    exit 1
fi

echo "run-frozen-replay regressions: 1/1"
