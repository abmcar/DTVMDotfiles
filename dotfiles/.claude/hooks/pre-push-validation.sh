#!/usr/bin/env bash
# Pre-push validation: mirrors CI pipeline locally.
# Runs format check, build, unittests, and statetests before allowing push.
# Outputs {"decision":"block",...} JSON on failure to block the push via CC hook protocol.

set -euo pipefail

# P0-C: bypass mechanisms
# Substring match is safe: git refnames cannot contain consecutive '--'
# (per `git check-ref-format`), so no false positives from branch names.
case "${CMD:-}" in
  *--no-verify*) echo "[pre-push] --no-verify in command, skipping." >&2; exit 0 ;;
esac
if [ "${DTVM_SKIP_PRE_PUSH:-}" = "1" ]; then
  echo "[pre-push] DTVM_SKIP_PRE_PUSH=1, skipping." >&2
  exit 0
fi

# P0-A: derive REPO_ROOT from the push's effective cwd.
# Parse $CMD for an inline `cd <dir> &&` or `git -C <dir>`; fall back to $PUSH_PWD_HINT.
EFFECTIVE_PWD="${PUSH_PWD_HINT:-$PWD}"
_cmd="${CMD:-}"
if [[ "$_cmd" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+)[[:space:]]+\&\& ]]; then
  EFFECTIVE_PWD="${BASH_REMATCH[1]}"
elif [[ "$_cmd" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  _gitC="${BASH_REMATCH[1]}"
  case "$_gitC" in
    /*) EFFECTIVE_PWD="$_gitC" ;;
    *)  EFFECTIVE_PWD="${PUSH_PWD_HINT:-$PWD}/$_gitC" ;;
  esac
fi

REPO_ROOT=$(git -C "$EFFECTIVE_PWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$REPO_ROOT"

# Only run for pushes to the DTVM repo itself (not DTVMDotfiles, DTVM-Papers, etc.)
PUSH_REMOTE=$(git remote get-url origin 2>/dev/null || true)
case "$PUSH_REMOTE" in
  *DTVMStack/DTVM|*DTVMStack/DTVM.git|*abmcar/DTVM|*abmcar/DTVM.git) ;;
  *) exit 0 ;;
esac

# P0-B: docs-only short-circuit. Diff range must match what's actually being pushed:
# prefer @{push} (git's native "where I'd push to" ref); fall back to origin/<current-branch>.
# If neither resolves, skip the docs check entirely (let validation run).
# First push of a new branch: no @{push}, no origin/<branch> → PUSH_BASE empty,
# fall through to full validation. This is the safe default; do NOT change it.
PUSH_BASE=""
if _b=$(git rev-parse --verify -q '@{push}' 2>/dev/null); then
  PUSH_BASE="$_b"
elif _br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) && [ -n "$_br" ] && \
     _b=$(git rev-parse --verify -q "origin/$_br" 2>/dev/null); then
  PUSH_BASE="$_b"
fi

if [ -n "$PUSH_BASE" ]; then
  CHANGED=$(git diff --name-only "$PUSH_BASE..HEAD" 2>/dev/null || true)
  # Allowlist (no local build/test impact):
  #   docs/, paper/ (LaTeX/PDF), top-level .md, CHANGELOG,
  #   .github/workflows/ (CI YAML — only matters in CI runs, never locally).
  # Anything else → full validation.
  if [ -n "$CHANGED" ] && ! printf '%s\n' "$CHANGED" | grep -qvE '^(docs/|paper/|\.github/workflows/|[^/]*\.md$|CHANGELOG(\.md)?$)'; then
    echo "[pre-push] no-build-impact diff vs ${PUSH_BASE:0:12}, skipping build/tests:" >&2
    printf '  %s\n' "$CHANGED" >&2
    exit 0
  fi
fi

SO_PATH="$REPO_ROOT/build/lib/libdtvmapi.so"
EVMONE_BIN="$HOME/evmone/build/bin"
LOG_DIR="/tmp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# Single source of truth for CI cmake flags.
# The cache-check loop below derives its expected values from this array.
CI_CMAKE_FLAGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DZEN_ENABLE_EVM=ON
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF
  -DZEN_ENABLE_MULTIPASS_JIT=ON
  -DZEN_ENABLE_CPU_EXCEPTION=ON
  -DZEN_ENABLE_VIRTUAL_STACK=ON
  -DZEN_ENABLE_LIBEVM=ON
  -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON
)

CMAKE_CACHE="$REPO_ROOT/build/CMakeCache.txt"
CMAKE_CACHE_BACKUP=""
NEEDS_RESTORE=0

restore_cmake() {
  if [ "$NEEDS_RESTORE" -eq 1 ] && [ -n "$CMAKE_CACHE_BACKUP" ] && [ -f "$CMAKE_CACHE_BACKUP" ]; then
    step "Restoring original cmake configuration"
    cp "$CMAKE_CACHE_BACKUP" "$CMAKE_CACHE"
    cmake --build build --target dtvmapi -j"$(nproc)" > "$LOG_DIR/dtvm-restore-build.log" 2>&1 || true
    rm -f "$CMAKE_CACHE_BACKUP"
    pass "Original cmake config restored"
  fi
}

trap restore_cmake EXIT

step() { echo -e "\n${YELLOW}▶ $1${NC}" >&2; }
pass() { echo -e "${GREEN}✓ $1${NC}" >&2; }
fail() { echo -e "${RED}✗ $1${NC}" >&2; FAILED=1; }

block() {
  echo -e "\n${RED}Pre-push validation FAILED. Push blocked.${NC}" >&2
  echo "{\"decision\":\"block\",\"reason\":\"Pre-push validation failed: $1\"}"
  exit 0
}

run_test() {
  local label="$1" opts="$2" bin="$3" log="$4"
  shift 4
  step "$label"
  if EVMONE_EXTERNAL_OPTIONS="$opts" "$EVMONE_BIN/$bin" "$@" > "$log" 2>&1; then
    pass "$label passed"
  else
    echo -e "${RED}✗ $label FAILED — see $log${NC}" >&2
    return 1
  fi
}

# 1. Format check
step "Format check"
if bash tools/format.sh check >/dev/null 2>&1; then
  pass "Format check passed"
else
  fail "Format check FAILED — run 'tools/format.sh format' to fix"
fi

# 2. Ensure cmake config matches CI flags (derived from CI_CMAKE_FLAGS)
step "Checking cmake configuration against CI"
RECONFIGURE=0
if [ -f "$CMAKE_CACHE" ]; then
  for flag in "${CI_CMAKE_FLAGS[@]}"; do
    # Skip -DCMAKE_BUILD_TYPE (not a ZEN_ flag, checked differently)
    case "$flag" in -DCMAKE_BUILD_TYPE=*) continue ;; esac
    # Parse "-DZEN_ENABLE_FOO=ON" → key="ZEN_ENABLE_FOO:BOOL", expected="ON"
    kv="${flag#-D}"
    key="${kv%%=*}:BOOL"
    expected="${kv##*=}"
    actual=$(grep "^${key}=" "$CMAKE_CACHE" 2>/dev/null | head -1 | cut -d= -f2)
    if [ "$actual" != "$expected" ]; then
      echo -e "  ${YELLOW}${key}: ${actual:-<unset>} → ${expected}${NC}" >&2
      RECONFIGURE=1
    fi
  done
else
  RECONFIGURE=1
fi

if [ "$RECONFIGURE" -eq 1 ]; then
  step "Reconfiguring cmake with CI flags"
  cp "$CMAKE_CACHE" "$CMAKE_CACHE.pre-push-backup" 2>/dev/null || true
  CMAKE_CACHE_BACKUP="$CMAKE_CACHE.pre-push-backup"
  NEEDS_RESTORE=1
  if cmake -S . -B build "${CI_CMAKE_FLAGS[@]}" > "$LOG_DIR/dtvm-cmake-reconfig.log" 2>&1; then
    pass "cmake reconfigured with CI flags"
  else
    block "cmake reconfigure failed — see $LOG_DIR/dtvm-cmake-reconfig.log"
  fi
else
  pass "cmake config already matches CI"
fi

# 3. Build
step "Building dtvmapi"
if ! cmake --build build --target dtvmapi -j"$(nproc)" > "$LOG_DIR/dtvm-build.log" 2>&1; then
  block "build failed — see $LOG_DIR/dtvm-build.log"
fi
if [ ! -f "$SO_PATH" ]; then
  block "libdtvmapi.so not found after build"
fi
pass "Build succeeded"

# 4. Tests — run all four in parallel
MULTIPASS_FILTER="$(paste -sd: tests/evmone_unittests/EVMOneMultipassUnitTestsRunList.txt)"
INTERP_FILTER="$(paste -sd: tests/evmone_unittests/EVMOneInterpreterUnitTestsRunList.txt)"
STATE_ARGS=(tests/fixtures/fixtures/state_tests --vm external_vm -k fork_Cancun)

run_test "evmone-unittests (multipass)" \
  "$SO_PATH,mode=multipass" evmone-unittests "$LOG_DIR/dtvm-unittest-multipass.log" \
  --gtest_filter="$MULTIPASS_FILTER" &
PID_UT_MP=$!

run_test "evmone-unittests (interpreter)" \
  "$SO_PATH,mode=interpreter" evmone-unittests "$LOG_DIR/dtvm-unittest-interpreter.log" \
  --gtest_filter="$INTERP_FILTER" &
PID_UT_INT=$!

run_test "evmone-statetest (multipass)" \
  "$SO_PATH,mode=multipass,enable_gas_metering=true" evmone-statetest "$LOG_DIR/dtvm-statetest-multipass.log" \
  "${STATE_ARGS[@]}" &
PID_ST_MP=$!

run_test "evmone-statetest (interpreter)" \
  "$SO_PATH,mode=interpreter,enable_gas_metering=true" evmone-statetest "$LOG_DIR/dtvm-statetest-interpreter.log" \
  "${STATE_ARGS[@]}" &
PID_ST_INT=$!

# Wait for all tests; collect failures from subshell exit codes
wait "$PID_UT_MP" || FAILED=1
wait "$PID_UT_INT" || FAILED=1
wait "$PID_ST_MP" || FAILED=1
wait "$PID_ST_INT" || FAILED=1

# Summary
echo "" >&2
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}All pre-push checks passed. Push allowed.${NC}" >&2
  exit 0
else
  echo -e "${RED}Fix the issues above, then try pushing again.${NC}" >&2
  block "one or more checks failed — see stderr for details"
fi
