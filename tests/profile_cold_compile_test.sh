#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
PROFILE_SCRIPT="$REPO_DIR/skills/active/dtvm-cold-compile-profile/scripts/profile_cold_compile.sh"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

FAKE_REPO="$TEST_TMP/repo with spaces"
BUILD_DIR="$TEST_TMP/build"
DTVM_LIB_DIR="$BUILD_DIR/lib"
DTVM_LIBRARY="$DTVM_LIB_DIR/libdtvmapi.so"
DTVM_SONAME="$DTVM_LIB_DIR/libdtvmapi.so.1"
DTVM_REAL_LIBRARY="$DTVM_LIB_DIR/libdtvmapi.so.1.2.3"
POSITIONAL_LIB_DIR="$TEST_TMP/positional library"
POSITIONAL_LIBRARY="$POSITIONAL_LIB_DIR/libdtvmapi.so"
POSITIONAL_REAL_LIBRARY="$POSITIONAL_LIB_DIR/libdtvmapi.so.9.8.7"
CORPUS="$FAKE_REPO/corpus.hex"
SUBJECT="$FAKE_REPO/subject.sh"
FAKE_PERF="$TEST_TMP/fake-perf"
BUNDLE="$TEST_TMP/profile bundle"

mkdir -p "$FAKE_REPO" "$DTVM_LIB_DIR" "$POSITIONAL_LIB_DIR"
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.name test
git -C "$FAKE_REPO" config user.email test@example.com
printf '%s\n' 'jit-*.dump' > "$FAKE_REPO/.gitignore"
printf '%s\n' deadbeef > "$CORPUS"

printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "jit evidence\\n" > "jit-$$.dump"' > "$SUBJECT"
chmod +x "$SUBJECT"

git -C "$FAKE_REPO" add .gitignore corpus.hex subject.sh
git -C "$FAKE_REPO" commit -qm fixture
printf 'CMAKE_HOME_DIRECTORY:INTERNAL=%s\n' "$FAKE_REPO" \
    > "$BUILD_DIR/CMakeCache.txt"
printf '%s\n' 'fake dtvm library' > "$DTVM_REAL_LIBRARY"
ln -s "$(basename "$DTVM_REAL_LIBRARY")" "$DTVM_SONAME"
ln -s "$(basename "$DTVM_SONAME")" "$DTVM_LIBRARY"
printf '%s\n' 'fake positional library' > "$POSITIONAL_REAL_LIBRARY"
ln -s "$(basename "$POSITIONAL_REAL_LIBRARY")" "$POSITIONAL_LIBRARY"

printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'mode=${1:-}' \
    'shift || true' \
    'case "$mode" in' \
    '  version)' \
    '    echo "perf version fake"' \
    '    ;;' \
    '  record)' \
    '    output=""' \
    '    while (($#)); do' \
    '      case "$1" in' \
    '        --output) output=$2; shift 2 ;;' \
    '        --) shift; break ;;' \
    '        *) shift ;;' \
    '      esac' \
    '    done' \
    '    printf "fake perf data\\n" > "$output"' \
    '    "$@"' \
    '    ;;' \
    '  inject)' \
    '    input=""' \
    '    output=""' \
    '    while (($#)); do' \
    '      case "$1" in' \
    '        --input) input=$2; shift 2 ;;' \
    '        --output) output=$2; shift 2 ;;' \
    '        *) shift ;;' \
    '      esac' \
    '    done' \
    '    cp "$input" "$output"' \
    '    ;;' \
    '  report)' \
    '    echo "  70.00% objdump fake.so fake_symbol"' \
    '    ;;' \
    '  *)' \
    '    echo "unexpected fake perf mode: $mode" >&2' \
    '    exit 2' \
    '    ;;' \
    'esac' > "$FAKE_PERF"
chmod +x "$FAKE_PERF"

# Dry-run must not refresh the Git index even after a tracked-file stat change.
touch "$SUBJECT"
INDEX_TIME_BEFORE="$(stat -c '%y' "$FAKE_REPO/.git/index")"
bash "$PROFILE_SCRIPT" \
    --dry-run \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$BUNDLE" \
    -- "$SUBJECT" "$POSITIONAL_LIBRARY" >/dev/null
[ ! -e "$BUNDLE" ] || fail "dry-run created the bundle"
[ "$(stat -c '%y' "$FAKE_REPO/.git/index")" = "$INDEX_TIME_BEFORE" ] ||
    fail "dry-run refreshed the Git index"

bash "$PROFILE_SCRIPT" \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$BUNDLE" \
    -- "$SUBJECT" "$POSITIONAL_LIBRARY" >/dev/null

grep -Fqx 'status=complete' "$BUNDLE/status.txt" ||
    fail "bundle did not complete"
(
    cd "$BUNDLE"
    sha256sum -c manifest.sha256 >/dev/null
)
[ -s "$BUNDLE/perf.data" ] || fail "raw perf data is missing"
[ -s "$BUNDLE/perf.jit.data" ] || fail "JIT-injected perf data is missing"
[ -n "$(find "$BUNDLE/jit" -type f -name '*jit-*.dump' -print -quit)" ] ||
    fail "new JIT dump was not retained"
grep -Fq objdump "$BUNDLE/child-process-signals.txt" ||
    fail "child process signal was not separated"
[ -x "$BUNDLE/rerun-profile.sh" ] || fail "rerun script is not executable"
[ -x "$BUNDLE/metadata/profile_cold_compile.sh" ] ||
    fail "profiling implementation was not bundled"
grep -Fq '$BUNDLE_DIR/metadata/profile_cold_compile.sh' "$BUNDLE/rerun-profile.sh" ||
    fail "rerun script still depends on the installed skill"
grep -Fq '  ./status.txt' "$BUNDLE/manifest.sha256" ||
    fail "bundle status is not protected by the integrity manifest"
grep -Fq "$(printf 'symlink\tpath=%s\ttarget=%s' \
    "$DTVM_LIBRARY" "$(basename "$DTVM_SONAME")")" \
    "$BUNDLE/metadata/build-artifacts.identity" ||
    fail "unversioned DTVM library symlink identity is missing"
grep -Fq "$(printf 'symlink\tpath=%s\ttarget=%s' \
    "$DTVM_SONAME" "$(basename "$DTVM_REAL_LIBRARY")")" \
    "$BUNDLE/metadata/build-artifacts.identity" ||
    fail "DTVM library SONAME symlink identity is missing"
grep -Fq "$(printf 'realpath\tpath=%s' "$DTVM_REAL_LIBRARY")" \
    "$BUNDLE/metadata/build-artifacts.identity" ||
    fail "versioned DTVM library realpath identity is missing"
printf -v POSITIONAL_LIBRARY_QUOTED '%q' "$POSITIONAL_LIBRARY"
grep -Fq "$(printf 'artifact\tlogical=%s' "$POSITIONAL_LIBRARY_QUOTED")" \
    "$BUNDLE/metadata/build-artifacts.identity" ||
    fail "positional DTVM library outside the build tree is missing"
grep -Fq "  $DTVM_REAL_LIBRARY" \
    "$BUNDLE/metadata/build-artifacts.sha256" ||
    fail "versioned DTVM library content hash is missing"

RERUN_BUNDLE="$TEST_TMP/rerun bundle"
"$BUNDLE/rerun-profile.sh" "$RERUN_BUNDLE" >/dev/null
grep -Fqx 'status=complete' "$RERUN_BUNDLE/status.txt" ||
    fail "identity-checked rerun did not complete"

printf 'status=tampered\n' > "$BUNDLE/status.txt"
if (
    cd "$BUNDLE"
    sha256sum -c manifest.sha256 >/dev/null 2>&1
); then
    fail "integrity manifest accepted a tampered bundle status"
fi
if "$BUNDLE/rerun-profile.sh" "$TEST_TMP/status-tamper-bundle" \
    >/dev/null 2>&1; then
    fail "rerun accepted a tampered bundle status"
fi
[ ! -e "$TEST_TMP/status-tamper-bundle" ] ||
    fail "status integrity failure created an output bundle"
printf 'status=complete\n' > "$BUNDLE/status.txt"
(
    cd "$BUNDLE"
    sha256sum -c manifest.sha256 >/dev/null
)

printf '%s\n' 'mutated positional library' > "$POSITIONAL_REAL_LIBRARY"
if "$BUNDLE/rerun-profile.sh" "$TEST_TMP/changed-artifact-bundle" \
    >/dev/null 2>"$TEST_TMP/changed-artifact.log"; then
    fail "rerun accepted changed DTVM build artifact content"
fi
[ ! -e "$TEST_TMP/changed-artifact-bundle" ] ||
    fail "build artifact identity failure created an output bundle"
grep -Fq 'DTVM build artifacts differ from the expected identity' \
    "$TEST_TMP/changed-artifact.log" ||
    fail "artifact mutation did not fail the build identity expectation"
printf '%s\n' 'fake positional library' > "$POSITIONAL_REAL_LIBRARY"

DTVM_ALTERNATE_LIBRARY="$DTVM_LIB_DIR/libdtvmapi-alternate"
cp "$DTVM_REAL_LIBRARY" "$DTVM_ALTERNATE_LIBRARY"
ln -sfn "$(basename "$DTVM_ALTERNATE_LIBRARY")" "$DTVM_SONAME"
if "$BUNDLE/rerun-profile.sh" "$TEST_TMP/changed-symlink-bundle" \
    >/dev/null 2>"$TEST_TMP/changed-symlink.log"; then
    fail "rerun accepted a changed DTVM library symlink chain"
fi
[ ! -e "$TEST_TMP/changed-symlink-bundle" ] ||
    fail "symlink identity failure created an output bundle"
grep -Fq 'DTVM build artifacts differ from the expected identity' \
    "$TEST_TMP/changed-symlink.log" ||
    fail "symlink mutation did not fail the build identity expectation"
ln -sfn "$(basename "$DTVM_REAL_LIBRARY")" "$DTVM_SONAME"
rm "$DTVM_ALTERNATE_LIBRARY"

printf '%s\n' changed > "$CORPUS"
if "$BUNDLE/rerun-profile.sh" "$TEST_TMP/changed-corpus-bundle" \
    >/dev/null 2>&1; then
    fail "rerun accepted changed corpus content"
fi
[ ! -e "$TEST_TMP/changed-corpus-bundle" ] ||
    fail "corpus identity failure created an output bundle"
git -C "$FAKE_REPO" checkout -q -- corpus.hex

printf '%s\n' source-identity > "$FAKE_REPO/source-identity.txt"
git -C "$FAKE_REPO" add source-identity.txt
git -C "$FAKE_REPO" commit -qm 'advance source identity'
if "$BUNDLE/rerun-profile.sh" "$TEST_TMP/changed-commit-bundle" \
    >/dev/null 2>&1; then
    fail "rerun accepted a different source commit"
fi
[ ! -e "$TEST_TMP/changed-commit-bundle" ] ||
    fail "source commit identity failure created an output bundle"

printf '%s\n' '# diagnostic patch' >> "$FAKE_REPO/.gitignore"
DIRTY_BUNDLE="$TEST_TMP/dirty profile bundle"
bash "$PROFILE_SCRIPT" \
    --allow-dirty \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$DIRTY_BUNDLE" \
    -- "$SUBJECT" >/dev/null
"$DIRTY_BUNDLE/rerun-profile.sh" "$TEST_TMP/dirty rerun bundle" >/dev/null
printf '%s\n' '# changed diagnostic patch' >> "$FAKE_REPO/.gitignore"
if "$DIRTY_BUNDLE/rerun-profile.sh" "$TEST_TMP/changed-patch-bundle" \
    >/dev/null 2>&1; then
    fail "dirty rerun accepted a different source patch"
fi
[ ! -e "$TEST_TMP/changed-patch-bundle" ] ||
    fail "source patch identity failure created an output bundle"
git -C "$FAKE_REPO" checkout -q -- .gitignore

# A command that mutates an already-dirty patch without changing porcelain
# status must fail the end-of-run identity check.
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "# changed during profiling\\n" >> .gitignore' \
    'printf "jit evidence\\n" > "jit-$$.dump"' > "$SUBJECT"
git -C "$FAKE_REPO" add subject.sh
git -C "$FAKE_REPO" commit -qm 'mutating subject fixture'
printf '%s\n' '# dirty before profiling' >> "$FAKE_REPO/.gitignore"
MUTATING_BUNDLE="$TEST_TMP/mutating profile bundle"
if bash "$PROFILE_SCRIPT" \
    --allow-dirty \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$MUTATING_BUNDLE" \
    -- "$SUBJECT" >/dev/null 2>&1; then
    fail "profile accepted a source patch changed during execution"
fi
grep -Fqx 'status=failed' "$MUTATING_BUNDLE/status.txt" ||
    fail "source mutation did not leave a failed bundle"
git -C "$FAKE_REPO" checkout -q -- .gitignore

# Dirty submodule contents have no exact identity in the superproject patch and
# are rejected even for a diagnostic --allow-dirty run.
SUBMODULE_SOURCE="$TEST_TMP/submodule-source"
mkdir -p "$SUBMODULE_SOURCE"
git -C "$SUBMODULE_SOURCE" init -q
git -C "$SUBMODULE_SOURCE" config user.name test
git -C "$SUBMODULE_SOURCE" config user.email test@example.com
printf '%s\n' fixture > "$SUBMODULE_SOURCE/tracked.txt"
git -C "$SUBMODULE_SOURCE" add tracked.txt
git -C "$SUBMODULE_SOURCE" commit -qm fixture
git -C "$FAKE_REPO" -c protocol.file.allow=always submodule add -q \
    "$SUBMODULE_SOURCE" dependency
git -C "$FAKE_REPO" commit -qam 'add submodule fixture'
printf '%s\n' dirty >> "$FAKE_REPO/dependency/tracked.txt"
if bash "$PROFILE_SCRIPT" \
    --allow-dirty \
    --dry-run \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$TEST_TMP/dirty-submodule-bundle" \
    -- "$SUBJECT" >/dev/null 2>&1; then
    fail "dirty submodule unexpectedly passed source identity preflight"
fi
[ ! -e "$TEST_TMP/dirty-submodule-bundle" ] ||
    fail "dirty submodule preflight created an output bundle"
git -C "$FAKE_REPO/dependency" checkout -q -- tracked.txt

ln -s "$CORPUS" "$TEST_TMP/symlink-corpus"
if bash "$PROFILE_SCRIPT" \
    --dry-run \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$TEST_TMP/symlink-corpus" \
    --output-dir "$TEST_TMP/symlink-bundle" \
    -- "$SUBJECT" >/dev/null 2>&1; then
    fail "symlinked corpus unexpectedly passed preflight"
fi

printf '%s\n' untracked > "$FAKE_REPO/untracked-source.h"
if bash "$PROFILE_SCRIPT" \
    --dry-run \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$TEST_TMP/untracked-bundle" \
    -- "$SUBJECT" >/dev/null 2>&1; then
    fail "untracked source unexpectedly passed clean-state preflight"
fi
rm "$FAKE_REPO/untracked-source.h"

if bash "$PROFILE_SCRIPT" \
    --repo "$FAKE_REPO" \
    --build-dir "$BUILD_DIR" \
    --work-dir "$FAKE_REPO" \
    --perf "$FAKE_PERF" \
    --corpus "$CORPUS" \
    --output-dir "$BUNDLE" \
    -- "$SUBJECT" >/dev/null 2>&1; then
    fail "existing output path was reused"
fi

echo "PASS: cold compile profile bundle"
