---
name: worktree-bootstrap
description: Create and fully initialize a DTVM git worktree (submodules + dotfiles sync + cmake). Supersedes superpowers:using-git-worktrees for DTVM.
---

# Worktree Bootstrap (DTVM)

Any time you need an isolated DTVM worktree — new branch, experimental
optimization, parallel work, or before `superpowers:executing-plans`.

**Supersedes `superpowers:using-git-worktrees` inside the DTVM repo.** The
upstream skill targets generic Node/Rust/Python/Go projects and skips
everything DTVM-specific (submodules, dotfiles, cmake).

Invoke with a branch name. Worktree always created at `.worktrees/<branch>`
(convention in `CLAUDE.md` — no other location is supported).

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

### 2. Init submodules + sync dotfiles + seed deps

The worktree must already exist from step 1 — `worktree-init.sh` is a
post-creation initializer, not an end-to-end bootstrapper. It `cd`s into
the path you pass.

```bash
bash DTVMDotfiles/worktree-init.sh "$WORKTREE_PATH"
```

Runs recursive submodule init (`evmc/`, `tests/wast/spec`), symlinks
`.claude/` config + `CLAUDE.md` + utility scripts from the main repo, and
hardlinks CMake FetchContent sources from the main build's `_deps/` to
skip re-download. The same script backs the SessionStart hook for agent
worktrees, so behavior is identical across manual and agent paths.

### 3. CMake configure

```bash
cmake -B "$WORKTREE_PATH/build" -S "$WORKTREE_PATH" \
    -DCMAKE_BUILD_TYPE=Debug -DZEN_ENABLE_MULTIPASS_JIT=ON
```

Adjust flags per task:
- Singlepass only: `-DZEN_ENABLE_SINGLEPASS_JIT=ON`
- Release: `-DCMAKE_BUILD_TYPE=Release`
- CI-faithful EVM build: see `.claude/rules/dtvm-build-config.md`

CMake finds the pre-seeded `*-src/` under `build/_deps/` and skips download.

### 4. Verify

```bash
cmake --build "$WORKTREE_PATH/build" --target dtvmapi -j$(nproc)
ls "$WORKTREE_PATH/build/lib/libdtvmapi.so"
```

Compilation benefits from `ccache` when `CMAKE_C/CXX_COMPILER_LAUNCHER` is
exported from your shell rc — same object files across worktrees hit cache.

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
