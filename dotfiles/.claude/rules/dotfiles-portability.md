---
description: Enforces portable paths in DTVMDotfiles-managed files. Triggered when editing .claude/ rules, commands, or settings.
globs:
  - .claude/rules/**
  - .claude/commands/**
  - .claude/settings.*
  - CLAUDE.md
alwaysApply: false
---

# Dotfiles Portability Constraint

Files under `.claude/` and `CLAUDE.md` are synced across machines via
DTVMDotfiles. **Never write machine-specific absolute paths**
(e.g. `/home/abmcar/DTVM/...`, `/Users/foo/...`) in these files.

`CLAUDE.local.md` is also listed in `MIRRORED_ITEMS` (see
`DTVMDotfiles/lib/sync_common.sh`), but in practice it diverges per machine
and is treated as single-user state. Absolute paths are tolerated there —
just be aware that `store.sh`/`release.sh` round-trips can carry WSL2 paths
to Mac and vice versa, so prefer `~/`-relative when the same content makes
sense on both machines.

## Allowed path styles

| Style | Example | When to use |
|-------|---------|-------------|
| Repo-relative | `evmone/`, `build/lib/libdtvmapi.so` | Paths inside the DTVM repo |
| Home-relative | `~/evmone/`, `~/dtvm-baseline/` | Paths outside the repo but under $HOME |
| Generic placeholder | `<baseline-worktree>/build-baseline/` | When the exact path varies |

## Where absolute paths ARE acceptable

- `CLAUDE.local.md` — machine-specific in practice (single-user state)
- Memory files (`~/.claude/projects/*/memory/`) — per-machine

## Common mistake

Using `replace_all` to fix a variable like `$DTVM_ROOT` without checking
each occurrence. Some sites need repo-relative paths, others need `~/` paths.
Always verify each replacement site individually.
