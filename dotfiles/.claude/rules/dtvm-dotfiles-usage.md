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
- `DTVMDotfiles/lib/sync_common.sh`
- `DTVMDotfiles/dotfiles/exclude.map.sh`

## Architecture

DTVMDotfiles syncs configuration between machines using two scripts:

- **`store.sh`**: parent DTVM repo → `DTVMDotfiles/dotfiles/`
- **`release.sh`**: `DTVMDotfiles/dotfiles/` → parent DTVM repo

### What gets synced

All items in `MIRRORED_ITEMS` (defined in `lib/sync_common.sh`):
- `.claude/` — rules (auto-loaded) and commands (user-invoked via `/name`)
- `CLAUDE.md` — development guide (authority source)
- `CLAUDE.local.md` — local environment config
- `init.sh`, `perf/*.sh`, `perf/*.hex` — utility scripts

### What does NOT get synced

- `.agents/skills/` — upstream-tracked skills are managed by the DTVM repo, not DTVMDotfiles
- `openspec/` — managed by DTVM main repo

### Additional release.sh behavior

- Generates `.git/info/exclude` from `dotfiles/exclude.map.sh`
- Creates `AGENTS.md` and `GEMINI.md` as copies of `CLAUDE.md`
- Syncs `.claude/commands` to `~/.codex/prompts`

## Use This Rule For

- Explaining how to bootstrap a workspace with `setup_from_dotfiles.sh`
- Explaining or editing the `release.sh` / `store.sh` workflow
- Explaining why `.git/info/exclude` contains generated entries
- Debugging why a dotfiles-managed file did or did not sync

## Workflow

1. Identify whether the request is about setup, release, store, or exclude
   generation.
2. Re-read the relevant script before making assertions. The shell scripts
   are the source of truth, not this rule.
3. To add a new file to sync: add it to `MIRRORED_ITEMS` in
   `lib/sync_common.sh`.

## Output Requirements

When answering a DTVMDotfiles usage question, include:

- which script or file is authoritative for that answer
- whether the behavior happens during `release.sh`, `store.sh`, or both
- any follow-up command the user should run
