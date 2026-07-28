#!/usr/bin/env bash
set -euo pipefail

skill_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
restore="${skill_root}/scripts/restore-reth-replay-suite.sh"
scratch="$(mktemp -d)"
trap 'chmod -R u+w -- "${scratch}" 2>/dev/null || true; rm -rf -- "${scratch}"' EXIT

expect_failure_category() {
    local expected="$1"
    shift
    local log="${scratch}/expected-failure.log"
    if "$@" >"${scratch}/unexpected-success.log" 2>"${log}"; then
        echo "expected restore command to fail" >&2
        exit 1
    fi
    if ! grep -Fq -- "${expected}" "${log}"; then
        echo "restore command failed with the wrong category" >&2
        sed -n '1,5p' "${log}" >&2
        exit 1
    fi
}

baseline="${scratch}/baseline"
bash "${restore}" install "${baseline}" >/dev/null
bash "${restore}" check "${baseline}" >/dev/null

touch "${baseline}/build.rs"
expect_failure_category \
    "unexpected file" \
    bash "${restore}" check "${baseline}"
before="$(sha256sum "${baseline}/Cargo.lock" | awk '{print $1}')"
expect_failure_category \
    "unexpected file" \
    bash "${restore}" sync "${baseline}"
after="$(sha256sum "${baseline}/Cargo.lock" | awk '{print $1}')"
[[ "${before}" == "${after}" ]]

physical_target="${scratch}/physical-target"
mkdir "${physical_target}"
ln -s "${physical_target}" "${scratch}/target-alias"
expect_failure_category \
    "symlinked ancestor" \
    bash "${restore}" install "${scratch}/target-alias/new-suite"
[[ ! -e "${physical_target}/new-suite" ]]

expect_failure_category \
    "unsafe target directory" \
    bash -c 'cd "$1" && bash "$2" check ./' _ "${scratch}" "${restore}"
expect_failure_category \
    "unsafe target directory" \
    bash "${restore}" check /tmp/..

manifest_copy="${scratch}/manifest-copy"
cp -a -- "${skill_root}" "${manifest_copy}"
manifest="${manifest_copy}/assets/reth-replay-suite.sha256"
first_entry="$(sed -n '1p' "${manifest}")"
sed -i '/  verify\.sh$/d' "${manifest}"
printf '%s\n' "${first_entry}" >>"${manifest}"
expect_failure_category \
    "duplicate path" \
    bash "${manifest_copy}/scripts/restore-reth-replay-suite.sh" \
    install "${scratch}/duplicate-manifest-target"

symlink_copy="${scratch}/symlink-copy"
cp -a -- "${skill_root}" "${symlink_copy}"
external_source="${scratch}/external-source"
mkdir "${external_source}"
mv -- "${symlink_copy}/assets/witness-db-suite/src" \
    "${external_source}/src"
ln -s "${external_source}/src" \
    "${symlink_copy}/assets/witness-db-suite/src"
expect_failure_category \
    "symlinked ancestor" \
    bash "${symlink_copy}/scripts/restore-reth-replay-suite.sh" \
    install "${scratch}/symlink-source-target"

echo "restore suite regressions: 6/6"
