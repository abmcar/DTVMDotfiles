---
description: Manage DTVMDotfiles sync (status / release / store / worktree / setup)
---

# DTVMDotfiles Management

The user invoked `/dotfiles` with arguments: $ARGUMENTS

## Operations

Based on the arguments, execute the appropriate operation:

### `status` (or no arguments)
Run `bash DTVMDotfiles/diff.sh` and present the drift report.

### `release`
Run `bash DTVMDotfiles/release.sh` to deploy SSOT → parent DTVM repo.
- Pre-flight: gate aborts if any parent file was modified since last manifest write (per 2026-05-11 dest-hash gate).
- For dry-run: `RELEASE_CHECK=1 bash DTVMDotfiles/release.sh`
- To force-overwrite local edits: `RELEASE_FORCE=1 bash DTVMDotfiles/release.sh`
Show the manifest summary after completion.

### `store`
Run `bash DTVMDotfiles/store.sh` to capture parent repo → SSOT.
Remind the user to commit changes in DTVMDotfiles if needed.

### `worktree-sync <path>`
Run `bash DTVMDotfiles/worktree-sync.sh <path>` to symlink dotfiles into an existing git worktree.
Requires the worktree path as argument.

### `worktree-init <path>`
Run `bash DTVMDotfiles/worktree-init.sh <path>` to bootstrap a freshly created worktree:
submodule init + dotfiles sync + FetchContent seed. This is what the agent-isolation
SessionStart hook calls. Prefer the `worktree-bootstrap` skill for new worktrees;
this command is for repairing an existing worktree.

### `setup`
Run `bash DTVMDotfiles/setup_from_dotfiles.sh` for first-time DTVM workspace bootstrap.
Only use on a fresh DTVMDotfiles checkout where the parent DTVM repo doesn't exist yet.

## Important
- Always run the script from the project root directory
- The manifest file `.claude/.dtvm-manifest.json` tracks which files are managed
- Unmanaged files in `.claude/` are never touched by release/store
- After store, suggest running `cd DTVMDotfiles && git diff` to review changes
- After release/store, also remind the user to commit + push DTVMDotfiles
