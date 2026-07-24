---
description: DTVMDotfiles ownership and synchronization rules. Use when editing DTVMDotfiles-managed project config, personal DTVM skills, release/store scripts, or DTVM worktree setup.
paths:
  - ".claude/**"
  - "CLAUDE.md"
  - "DTVMDotfiles/**"
---

# DTVMDotfiles Usage

Treat the checked-in scripts as authoritative. This rule records routing and
invariants; implementation and recovery details live in `DTVMDotfiles/README.md`
and `DTVMDotfiles/SETUP_GUIDE.md`.

## Two ownership flows

### Project dotfiles

- SSOT: `DTVMDotfiles/dotfiles/`
- Deploy: `bash DTVMDotfiles/release.sh` (SSOT → DTVM checkout)
- Collect live edits: `bash DTVMDotfiles/store.sh` (DTVM checkout → SSOT)
- Detect drift: `bash DTVMDotfiles/diff.sh`

`MIRRORED_ITEMS` in `DTVMDotfiles/lib/sync_common.sh` defines the managed set.
Release writes a per-file manifest; store collects only manifest entries.
Unmanaged files are not swept into DTVMDotfiles.

Never run release after editing a managed live file but before store: release
may replace the edit with the SSOT copy. The same local-hash gate applies when
a file disappears from the new manifest. `AGENTS.md` and `GEMINI.md` are
generated from `CLAUDE.md`; never edit them directly.

`AGENTS.md` is tracked by DTVM and can show a local generated diff after
release. DTVMDotfiles never stages, commits, or pushes it. Keep the DTVM index
empty and never include that derived diff in a DTVM-origin change.

`CLAUDE.local.md` is machine-local and is not collected. User-level
`~/.claude/CLAUDE.md` belongs to the separate `claude-sync` system.

### Personal DTVM skills

- SSOT: `DTVMDotfiles/skills/`
- Reconcile only: `bash DTVMDotfiles/skills.sh sync`
- Verify derived state: `bash DTVMDotfiles/skills.sh check`
- Normal deployment: `bash DTVMDotfiles/release.sh`

Lifecycle directories:

- `active/`: each direct child is published
- `incubator/`: versioned draft, never published
- `retired/`: versioned history, never published

Edit this SSOT directly; `store.sh` never collects personal skills from DTVM
or from a user discovery directory. Personal skill source is committed and
pushed only to the DTVMDotfiles origin. It must never be copied, staged, or
pushed in the DTVM origin.

## Personal-skill reconciliation

Each active skill is linked independently into both namespaces:

```text
~/.agents/skills/<name>
~/.claude/skills/<name>
```

DTVMDotfiles owns those individual links, not either parent directory. An
existing foreign file, directory, symlink, or symlinked discovery root is a
hard collision: fail closed and leave it untouched. Never recursively replace
either discovery directory, and do not use `RELEASE_FORCE=1` to bypass a skill
collision.

The reconciler owns only the following marked block at the end of
`~/.codex/config.toml`:

```toml
# BEGIN DTVMDotfiles managed agent skills
# END DTVMDotfiles managed agent skills
```

It preserves content outside the block and generates exact-path
`enabled = false` entries for these superseded DTVM-tracked skills in every
worktree currently known to Git:

- `dtvm-perf-profile`
- `dmir-compiler-analysis`

Keeping the array-of-tables block at EOF prevents later bare TOML keys from
being scoped into the last skill entry. The names are declared in
`dotfiles/skills.map.sh`. Missing markers may be created; duplicate, partial,
or reversed markers must fail closed. After a successful sync, start a new
task or restart the client so discovery/config caches cannot retain old
routing.

## Positive skill routing

Route current work to the personal replacements:

- `dtvm-worktree-bootstrap`: create and fully initialize a DTVM worktree
- `dtvm-cold-compile-profile`: produce a reproducible cold-compile evidence bundle
- `dtvm-compiler-path-analysis`: map measured hotspots to current compiler source
- `dtvm-write-report`: write and lint decision-first reader-facing DTVM reports
- `dtvm-compile-time-optimize`: explicitly invoked end-to-end optimization loop

The old tracked skills are historical migration inputs, not workflow entry
points. Focused skills own one capability; the orchestrator composes them
without duplicating their detailed procedures.

## Worktrees

Use `dtvm-worktree-bootstrap`, which delegates to:

```bash
bash DTVMDotfiles/worktree-init.sh /absolute/worktree/path
```

Do not substitute raw `git worktree add` or a generic worktree skill. The DTVM
initializer handles submodules and dotfile links, then refreshes the Codex
exact-path disables after Git knows about the new worktree. The personal skill
derives CMake from current CI and runs the build gate after initialization.

For an already initialized worktree, `worktree-sync.sh` links project config
back to the primary checkout and then runs the same personal-skill
reconciliation. `CLAUDE.local.md` is never linked.

## Safe operations

| Goal | Command |
|---|---|
| No-write release preview | `RELEASE_CHECK=1 bash DTVMDotfiles/release.sh` |
| No-write personal-skill preview | `RELEASE_CHECK=1 bash DTVMDotfiles/skills.sh sync` |
| Reconcile personal skills only | `bash DTVMDotfiles/skills.sh sync` |
| Verify personal-skill state | `bash DTVMDotfiles/skills.sh check` |
| Collect a managed live edit | `bash DTVMDotfiles/store.sh` |
| Check project-dotfile drift | `bash DTVMDotfiles/diff.sh` |

Resolve failures at the exact reported object and rerun the idempotent command.
An absolute link into an older/moved DTVMDotfiles checkout is deliberately
foreign: prove it targets an obsolete same-name skill, remove only that link,
then sync. Do not perform broad cleanup. The integration test is
`bash DTVMDotfiles/tests/agent_skills_test.sh`.

## Response requirements

For DTVMDotfiles work, state:

1. which script is authoritative;
2. which of the two ownership flows applies;
3. which Git origin owns the source;
4. the validation and follow-up command.

For personal skills, explicitly confirm that skill source and commits stay in
DTVMDotfiles, the DTVM index remains untouched, and nothing is pushed to DTVM
origin.
