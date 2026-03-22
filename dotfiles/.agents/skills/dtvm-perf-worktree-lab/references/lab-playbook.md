# DTVM Perf Lab Playbook

## Keep/Remove Policy

Keep by default:

- `/home/abmcar/DTVM`
- one active branch worktree such as `/home/abmcar/DTVM-<topic>`
- one active evmone checkout such as `/home/abmcar/evmone-for-test-<topic>`

Remove after use:

- detached baseline worktrees
- stale `DTVM-*` worktrees not tied to the current branch
- stale `evmone-for-test-*` directories from old experiments

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

Create detached baseline worktree:

```bash
git -C /home/abmcar/DTVM worktree add /home/abmcar/DTVM-topic-base <commit>
cd /home/abmcar/DTVM-topic-base
git submodule update --init --recursive
```

Remove temporary worktree:

```bash
git -C /home/abmcar/DTVM worktree remove --force /home/abmcar/DTVM-topic-base
```

Replace evmone VM library:

```bash
cp /home/abmcar/DTVM-topic/build/lib/libdtvmapi.so \
  /home/abmcar/evmone-for-test-topic/
```

## Baseline Build Shortcut

If a temporary baseline only needs `dtvmapi`, configure it with local source
overrides for fetched dependencies instead of downloading them again:

```bash
cmake -S . -B build-perf-lite \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF \
  -DZEN_ENABLE_EVM=ON \
  -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_SPEC_TEST=OFF \
  -DFETCHCONTENT_SOURCE_DIR_SPDLOG=<active-build>/_deps/spdlog-src \
  -DFETCHCONTENT_SOURCE_DIR_CLI11=<active-build>/_deps/cli11-src \
  -DFETCHCONTENT_SOURCE_DIR_INTX=<active-build>/_deps/intx-src \
  -DFETCHCONTENT_SOURCE_DIR_BOOST=<active-build>/_deps/boost-src \
  -DFETCHCONTENT_SOURCE_DIR_RAPIDJSON=<active-build>/_deps/rapidjson-src \
  -G Ninja
cmake --build build-perf-lite -j$(nproc) --target dtvmapi
```

This is for local perf comparison only. Do not present it as CI reproduction.
