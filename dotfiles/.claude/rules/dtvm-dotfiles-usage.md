---
description: DTVMDotfiles workflow for syncing Claude Code configuration between machines. Use when operating DTVMDotfiles, running release.sh or store.sh, editing exclude.map.sh, or syncing dotfiles changes between DTVMDotfiles and the parent DTVM workspace.
globs: []
alwaysApply: false
---

# DTVMDotfiles Usage

Treat the checked-in DTVMDotfiles scripts as authoritative.

Read these files before answering any workflow question or making changes:

- `DTVMDotfiles/release.sh`
- `DTVMDotfiles/store.sh`
- `DTVMDotfiles/diff.sh`
- `DTVMDotfiles/lib/sync_common.sh`
- `DTVMDotfiles/dotfiles/exclude.map.sh`

## Architecture

DTVMDotfiles syncs configuration between machines using four scripts:

- **`release.sh`**: `DTVMDotfiles/dotfiles/` → parent DTVM repo (file-level sync + manifest)
- **`store.sh`**: parent DTVM repo → `DTVMDotfiles/dotfiles/` (manifest-guided)
- **`diff.sh`**: compare deployed vs dotfiles, detect drift
- **`worktree-sync.sh`**: symlink dotfiles from parent repo into a git worktree

### Manifest

`release.sh` generates `.claude/.dtvm-manifest.json` in the parent directory,
tracking every managed file path and its content hash (sha256, first 12 chars).

- **release.sh** uses file-level sync (no `rm -rf`), then writes the manifest
- **store.sh** reads the manifest and only collects managed files back
- **diff.sh** compares manifest hashes against current file states
- Unmanaged files (created locally, not from dotfiles) are never touched

### What gets synced

All items in `MIRRORED_ITEMS` (defined in `lib/sync_common.sh`):
- `.claude/` — rules, commands, agents, hooks, settings
- `CLAUDE.md` — development guide (authority source)
- `CLAUDE.local.md` — local environment config
- `init.sh`, `perf/*.sh`, `perf/*.hex` — utility scripts

### What does NOT get synced

- `.agents/skills/` — upstream-tracked skills, managed by the DTVM repo
- Files in `.claude/` not originating from dotfiles (shown as "unmanaged" in diff.sh)

### Worktree sync

Git worktrees only contain tracked files. Since dotfiles-managed content is
gitignored, worktrees lack all configuration. `worktree-sync.sh` creates
symlinks from the worktree back to the main repo, so changes via `release.sh`
are immediately visible. Run once per worktree after creation:

```bash
bash DTVMDotfiles/worktree-sync.sh <worktree-path>
```

The script must be invoked from the main repo (where DTVMDotfiles lives).
It symlinks `.claude/` subdirectories (rules, commands, hooks, agents),
settings files, `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `GEMINI.md`,
`init.sh`, and `perf/`. It skips `.claude/skills/` (git-tracked).

### Additional release.sh behavior

- Generates `.git/info/exclude` from `dotfiles/exclude.map.sh`
- Creates `AGENTS.md` and `GEMINI.md` as copies of `CLAUDE.md`
- Syncs `.claude/commands` to `~/.codex/prompts`
- Cleans up files that were in the previous manifest but no longer in dotfiles

## Use This Rule For

- Explaining how to bootstrap a workspace with `setup_from_dotfiles.sh`
- Explaining or editing the `release.sh` / `store.sh` / `diff.sh` / `worktree-sync.sh` workflow
- Syncing dotfiles into a new git worktree
- Explaining why `.git/info/exclude` contains generated entries
- Debugging why a dotfiles-managed file did or did not sync
- Understanding which files are managed vs unmanaged

## Workflow

1. Identify whether the request is about setup, release, store, diff, or
   exclude generation.
2. Re-read the relevant script before making assertions. The shell scripts
   are the source of truth, not this rule.
3. To add a new file to sync: add it to `MIRRORED_ITEMS` in
   `lib/sync_common.sh`, then run `release.sh`.
4. To check for drift: run `diff.sh`.

## Output Requirements

When answering a DTVMDotfiles usage question, include:

- which script or file is authoritative for that answer
- whether the behavior happens during `release.sh`, `store.sh`, or both
- any follow-up command the user should run
