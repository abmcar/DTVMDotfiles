# Local Development Environment

## evmone Test Infrastructure
- evmone source: `/home/abmcar/evmone-for-test-mulx-adx/`
- evmone-bench: `/home/abmcar/evmone-for-test-mulx-adx/build/bin/evmone-bench`
- evmone-unittests: `/home/abmcar/evmone-for-test-mulx-adx/build/bin/evmone-unittests`
- evmone-statetest: `/home/abmcar/evmone-statetest/build/bin/evmone-statetest`
- Benchmark suite: `/home/abmcar/evmone-for-test-mulx-adx/test/evm-benchmarks/benchmarks`
- evmone is also accessible via symlink at `/home/abmcar/evmone-bench`

## DTVM Builds
- Main lib: `build/lib/libdtvmapi.so`
- CI build (multipass JIT): `build-ci/` with `-DZEN_ENABLE_MULTIPASS_JIT=ON`
- EVMC config string: `"<lib>,mode=multipass,enable_gas_metering=true"`
- For full build commands, see `.claude/rules/dtvm-build-config.md`

## Baseline Worktree
- Path: `/home/abmcar/dtvm-baseline` (tracks upstream/main)
- Build dir: `build-baseline/`
- Auto-refresh before benchmark: `git -C /home/abmcar/dtvm-baseline fetch upstream && git -C /home/abmcar/dtvm-baseline checkout upstream/main`

## Statetest Fixtures
- Path: `tests/fixtures/fixtures/state_tests`
- statetest VM arg: `EVMONE_EXTERNAL_OPTIONS="<lib>,mode=multipass,enable_gas_metering=true"`

## Difftest
- Code: `tools/difftest/`
- evmone CLI: `evmone/build/bin/evmc run --vm evmone/build/lib/libevmone.so`
- Quick run: `python3 -m tools.difftest.evm_difftest --dtvm ./build-ci/dtvm --seeds-only -v`

## Git Remotes
- `origin` = github.com/abmcar/DTVM (personal fork)
- `upstream` = github.com/DTVMStack/DTVM (main project)
- PRs: feature branches on origin -> upstream/main
