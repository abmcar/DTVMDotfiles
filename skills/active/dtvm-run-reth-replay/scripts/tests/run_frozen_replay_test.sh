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

verified_suite="${test_root}/verified-suite"
fake_bin="${test_root}/bin"
invocations="${test_root}/python-invocations.jsonl"
mkdir -- "${fake_bin}"
bash "${skill_root}/scripts/restore-reth-replay-suite.sh" \
    install "${verified_suite}" >/dev/null
{
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'jq -cn --args '\''$ARGS.positional'\'' -- "$@" >>"${DTVM_PYTHON_INVOCATIONS}"'
} >"${fake_bin}/python3"
chmod 700 "${fake_bin}/python3"

PATH="${fake_bin}:${PATH}" \
DTVM_PYTHON_INVOCATIONS="${invocations}" \
DTVM_RETH_SUITE_ROOT="${verified_suite}" \
RETH_RPC_HA_CONFIG="${config}" \
    bash "${skill_root}/scripts/run-frozen-replay.sh" readiness >/dev/null
jq -s -e \
    'length == 1 and
     .[0][-3:] == ["readiness", "--count", "16"]' \
    "${invocations}" >/dev/null

: >"${invocations}"
PATH="${fake_bin}:${PATH}" \
DTVM_PYTHON_INVOCATIONS="${invocations}" \
DTVM_RETH_SUITE_ROOT="${verified_suite}" \
RETH_RPC_HA_CONFIG="${config}" \
DTVM_RETH_START_BLOCK=25625000 \
DTVM_RETH_END_BLOCK=25625015 \
DTVM_RETH_BLOCK_COUNT=16 \
    bash "${skill_root}/scripts/run-frozen-replay.sh" readiness >/dev/null
jq -s -e \
    'length == 1 and
     .[0][-7:] == [
        "readiness",
        "--start-block", "25625000",
        "--end-block", "25625015",
        "--count", "16"
     ]' \
    "${invocations}" >/dev/null

: >"${invocations}"
PATH="${fake_bin}:${PATH}" \
DTVM_PYTHON_INVOCATIONS="${invocations}" \
DTVM_RETH_SUITE_ROOT="${verified_suite}" \
RETH_RPC_HA_CONFIG="${config}" \
DTVM_RETH_START_BLOCK=25625000 \
DTVM_RETH_END_BLOCK=25625015 \
DTVM_RETH_BLOCK_COUNT=16 \
DTVM_RETH_OUTPUT="${test_root}/corpus" \
DTVM_RETH_STATE_DIR="${test_root}/state" \
DTVM_IDENTITY_MANIFEST="${test_root}/identity.json" \
DTVM_REPLAYER_MANIFEST="${test_root}/replayer.json" \
    bash "${skill_root}/scripts/run-frozen-replay.sh" capture >/dev/null
jq -s -e \
    'length == 1 and
     (.[0] | index("capture")) != null and
     (.[0] | index("--start-block")) != null and
     (.[0] | index("25625000")) != null and
     (.[0] | index("--end-block")) != null and
     (.[0] | index("25625015")) != null and
     (.[0] | index("--count")) != null and
     (.[0] | index("16")) != null' \
    "${invocations}" >/dev/null

: >"${invocations}"
if PATH="${fake_bin}:${PATH}" \
    DTVM_PYTHON_INVOCATIONS="${invocations}" \
    DTVM_RETH_SUITE_ROOT="${verified_suite}" \
    RETH_RPC_HA_CONFIG="${config}" \
    DTVM_RETH_START_BLOCK=25625000 \
        bash "${skill_root}/scripts/run-frozen-replay.sh" readiness \
        >"${test_root}/one-sided.stdout" 2>"${test_root}/one-sided.stderr"; then
    echo "one-sided fixed range unexpectedly passed wrapper preflight" >&2
    exit 1
fi
test ! -s "${invocations}"
grep -Fq \
    "DTVM_RETH_START_BLOCK and DTVM_RETH_END_BLOCK must be set together" \
    "${test_root}/one-sided.stderr"

echo "run-frozen-replay regressions: 5/5"
