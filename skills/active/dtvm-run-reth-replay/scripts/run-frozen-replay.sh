#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
if [[ "$#" -ne 1 ]] ||
   [[ "${mode}" != "readiness" &&
      "${mode}" != "capture" &&
      "${mode}" != "replay" &&
      "${mode}" != "seal" &&
      "${mode}" != "all" ]]; then
    echo "usage: $0 readiness|capture|replay|seal|all" >&2
    exit 2
fi

suite_root="${DTVM_RETH_SUITE_ROOT:-}"
config="${RETH_RPC_HA_CONFIG:-}"
if [[ -z "${suite_root}" || ! -f "${suite_root}/reth_rpc_ha.py" ]]; then
    echo "DTVM_RETH_SUITE_ROOT must contain reth_rpc_ha.py" >&2
    exit 2
fi
if [[ -z "${config}" || ! -f "${config}" ]]; then
    echo "RETH_RPC_HA_CONFIG must name the secret-free config" >&2
    exit 2
fi

skill_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
bash "${skill_root}/scripts/restore-reth-replay-suite.sh" \
    check "${suite_root}" >/dev/null

export PYTHONDONTWRITEBYTECODE=1

selection_arguments() {
    local start="${DTVM_RETH_START_BLOCK:-}"
    local end="${DTVM_RETH_END_BLOCK:-}"
    local count="${DTVM_RETH_BLOCK_COUNT:-16}"
    if [[ (-n "${start}" && -z "${end}") ||
          (-z "${start}" && -n "${end}") ]]; then
        echo "DTVM_RETH_START_BLOCK and DTVM_RETH_END_BLOCK must be set together" >&2
        return 2
    fi
    if [[ -n "${start}" ]]; then
        printf '%s\n' \
            --start-block "${start}" \
            --end-block "${end}" \
            --count "${count}"
    else
        printf '%s\n' --count "${count}"
    fi
}

run_readiness() {
    local -a selection
    local selection_output
    selection_output="$(selection_arguments)" || return
    mapfile -t selection <<<"${selection_output}"
    python3 "${suite_root}/reth_rpc_ha.py" \
        --config "${config}" \
        readiness \
        "${selection[@]}"
}

require_capture_inputs() {
    : "${DTVM_RETH_OUTPUT:?set DTVM_RETH_OUTPUT}"
    : "${DTVM_RETH_STATE_DIR:?set DTVM_RETH_STATE_DIR}"
    : "${DTVM_IDENTITY_MANIFEST:?set DTVM_IDENTITY_MANIFEST}"
    : "${DTVM_REPLAYER_MANIFEST:?set DTVM_REPLAYER_MANIFEST}"
}

run_capture() {
    require_capture_inputs
    local -a selection
    local selection_output
    selection_output="$(selection_arguments)" || return
    mapfile -t selection <<<"${selection_output}"
    python3 "${suite_root}/reth_rpc_ha.py" \
        --config "${config}" \
        capture \
        "${selection[@]}" \
        --capture-attempts "${DTVM_RETH_CAPTURE_ATTEMPTS:-3}" \
        --output "${DTVM_RETH_OUTPUT}" \
        --state-dir "${DTVM_RETH_STATE_DIR}" \
        --dtvm-identity-manifest "${DTVM_IDENTITY_MANIFEST}" \
        --replayer-manifest "${DTVM_REPLAYER_MANIFEST}"
}

require_replay_inputs() {
    : "${DTVM_RETH_STATE_DIR:?set DTVM_RETH_STATE_DIR}"
    : "${DTVM_VERIFY_CORPUS_SCRIPT:?set DTVM_VERIFY_CORPUS_SCRIPT}"
    : "${DTVM_VERIFY_CORPUS_SHA256:?set DTVM_VERIFY_CORPUS_SHA256}"
    : "${DTVM_LIBRARY:?set DTVM_LIBRARY}"
    : "${DTVM_LIBRARY_SHA256:?set DTVM_LIBRARY_SHA256}"
    : "${DTVM_REPLAY_OUTPUT:?set DTVM_REPLAY_OUTPUT}"
    : "${DTVM_REPLAY_LABEL:?set DTVM_REPLAY_LABEL}"
}

run_replay() {
    require_replay_inputs
    python3 "${suite_root}/reth_rpc_ha.py" \
        --config "${config}" \
        replay \
        --state-dir "${DTVM_RETH_STATE_DIR}" \
        --verify-corpus-script "${DTVM_VERIFY_CORPUS_SCRIPT}" \
        --verify-corpus-sha256 "${DTVM_VERIFY_CORPUS_SHA256}" \
        --dtvm-library "${DTVM_LIBRARY}" \
        --dtvm-library-sha256 "${DTVM_LIBRARY_SHA256}" \
        --replay-output "${DTVM_REPLAY_OUTPUT}" \
        --label "${DTVM_REPLAY_LABEL}"
}

run_seal() {
    : "${DTVM_RETH_STATE_DIR:?set DTVM_RETH_STATE_DIR}"
    python3 "${suite_root}/reth_rpc_ha.py" \
        --config "${config}" \
        seal \
        --state-dir "${DTVM_RETH_STATE_DIR}"
}

case "${mode}" in
    readiness)
        run_readiness
        ;;
    capture)
        run_capture
        ;;
    replay)
        run_replay
        ;;
    seal)
        run_seal
        ;;
    all)
        run_readiness
        run_capture
        run_replay
        run_seal
        ;;
esac
