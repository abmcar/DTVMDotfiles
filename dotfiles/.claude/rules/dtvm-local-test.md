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

## Test Selection by Touched Path

For workflows that need to run "the right test suite for this diff" (e.g.
`/dev-cycle` Phase 5 pre-push gate), map touched paths to test suites as
follows. When the diff touches files from multiple buckets, run **all**
matching suites.

| Touched path | Required test suite |
|---|---|
| `src/compiler/` or `src/runtime/` | multipass `evmone-unittests` **and** multipass `evmone-statetest -k fork_Cancun` |
| `src/evm/` | interpreter `evmone-unittests` **and** interpreter `evmone-statetest -k fork_Cancun` |
| `src/tests/` only | `ctest` in the build dir |
| `docs/`-only or `.claude/`-only or `CLAUDE.md`-only | format check + `ctest` smoke (build is a no-op but still run; full `evmone-*` runs skipped) |
| Unknown / mixed / cross-module | multipass unittests + multipass statetest as the safe default |

Per Rule 1 of `.claude/rules/ci-test-discipline.md`: **never silently skip a
required suite.** If a suite cannot be run, report the skip and the reason
explicitly (*"I could not run <X> because <reason>. The results below are
from <Y> only — this does not cover the same scope."*).

For docs-only / `.claude/`-only diffs, explicitly list in the report what
was executed and what was skipped, citing the touched-paths rationale, so
Rule 1 is not violated by omission.

## Common Mistakes

- **Missing `-k fork_Cancun`** on statetest → ~28 Prague failures (not regressions)
- **Missing run list filter** on unittests → failures from unsupported opcodes
- **Using `.ci/run_test_suite.sh` locally** → clones evmone into CWD (`evmone/`,
  `evmone-statetest/`), copies `.so` files everywhere, sets up ASAN — all wrong
  for local use. This is the #1 cause of stale artifact pollution. **Never run it.**
- **Wrong .so path** → EVMC loader failure; always use absolute path via `$(pwd)/`
- **Copying `.so` into `~/evmone/`** → a local mis-step, NOT a CI pattern: the CI
  script copies `build/lib/*` into the repo-local cloned evmone dir (`$EVMONE_DIR`,
  e.g. `evmone-statetest/`), never `~/evmone`. Always pass the `.so` path as an
  EVMC argument instead.
