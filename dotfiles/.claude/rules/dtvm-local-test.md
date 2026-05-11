---
description: Local EVM test commands using pre-built evmone infrastructure. Use when running evmone-unittests, evmone-statetest, or ctest locally — NOT for CI reproduction (see dtvm-build-config.md for that).
globs: []
alwaysApply: false
---

# DTVM Local Test Commands

Local testing uses pre-built evmone at `~/evmone/` (DTVMStack/evmone, for_test branch).
Do NOT use `.ci/run_test_suite.sh` for local runs — it clones evmone from scratch,
copies .so files, and sets up ASAN, none of which are needed locally.

For CI reproduction, see `.claude/rules/dtvm-build-config.md`.

## Prerequisites

- DTVM built with `libdtvmapi.so` at `build/lib/libdtvmapi.so`
- evmone pre-built at `~/evmone/build/bin/`
- Test fixtures at `tests/fixtures/fixtures/state_tests` (git submodule)
- Run lists at `tests/evmone_unittests/`

## evmone-unittests

Uses curated run lists to exclude unsupported tests (Prague/EIP-7702 etc.).

```bash
# multipass (223 tests)
EVMONE_EXTERNAL_OPTIONS="$(pwd)/build/lib/libdtvmapi.so,mode=multipass" \
  ~/evmone/build/bin/evmone-unittests \
  --gtest_filter="$(paste -sd: tests/evmone_unittests/EVMOneMultipassUnitTestsRunList.txt)"

# interpreter (226 tests)
EVMONE_EXTERNAL_OPTIONS="$(pwd)/build/lib/libdtvmapi.so,mode=interpreter" \
  ~/evmone/build/bin/evmone-unittests \
  --gtest_filter="$(paste -sd: tests/evmone_unittests/EVMOneInterpreterUnitTestsRunList.txt)"
```

## evmone-statetest

**MUST use `-k fork_Cancun`** to filter out Prague tests (DTVM does not support Prague yet).
Running without this filter produces ~28 pre-existing failures that are NOT regressions.

```bash
# multipass
EVMONE_EXTERNAL_OPTIONS="$(pwd)/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  ~/evmone/build/bin/evmone-statetest \
  tests/fixtures/fixtures/state_tests \
  --vm external_vm -k fork_Cancun

# interpreter
EVMONE_EXTERNAL_OPTIONS="$(pwd)/build/lib/libdtvmapi.so,mode=interpreter,enable_gas_metering=true" \
  ~/evmone/build/bin/evmone-statetest \
  tests/fixtures/fixtures/state_tests \
  --vm external_vm -k fork_Cancun
```

## ctest (built-in EVM tests)

```bash
cd build && SPEC_TESTS_ARGS="-m multipass --format evm --enable-evm-gas" ctest --verbose
```

## Common Mistakes

- **Missing `-k fork_Cancun`** on statetest → ~28 Prague failures (not regressions)
- **Missing run list filter** on unittests → failures from unsupported opcodes
- **Using `.ci/run_test_suite.sh` locally** → clones evmone into CWD (`evmone/`,
  `evmone-statetest/`), copies `.so` files everywhere, sets up ASAN — all wrong
  for local use. This is the #1 cause of stale artifact pollution. **Never run it.**
- **Wrong .so path** → EVMC loader failure; always use absolute path via `$(pwd)/`
- **Copying `.so` into `~/evmone/`** → CI script pattern, wrong locally. Always
  pass the `.so` path as an EVMC argument instead.
