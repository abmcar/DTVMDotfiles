#!/usr/bin/env bash
# Pre-push validation: mirrors CI pipeline locally.
# Runs format check, build, unittests, and statetests before allowing push.
# Exit non-zero to block the push.

set -euo pipefail

# Find repo root
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# Only run for the main DTVM repo (skip submodules, worktrees of other repos)
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
case "$REMOTE_URL" in
  *DTVMStack/DTVM*|*abmcar/DTVM*) ;;
  *) exit 0 ;;  # Not DTVM repo, skip
esac

SO_PATH="$REPO_ROOT/build/lib/libdtvmapi.so"
EVMONE_BIN="$HOME/evmone/build/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# CI-faithful cmake flags (superset of evmonetestsuite + evmonestatetestsuite)
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

# Backup current CMakeCache.txt so we can restore after tests
CMAKE_CACHE="$REPO_ROOT/build/CMakeCache.txt"
CMAKE_CACHE_BACKUP=""
NEEDS_RESTORE=0

restore_cmake() {
  if [ "$NEEDS_RESTORE" -eq 1 ] && [ -n "$CMAKE_CACHE_BACKUP" ] && [ -f "$CMAKE_CACHE_BACKUP" ]; then
    step "Restoring original cmake configuration"
    cp "$CMAKE_CACHE_BACKUP" "$CMAKE_CACHE"
    cmake --build build --target dtvmapi -j"$(nproc)" > /tmp/dtvm-restore-build.log 2>&1 || true
    rm -f "$CMAKE_CACHE_BACKUP"
    pass "Original cmake config restored"
  fi
}

trap restore_cmake EXIT

step() {
  echo -e "\n${YELLOW}▶ $1${NC}"
}

pass() {
  echo -e "${GREEN}✓ $1${NC}"
}

fail() {
  echo -e "${RED}✗ $1${NC}"
  FAILED=1
}

# 1. Format check
step "Format check"
if bash tools/format.sh check >/dev/null 2>&1; then
  pass "Format check passed"
else
  fail "Format check FAILED — run 'tools/format.sh format' to fix"
fi

# 2. Ensure cmake config matches CI flags
step "Checking cmake configuration against CI"
RECONFIGURE=0
if [ -f "$CMAKE_CACHE" ]; then
  for flag_pair in \
    "ZEN_ENABLE_EVM:BOOL=ON" \
    "ZEN_ENABLE_SINGLEPASS_JIT:BOOL=OFF" \
    "ZEN_ENABLE_MULTIPASS_JIT:BOOL=ON" \
    "ZEN_ENABLE_CPU_EXCEPTION:BOOL=ON" \
    "ZEN_ENABLE_VIRTUAL_STACK:BOOL=ON" \
    "ZEN_ENABLE_LIBEVM:BOOL=ON" \
    "ZEN_ENABLE_JIT_PRECOMPILE_FALLBACK:BOOL=ON"; do
    key="${flag_pair%%=*}"
    expected="${flag_pair##*=}"
    actual=$(grep "^${key}=" "$CMAKE_CACHE" 2>/dev/null | head -1 | cut -d= -f2)
    if [ "$actual" != "$expected" ]; then
      echo -e "  ${YELLOW}${key}: ${actual:-<unset>} → ${expected}${NC}"
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
  if cmake -S . -B build "${CI_CMAKE_FLAGS[@]}" > /tmp/dtvm-cmake-reconfig.log 2>&1; then
    pass "cmake reconfigured with CI flags"
  else
    fail "cmake reconfigure FAILED — see /tmp/dtvm-cmake-reconfig.log"
    echo -e "\n${RED}Pre-push validation FAILED. Push blocked.${NC}"
    exit 1
  fi
else
  pass "cmake config already matches CI"
fi

# 3. Build
step "Building dtvmapi"
if cmake --build build --target dtvmapi -j"$(nproc)" > /tmp/dtvm-build.log 2>&1; then
  pass "Build succeeded"
else
  fail "Build FAILED — see /tmp/dtvm-build.log"
fi

# Bail early if build failed (tests can't run without .so)
if [ ! -f "$SO_PATH" ]; then
  fail "libdtvmapi.so not found at $SO_PATH — cannot run tests"
  echo -e "\n${RED}Pre-push validation FAILED. Push blocked.${NC}"
  exit 1
fi

# 4. evmone-unittests (multipass)
step "evmone-unittests (multipass)"
if EVMONE_EXTERNAL_OPTIONS="$SO_PATH,mode=multipass" \
  "$EVMONE_BIN/evmone-unittests" \
  --gtest_filter="$(paste -sd: tests/evmone_unittests/EVMOneMultipassUnitTestsRunList.txt)" \
  > /tmp/dtvm-unittest-multipass.log 2>&1; then
  pass "Multipass unittests passed"
else
  fail "Multipass unittests FAILED — see /tmp/dtvm-unittest-multipass.log"
fi

# 5. evmone-unittests (interpreter)
step "evmone-unittests (interpreter)"
if EVMONE_EXTERNAL_OPTIONS="$SO_PATH,mode=interpreter" \
  "$EVMONE_BIN/evmone-unittests" \
  --gtest_filter="$(paste -sd: tests/evmone_unittests/EVMOneInterpreterUnitTestsRunList.txt)" \
  > /tmp/dtvm-unittest-interpreter.log 2>&1; then
  pass "Interpreter unittests passed"
else
  fail "Interpreter unittests FAILED — see /tmp/dtvm-unittest-interpreter.log"
fi

# 6. evmone-statetest (multipass, fork_Cancun)
step "evmone-statetest (multipass, fork_Cancun)"
if EVMONE_EXTERNAL_OPTIONS="$SO_PATH,mode=multipass,enable_gas_metering=true" \
  "$EVMONE_BIN/evmone-statetest" \
  tests/fixtures/fixtures/state_tests \
  --vm external_vm -k fork_Cancun \
  > /tmp/dtvm-statetest-multipass.log 2>&1; then
  pass "Multipass statetests passed"
else
  fail "Multipass statetests FAILED — see /tmp/dtvm-statetest-multipass.log"
fi

# 7. evmone-statetest (interpreter, fork_Cancun)
step "evmone-statetest (interpreter, fork_Cancun)"
if EVMONE_EXTERNAL_OPTIONS="$SO_PATH,mode=interpreter,enable_gas_metering=true" \
  "$EVMONE_BIN/evmone-statetest" \
  tests/fixtures/fixtures/state_tests \
  --vm external_vm -k fork_Cancun \
  > /tmp/dtvm-statetest-interpreter.log 2>&1; then
  pass "Interpreter statetests passed"
else
  fail "Interpreter statetests FAILED — see /tmp/dtvm-statetest-interpreter.log"
fi

# Summary
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}All pre-push checks passed. Push allowed.${NC}"
  exit 0
else
  echo -e "${RED}Pre-push validation FAILED. Push blocked.${NC}"
  echo -e "${RED}Fix the issues above, then try pushing again.${NC}"
  exit 1
fi
