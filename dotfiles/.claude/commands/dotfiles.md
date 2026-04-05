---
description: Manage DTVMDotfiles sync (status/release/store)
---

# DTVMDotfiles Management

The user invoked `/dotfiles` with arguments: $ARGUMENTS

## Operations

Based on the arguments, execute the appropriate operation:

### `status` (or no arguments)
Run `bash DTVMDotfiles/diff.sh` and present the drift report to the user.

### `release`
Run `bash DTVMDotfiles/release.sh` to deploy dotfiles configuration to the workspace.
Show the manifest summary after completion.

### `store`
Run `bash DTVMDotfiles/store.sh` to capture current workspace configuration back to dotfiles.
Remind the user to commit changes in DTVMDotfiles if needed.

## Important
- Always run the script from the project root directory
- The manifest file `.claude/.dtvm-manifest.json` tracks which files are managed
- Unmanaged files in `.claude/` are never touched by release/store
- After store, suggest running `cd DTVMDotfiles && git diff` to review changes
