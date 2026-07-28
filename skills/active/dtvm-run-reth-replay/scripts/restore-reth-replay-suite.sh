#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 install|sync|check TARGET_DIR" >&2
    exit 2
fi

mode="$1"
target_root="$2"
if [[ "${mode}" != "install" && "${mode}" != "sync" && "${mode}" != "check" ]]; then
    echo "usage: $0 install|sync|check TARGET_DIR" >&2
    exit 2
fi

skill_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="${skill_root}/assets/reth-replay-suite.sha256"
suite_assets="${skill_root}/assets/witness-db-suite"
expected_paths=(
    Cargo.lock
    Cargo.toml
    HA_RPC_OPERATIONS.md
    README.md
    capture-window.sh
    config/reth-rpc-ha.example.json
    config/reth-rpc-ha.schema.json
    fetch-witness.sh
    replay-tip.sh
    reth_rpc_ha.py
    src/bin/replay-block.rs
    src/bin/verify-witness.rs
    src/lib.rs
    src/replay.rs
    tests/capture-window-fake-curl.sh
    tests/capture-window-fake-fetch.sh
    tests/capture-window-fake-verify.sh
    tests/capture-window.sh
    tests/fake-curl.sh
    tests/fetch-witness.sh
    tests/proof_backed_block_diff.rs
    tests/proof_backed_diff.rs
    tests/proof_backed_system_block.rs
    tests/replay-tip-fake-curl.sh
    tests/replay-tip-fake-replay-block.sh
    tests/replay-tip.sh
    tests/replay_block_cli.rs
    tests/reth_rpc_ha_test.py
    tools/validate-replay-state.py
    verify.sh
)

if [[ ! -f "${manifest}" || -L "${manifest}" ]]; then
    echo "suite source manifest is missing or symlinked" >&2
    exit 1
fi
if [[ "$(realpath -e -- "${manifest}")" != "$(realpath -m -s -- "${manifest}")" ]]; then
    echo "suite source manifest has a symlinked ancestor" >&2
    exit 1
fi
if [[ -z "${target_root}" ]]; then
    echo "unsafe target directory" >&2
    exit 1
fi
target_root="$(realpath -m -s -- "${target_root}")"
invocation_root="$(realpath -m -s -- .)"
if [[ "${target_root}" == "/" || "${target_root}" == "${invocation_root}" ]]; then
    echo "unsafe target directory" >&2
    exit 1
fi
if [[ -L "${target_root}" ]]; then
    echo "target directory must not be a symlink" >&2
    exit 1
fi
if [[ "$(realpath -m -- "${target_root}")" != "${target_root}" ]]; then
    echo "target directory has a symlinked ancestor" >&2
    exit 1
fi
if [[ -e "${target_root}" ]]; then
    if [[ ! -d "${target_root}" ]]; then
        echo "target must be a directory" >&2
        exit 1
    fi
elif [[ "${mode}" != "install" ]]; then
    echo "target directory does not exist" >&2
    exit 1
fi
if [[ "${mode}" == "install" && -d "${target_root}" ]] &&
    find "${target_root}" -mindepth 1 -print -quit | grep -q .; then
    echo "install target must be absent or empty" >&2
    exit 1
fi

source_for() {
    local relative="$1"
    case "${relative}" in
        reth_rpc_ha.py)
            printf '%s\n' "${skill_root}/scripts/reth_rpc_ha.py"
            ;;
        tests/reth_rpc_ha_test.py)
            printf '%s\n' "${skill_root}/scripts/tests/reth_rpc_ha_test.py"
            ;;
        tools/validate-replay-state.py)
            printf '%s\n' "${skill_root}/scripts/validate-replay-state.py"
            ;;
        HA_RPC_OPERATIONS.md)
            printf '%s\n' "${skill_root}/references/HA_RPC_OPERATIONS.md"
            ;;
        config/reth-rpc-ha.example.json)
            printf '%s\n' "${skill_root}/assets/reth-rpc-ha.example.json"
            ;;
        config/reth-rpc-ha.schema.json)
            printf '%s\n' "${skill_root}/assets/reth-rpc-ha.schema.json"
            ;;
        *)
            printf '%s\n' "${suite_assets}/${relative}"
            ;;
    esac
}

validate_relative() {
    local relative="$1"
    if [[ -z "${relative}" || "${relative}" == /* ||
          "${relative}" == ".." || "${relative}" == ../* ||
          "${relative}" == */../* || "${relative}" == */.. ]]; then
        echo "unsafe path in suite manifest" >&2
        exit 1
    fi
}

validate_destination() {
    local relative="$1"
    local current="${target_root}"
    local component
    local -a components
    IFS="/" read -r -a components <<<"${relative}"
    for component in "${components[@]}"; do
        current="${current}/${component}"
        if [[ -L "${current}" ]]; then
            echo "target path contains a symlink" >&2
            exit 1
        fi
    done
}

is_expected_path() {
    local relative="$1"
    local candidate
    for candidate in "${expected_paths[@]}"; do
        if [[ "${relative}" == "${candidate}" ]]; then
            return 0
        fi
    done
    return 1
}

declare -A allowed_files=()
declare -A allowed_directories=()
for relative in "${expected_paths[@]}"; do
    allowed_files["${relative}"]=1
    parent="$(dirname -- "${relative}")"
    while [[ "${parent}" != "." ]]; do
        allowed_directories["${parent}"]=1
        parent="$(dirname -- "${parent}")"
    done
done
allowed_files[".dtvm-reth-suite.sha256"]=1

validate_target_tree() {
    local item
    local relative
    [[ -d "${target_root}" ]] || return 0
    while IFS= read -r -d '' item; do
        relative="${item#"${target_root}/"}"
        if [[ -L "${item}" ]]; then
            echo "target path contains a symlink" >&2
            exit 1
        fi
        if [[ -d "${item}" ]]; then
            if [[ -z "${allowed_directories["${relative}"]+present}" ]]; then
                echo "restored suite contains an unexpected directory" >&2
                exit 1
            fi
        elif [[ -f "${item}" ]]; then
            if [[ -z "${allowed_files["${relative}"]+present}" ]]; then
                echo "restored suite contains an unexpected file" >&2
                exit 1
            fi
        else
            echo "restored suite contains an unexpected file type" >&2
            exit 1
        fi
    done < <(find "${target_root}" -mindepth 1 -print0)
}

declare -A seen_paths=()
entries=0
while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    expected="${line%%  *}"
    relative="${line#*  }"
    if [[ ! "${expected}" =~ ^[0-9a-f]{64}$ || "${relative}" == "${line}" ]]; then
        echo "malformed suite source manifest" >&2
        exit 1
    fi
    validate_relative "${relative}"
    if ! is_expected_path "${relative}"; then
        echo "unexpected path in suite source manifest" >&2
        exit 1
    fi
    if [[ -n "${seen_paths["${relative}"]+present}" ]]; then
        echo "duplicate path in suite source manifest" >&2
        exit 1
    fi
    seen_paths["${relative}"]=1
    source_file="$(source_for "${relative}")"
    if [[ ! -f "${source_file}" || -L "${source_file}" ]]; then
        echo "manifest source is missing or symlinked: ${relative}" >&2
        exit 1
    fi
    if [[ "$(realpath -e -- "${source_file}")" != "$(realpath -m -s -- "${source_file}")" ]]; then
        echo "manifest source has a symlinked ancestor: ${relative}" >&2
        exit 1
    fi
    if [[ "$(sha256sum "${source_file}" | awk '{print $1}')" != "${expected}" ]]; then
        echo "manifest source checksum mismatch: ${relative}" >&2
        exit 1
    fi
    entries=$((entries + 1))
done <"${manifest}"
if [[ "${entries}" -ne "${#expected_paths[@]}" ]]; then
    echo "suite source manifest path set is incomplete" >&2
    exit 1
fi
for relative in "${expected_paths[@]}"; do
    if [[ -z "${seen_paths["${relative}"]+present}" ]]; then
        echo "suite source manifest path set is incomplete" >&2
        exit 1
    fi
done

if [[ "${mode}" == "install" ]]; then
    mkdir -p -- "${target_root}"
    if [[ "$(realpath -m -- "${target_root}")" != "${target_root}" ]]; then
        echo "target directory has a symlinked ancestor" >&2
        exit 1
    fi
fi
validate_target_tree

while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    expected="${line%%  *}"
    relative="${line#*  }"
    source_file="$(source_for "${relative}")"
    destination="${target_root}/${relative}"
    validate_destination "${relative}"
    if [[ "${mode}" != "check" ]]; then
        source_mode="$(stat -c '%a' "${source_file}")"
        install -D -m "${source_mode}" -- "${source_file}" "${destination}"
    fi
    source_mode="$(stat -c '%a' "${source_file}")"
    destination_mode="$(
        stat -c '%a' "${destination}" 2>/dev/null || printf missing
    )"
    if [[ ! -f "${destination}" || -L "${destination}" ]] ||
        ! cmp -s -- "${source_file}" "${destination}" ||
        [[ "${destination_mode}" != "${source_mode}" ]] ||
        [[ "$(sha256sum "${destination}" | awk '{print $1}')" != "${expected}" ]]; then
        echo "restored suite mismatch: ${relative}" >&2
        exit 1
    fi
done <"${manifest}"
validate_target_tree

target_manifest="${target_root}/.dtvm-reth-suite.sha256"
if [[ "${mode}" != "check" ]]; then
    install -m 0444 -- "${manifest}" "${target_manifest}"
fi
if [[ ! -f "${target_manifest}" || -L "${target_manifest}" ]] ||
    ! cmp -s -- "${manifest}" "${target_manifest}"; then
    echo "restored suite manifest mismatch" >&2
    exit 1
fi
validate_target_tree

printf 'DTVM-Reth suite %s verified: %s files at %s\n' \
    "${mode}" "${entries}" "${target_root}"
