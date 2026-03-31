# DTVM Perf Lab Playbook

## Keep/Remove Policy

Never remove:

- `/home/abmcar/dtvm-baseline` — persistent baseline worktree
- `/home/abmcar/evmone-bench` — persistent evmone symlink
- `/home/abmcar/evmone-for-test-mulx-adx` — symlink target for evmone-bench

Keep by default:

- `/home/abmcar/DTVM`
- one active branch worktree such as `/home/abmcar/DTVM-<topic>`

Remove after use:

- stale `DTVM-*` worktrees not tied to the current branch
- stale `evmone-for-test-*` directories from old experiments
  (except `evmone-for-test-mulx-adx`)

Do not remove:

- non-worktree clones or directories unless the user explicitly includes them
- arbitrary sibling directories that merely resemble DTVM scratch names

## Canonical Commands

Create branch worktree:

```bash
git -C /home/abmcar/DTVM worktree add /home/abmcar/DTVM-topic -b perf/topic
cd /home/abmcar/DTVM-topic
git submodule update --init --recursive
```

Remove stale branch worktree:

```bash
git -C /home/abmcar/DTVM worktree remove --force /home/abmcar/DTVM-topic
```

Refresh persistent baseline to latest upstream/main:

```bash
git -C /home/abmcar/dtvm-baseline fetch upstream
git -C /home/abmcar/dtvm-baseline checkout upstream/main
# Then rebuild if upstream/main changed:
cmake --build /home/abmcar/dtvm-baseline/build-baseline --target dtvmapi -j$(nproc)
```

## Initial Baseline Build (first time or fresh machine only)

If `/home/abmcar/dtvm-baseline/build-baseline/` does not exist yet:

```bash
cd /home/abmcar/dtvm-baseline
git submodule update --init --recursive
cmake -S . -B build-baseline -GNinja -DCMAKE_BUILD_TYPE=Release \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_CPU_EXCEPTION=ON -DZEN_ENABLE_VIRTUAL_STACK=ON
cmake --build build-baseline --target dtvmapi -j$(nproc)
```

To speed up the configure step by reusing already-fetched deps from an
existing build (e.g. `/home/abmcar/DTVM/build`), add FETCHCONTENT overrides:

```bash
cmake -S . -B build-baseline -GNinja -DCMAKE_BUILD_TYPE=Release \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_CPU_EXCEPTION=ON -DZEN_ENABLE_VIRTUAL_STACK=ON \
  -DFETCHCONTENT_SOURCE_DIR_spdlog=/home/abmcar/DTVM/build/_deps/spdlog-src \
  -DFETCHCONTENT_SOURCE_DIR_cli11=/home/abmcar/DTVM/build/_deps/cli11-src \
  -DFETCHCONTENT_SOURCE_DIR_intx=/home/abmcar/DTVM/build/_deps/intx-src \
  -DFETCHCONTENT_SOURCE_DIR_rapidjson=/home/abmcar/DTVM/build/_deps/rapidjson-src
```

Note: FETCHCONTENT key names must be lowercase to match `FetchContent_Declare`
names in CMakeLists.txt. Mismatched keys are silently ignored.

For benchmark run commands and before/after comparison workflow, see the
`dtvm-evmone-benchmark` skill.
