---
name: dtvm-worktree-bootstrap
description: Bootstrap and hard-gate an isolated DTVM worktree with DTVMDotfiles initialization, a current CI-derived local CMake configuration, and a verified dtvmapi build. Use when creating a DTVM worktree for a branch, experiment, optimization, or parallel implementation.
---

# DTVM Worktree Bootstrap

Treat the worktree as **sealed** only after initialization, configuration, and
verification all pass. Run from the primary DTVM checkout, never from a nested
worktree.

## 1. Resolve the target

Set an explicit branch, derive the destination under `.worktrees/`, and name
the start point for a genuinely new branch:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
BRANCH="<branch>"
BASE_REF="<explicit base for a new branch>"
WORKTREE_PATH="$REPO_ROOT/.worktrees/$BRANCH"
```

Verify:

```bash
test -x "$REPO_ROOT/DTVMDotfiles/worktree-init.sh"
git -C "$REPO_ROOT" worktree list --porcelain
git -C "$REPO_ROOT" check-ref-format --branch "$BRANCH"
test ! -e "$WORKTREE_PATH"
# Required only when neither the local nor origin branch exists
git -C "$REPO_ROOT" rev-parse --verify "$BASE_REF^{commit}"
```

Resolve all three branch modes:

1. `refs/heads/$BRANCH` exists: use the existing local branch.
2. `refs/remotes/origin/$BRANCH` exists but the local branch does not: track
   that exact remote branch.
3. Neither exists: create from the explicit `BASE_REF`.

Do not silently use the primary checkout's current `HEAD` as the start point.
Stop on an occupied destination, an ambiguous/missing base, or a branch already
checked out elsewhere.

Completion criterion: the branch mode and exact start commit are recorded, the
destination is absent, and the DTVMDotfiles initializer is executable.

## 2. Create and initialize

Create the worktree with exactly one of:

```bash
# Existing local branch
git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" "$BRANCH"

# Remote-only branch
git -C "$REPO_ROOT" worktree add --track -b "$BRANCH" \
  "$WORKTREE_PATH" "origin/$BRANCH"

# Genuinely new branch from the predeclared base
git -C "$REPO_ROOT" worktree add -b "$BRANCH" \
  "$WORKTREE_PATH" "$BASE_REF"
```

Then run the DTVM initializer:

```bash
(
  cd "$REPO_ROOT"
  bash DTVMDotfiles/worktree-init.sh "$WORKTREE_PATH"
)
```

The initializer is the single source of truth for recursive submodules and
DTVMDotfiles links. Do not reproduce those operations in this skill.

Completion criterion: the initializer exits zero, recursive submodules have no
`-` prefix in `git -C "$WORKTREE_PATH" submodule status --recursive`, and these
checks pass:

```bash
test -e "$WORKTREE_PATH/.claude"
test -e "$WORKTREE_PATH/CLAUDE.md"
test -e "$WORKTREE_PATH/AGENTS.md"
```

## 3. Derive a CI-based local build

Read the current EVM job and option mapping before configuring:

```bash
rg -n "evm|RUN_MODE|TestSuite|ENABLE_GAS|CPU_EXCEPTION|VIRTUAL_STACK" \
  "$WORKTREE_PATH/.github/workflows/dtvm_evm_test_x86.yml" \
  "$WORKTREE_PATH/.ci/run_test_suite.sh"
```

Treat those files as authoritative. The command below is the local
semantic-flags variant of the current release performance-baseline job in
`dtvm_evm_test_x86.yml`:

```bash
cmake -S "$WORKTREE_PATH" -B "$WORKTREE_PATH/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF \
  -DZEN_ENABLE_EVM=ON \
  -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON \
  -DZEN_ENABLE_CPU_EXCEPTION=ON \
  -DZEN_ENABLE_VIRTUAL_STACK=ON
```

It is intentionally not a byte-for-byte CI reproduction: it leaves the CI
`LLVM_SYS_150_PREFIX`/`LLVM_DIR`/`PATH`, Ninja generator, sccache compiler
launchers, and fixed `-j 16` parallelism to the local environment. Record that
delta in the worktree handoff. When exact CI reproduction is required, copy
those environment settings, `-G Ninja`,
`-DCMAKE_{C,CXX}_COMPILER_LAUNCHER=sccache`, and build parallelism from the
current workflow instead of using this local variant.

For another named CI job, derive its flags exactly from the two authoritative
files and state the delta. Do not add
`ZEN_ENABLE_JIT_PRECOMPILE_FALLBACK=ON` unless that job enables it; the option
is a hard gate only for the performance-baseline configuration above.

Completion criterion: CMake exits zero, the local-vs-CI delta is recorded, and
`CMakeCache.txt` records every selected option. For the performance-baseline
local variant above, this includes
`ZEN_ENABLE_JIT_PRECOMPILE_FALLBACK:BOOL=ON`.

## 4. Build and hard-gate

```bash
cmake --build "$WORKTREE_PATH/build" --target dtvmapi \
  --parallel "$(getconf _NPROCESSORS_ONLN)"
test -f "$WORKTREE_PATH/build/lib/libdtvmapi.so"
git -C "$REPO_ROOT" worktree list --porcelain
```

Completion criterion: the build exits zero without new compiler warnings,
`libdtvmapi.so` exists, and Git lists the destination on the intended branch.

Report the branch, absolute worktree path, initializer result, exact CMake
command, build result, and absolute library path. A partial worktree is not a
successful bootstrap.
