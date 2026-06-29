---
description: Local EVM test commands using pre-built evmone infrastructure. Use when running evmone-unittests, evmone-statetest, or ctest locally — NOT for CI reproduction (see dtvm-build-config.md for that).
paths:
  - "src/**"
  - "tests/**"
---

# DTVM Local Test Commands

Local testing uses pre-built evmone at `~/evmone/` (DTVMStack/evmone, for_test branch).
Do NOT use `.ci/run_test_suite.sh` for local runs — it clones evmone and copies .so files
into your workspace (and enables ASAN when `ENABLE_ASAN=true`), polluting it.

For CI reproduction, see `.claude/rules/dtvm-build-config.md`.

## Prerequisites

- DTVM built with `libdtvmapi.so` at `build/lib/libdtvmapi.so`
- evmone pre-built at `~/evmone/build/bin/`
- Test fixtures at `tests/fixtures/fixtures/state_tests` — a gitignored EEST
  release download (see `EVM_SPEC_FIXTURES_URL` in `.ci/run_test_suite.sh`),
  NOT a submodule; worktree-init does not provision it, so fresh worktrees
  and machines must download it (or reference the main repo's copy) first
- Run lists at `tests/evmone_unittests/`

### Building `libdtvmapi.so` locally

No CI script is needed for a local EVM build. Configure and build the multipass
JIT library directly:

```bash
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release \
  -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_MULTIPASS_JIT=ON -DZEN_ENABLE_SPEC_TEST=ON \
  -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON \
  -DLLVM_DIR=<llvm15-prefix>/lib/cmake/llvm
cmake --build build --target dtvmapi -j$(nproc)
```

This produces `build/lib/libdtvmapi.so`. For CI-faithful flag variants (gas
register, fallback test, virtual stack), see `.claude/rules/dtvm-build-config.md`,
which maps each CI job's env vars to CMake options. Never run
`.ci/run_test_suite.sh` locally to obtain them (see Common Mistakes).

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

Whether to pass `-k fork_Cancun` depends on the **corpus test naming** — it is
not an absolute switch:

- **Standard EEST suite** `tests/fixtures/fixtures/state_tests` → **MUST use `-k fork_Cancun`** to filter out
  post-Cancun tests (Prague, Osaka, and future forks DTVM does not support yet).
  Omitting it produces many pre-existing failures — the count grows with each
  EEST release — that are NOT regressions.
- **Replay real-load corpus** `~/dtvm-perf-corpora/mainnet-replay/cancun-suite/`
  → **do NOT pass `-k fork_Cancun`**, or it matches zero tests.

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

For the replay real-load corpus (no fork suffix, hence no `-k`):

```bash
EVMONE_EXTERNAL_OPTIONS="$(pwd)/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  ~/evmone/build/bin/evmone-statetest \
  ~/dtvm-perf-corpora/mainnet-replay/cancun-suite \
  --vm external_vm
```

## ctest (built-in EVM tests)

```bash
cd build && SPEC_TESTS_ARGS="-m multipass --format evm --enable-evm-gas" ctest --verbose
```

## Test Selection by Touched Path

Map touched paths to required test suites as follows. When the diff touches files from multiple buckets, run **all** matching suites.

| Touched path | Required test suite |
|---|---|
| `src/compiler/` or `src/runtime/` | multipass `evmone-unittests` **and** multipass `evmone-statetest -k fork_Cancun` |
| `src/evm/` | interpreter `evmone-unittests` **and** interpreter `evmone-statetest -k fork_Cancun` |
| `src/tests/` only | `ctest` in the build dir |
| `docs/`-only or `.claude/`-only or `CLAUDE.md`-only | format check + `ctest` smoke only; `evmone-*` runs skipped |
| Unknown / mixed / cross-module | multipass unittests + multipass statetest as the safe default |

Per Rule 1 of `.claude/rules/ci-test-discipline.md`: **never silently skip a
required suite.** If a suite cannot be run, report the skip and the reason
explicitly (*"I could not run <X> because <reason>. The results below are
from <Y> only — this does not cover the same scope."*).

For docs-only / `.claude/`-only diffs:
- List what was executed and what was skipped.
- Cite the touched-paths rationale so Rule 1 is not violated by omission.

## Common Mistakes

- **Wrong `-k fork_Cancun` for the corpus** → on the standard EEST suite,
  **omitting** `-k` gives many post-Cancun failures (not regressions); on the
  replay corpus (`0x<hash>.json`, no fork suffix), **adding** `-k` matches zero
  tests. The corpus decides whether to pass it.
- **Missing run list filter** on unittests → failures from unsupported opcodes
- **Wrong cwd** → run all commands from the repo root. From any other cwd the
  run-list `paste` fails, the resulting empty `--gtest_filter=` selects zero
  tests, and the run exits 0 — a silent false PASS.
- **Using `.ci/run_test_suite.sh` locally** → clones evmone into CWD (`evmone/`,
  `evmone-statetest/`), copies `.so` files everywhere (and sets up ASAN when
  `ENABLE_ASAN=true`) — all wrong for local use. This is the #1 cause of stale
  artifact pollution. **Never run it.**
- **Wrong .so path** → EVMC loader failure; always use absolute path via `$(pwd)/`
- **Copying `.so` into `~/evmone/`** → do not do this; pass the build-path as the EVMC argument instead. CI copies `build/lib/*` into its own cloned evmone dir, not `~/evmone/`.
