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

Files under `.claude/`, `CLAUDE.md`, and `CLAUDE.local.md` are synced across
machines via DTVMDotfiles. **Never write machine-specific absolute paths**
(e.g. `/home/abmcar/DTVM/...`, `/Users/foo/...`) in these files.

## Allowed path styles

| Style | Example | When to use |
|-------|---------|-------------|
| Repo-relative | `evmone/`, `build/lib/libdtvmapi.so` | Paths inside the DTVM repo |
| Home-relative | `~/evmone/`, `~/dtvm-baseline/` | Paths outside the repo but under $HOME |
| Generic placeholder | `<baseline-worktree>/build-baseline/` | When the exact path varies |

## Where absolute paths ARE acceptable

- `CLAUDE.local.md` — machine-specific, not synced
- Memory files (`~/.claude/projects/*/memory/`) — per-machine

## Common mistake

Using `replace_all` to fix a variable like `$DTVM_ROOT` without checking
each occurrence. Some sites need repo-relative paths, others need `~/` paths.
Always verify each replacement site individually.
