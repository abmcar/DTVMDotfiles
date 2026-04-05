# Local Development Environment

## evmone Test Infrastructure
- evmone root: `/home/abmcar/evmone/`
- evmone-bench: `/home/abmcar/evmone/build/bin/evmone-bench`
- evmone-unittests: `/home/abmcar/evmone/build/bin/evmone-unittests`
- evmone-statetest: `/home/abmcar/evmone/build/bin/evmone-statetest`
- Benchmark suite: `/home/abmcar/evmone/test/evm-benchmarks/benchmarks`

## DTVM Builds
- Main lib: `build/lib/libdtvmapi.so` (multipass JIT enabled)
- EVMC config string: `"<lib>,mode=multipass,enable_gas_metering=true"`
- For full build commands, see `.claude/rules/dtvm-build-config.md`

## Baseline Worktree
- Path: `/home/abmcar/dtvm-baseline` (tracks upstream/main)
- Build dir: `build-baseline/`
- Auto-refresh before benchmark: `git -C /home/abmcar/dtvm-baseline fetch upstream && git -C /home/abmcar/dtvm-baseline checkout upstream/main`

## Statetest Fixtures
- Path: `tests/fixtures/fixtures/state_tests`
- statetest VM arg: `EVMONE_EXTERNAL_OPTIONS="<lib>,mode=multipass,enable_gas_metering=true"`

## Research
- Research repo: `docs/research/` (clone of https://github.com/abmcar/DTVM-Papers)
- Direction tracking: `docs/research/directions/`
- Paper library: `docs/research/papers/`
- Setup: `git clone https://github.com/abmcar/DTVM-Papers docs/research`

## Difftest
- Code: `tools/difftest/`
- evmone CLI: `/home/abmcar/evmone/build/bin/evmc run --vm /home/abmcar/evmone/build/lib/libevmone.so`
- Quick run: `python3 -m tools.difftest.evm_difftest --dtvm ./build/dtvm --seeds-only -v`

## Git Remotes
- `origin` = github.com/abmcar/DTVM (personal fork)
- `upstream` = github.com/DTVMStack/DTVM (main project)
- PRs: feature branches on origin -> upstream/main
