---
name: worktree-bootstrap
description: Create and fully initialize a DTVM git worktree (submodules + dotfiles sync + cmake). The authoritative DTVM worktree skill — generic worktree skills don't init submodules or sync dotfiles.
---

# Worktree Bootstrap (DTVM)

Any time you need an isolated DTVM worktree — new branch, experimental
optimization, parallel work, or before executing a multi-step plan that
needs an isolated workspace.

**Authoritative DTVM worktree skill.** Generic worktree skills target generic Node/Rust/Python/Go projects and skip submodules, dotfiles, and cmake. Use this skill instead.

Invoke with a branch name. Worktree always created at `.worktrees/<branch>`.

## Steps

Execute in order. Stop and report on any failure.

### 1. Create worktree

New branch:
```bash
BRANCH="<branch-name>"
WORKTREE_PATH=".worktrees/$BRANCH"
git worktree add "$WORKTREE_PATH" -b "$BRANCH"
```

Existing branch:
```bash
git worktree add "$WORKTREE_PATH" "$BRANCH"
```

### 2. Init submodules + sync dotfiles

The worktree must already exist from step 1 — `worktree-init.sh` is a
post-creation initializer, not an end-to-end bootstrapper. It `cd`s into
the path you pass.

```bash
bash DTVMDotfiles/worktree-init.sh "$WORKTREE_PATH"
```

Runs recursive submodule init (`evmc/`, `tests/wast/spec`) with command-scoped
`protocol.file.allow=always` for local alternates, then symlinks `.claude/`
config + `CLAUDE.md` + utility scripts from the main repo.

`worktree-init.sh` also maintains a local bare mirror cache for the DTVM
submodule graph under `${DTVM_GIT_MIRROR_DIR:-$HOME/.cache/git-mirrors}`. It
uses command-scoped `url.<mirror>.insteadOf` rewrites, so it does not need
machine-wide Git URL rewrite entries. Default behavior:
- Missing mirrors are seeded from existing `.git/modules/...` repositories when
  available; otherwise they are cloned on first use.
- Existing mirrors are reused without a network refresh.
- If submodule update fails, existing mirrors are refreshed once and the update
  is retried.

Optional controls:
- `DTVM_WORKTREE_INIT_USE_GIT_MIRRORS=0` disables the mirror cache for one run.
- `DTVM_WORKTREE_INIT_REFRESH_GIT_MIRRORS=1` refreshes existing mirrors before
  submodule init.
- `DTVM_GIT_MIRROR_DIR=/path/to/cache` changes the cache location.

CMake FetchContent reuse is handled at configure time through
`FETCHCONTENT_BASE_DIR`, not by this initializer.

### 3. CMake configure

**Default (CI-faithful EVM build — use this unless you have a specific reason not to):**

```bash
cmake -B "$WORKTREE_PATH/build" -S "$WORKTREE_PATH" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZEN_ENABLE_MULTIPASS_JIT=ON \
    -DZEN_ENABLE_SINGLEPASS_JIT=OFF \
    -DZEN_ENABLE_EVM=ON \
    -DZEN_ENABLE_LIBEVM=ON \
    -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON \
    -DZEN_ENABLE_CPU_EXCEPTION=ON \
    -DZEN_ENABLE_VIRTUAL_STACK=ON
```

**Critical — `ZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON` is not optional.** CI runs
with it ON, and some peephole rules have pathological compile-time loops that
only get masked by the interpreter fallback. Building with `FALLBACK=OFF`
silently hangs on those cases (2026-04-24 incident, see
`docs/research/directions/peephole-optimization/log.md`). If you need to
experiment with flags, keep this one ON.

Adjust per task:
- Debug build: override `-DCMAKE_BUILD_TYPE=Debug`
- WASM-only: replace `-DZEN_ENABLE_MULTIPASS_JIT=ON` with `-DZEN_ENABLE_SINGLEPASS_JIT=ON`
  and drop `-DZEN_ENABLE_EVM=ON -DZEN_ENABLE_LIBEVM=ON`
- CI-faithful env-driven variants (gas register, interp/multipass matrix, etc.):
  see `.claude/rules/dtvm-build-config.md` and `.ci/run_test_suite.sh`

### 4. Verify

```bash
cmake --build "$WORKTREE_PATH/build" --target dtvmapi -j$(nproc)
ls "$WORKTREE_PATH/build/lib/libdtvmapi.so"
```

## Output

Report:
- Worktree path and branch name
- `worktree-init.sh` result line
- CMake configure + build result
- Full path to `libdtvmapi.so`

## Cleanup

```bash
rm -rf "$WORKTREE_PATH"
git worktree prune
```

Do NOT use `git worktree remove` — it fails on worktrees with submodules.
Never remove the permanent baseline worktree (see `.claude/rules/dtvm-perf-worktree-lab.md` for its location).
