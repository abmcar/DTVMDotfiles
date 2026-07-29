# Change: Validate generated worktree content from its authoritative source

- **Status**: Accepted
- **Date**: 2026-07-28
- **Tier**: Light

## Overview

Make DTVM worktree initialization distinguish deterministic local adapters from
foreign tracked-file drift. Generate tracked `AGENTS.md` from the
DTVMDotfiles `dotfiles/CLAUDE.md` source, and validate tracked
`.claude/skills` against the target worktree's own Git state.

## Motivation

DTVMDotfiles release intentionally leaves the main DTVM checkout's tracked
`AGENTS.md` as an uncommitted generated diff. Requiring a new clean worktree's
committed `AGENTS.md` to match that main-checkout file rejects the normal
release state and prevents every bootstrap.

## Impact

The worktree synchronization contract changes for two DTVM-tracked paths:

- A clean tracked `AGENTS.md` may be refreshed to the deterministic
  DTVMDotfiles adapter. An existing exact generated diff is idempotent; staged,
  type, mode, or non-generated worktree drift fails before writes.
- Tracked `.claude/skills` remains branch-owned and must be Git-clean. It is
  not compared with another checkout.

The focused real-release-state regression is invoked by the shared agent-skill
integration test.

## Checklist

- [x] Implementation complete
- [x] Tests added/updated
- [x] Module specs in `docs/modules/` updated (not applicable: DTVMDotfiles tooling only)
- [x] Build and tests pass (build not applicable; shell syntax and integration tests pass)
