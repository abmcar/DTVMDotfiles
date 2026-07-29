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
collision. Each link is user-level state created once per active skill; it is
not replicated per DTVM worktree.

`dotfiles/skills.map.sh` is the sole suppression-policy SSOT for both clients.
Every entry must use the supported `legacy-repo` ownership value; an unknown or
misspelled value fails before writes. Reconciliation requires `jq`; the
Linux/WSL bootstrap installs it before the first release. After changing the
map, run:

```bash
bash DTVMDotfiles/skills.sh sync
bash DTVMDotfiles/skills.sh check
bash DTVMDotfiles/release.sh
```

The real sync must precede release because it renders the checked-in Claude
adapter. Never edit `skillOverrides` or the Codex managed block by hand.

The reconciler owns only the closed `BEGIN`/`END` block in
`~/.codex/config.toml`. A fixed tail anchor remains outside that block as the
last line:

```toml
# BEGIN DTVMDotfiles managed agent skills
# END DTVMDotfiles managed agent skills
# DTVMDotfiles agent skills tail anchor
```

It preserves content outside the block and generates four static, name-based
`enabled = false` entries for these superseded DTVM-tracked skills:

- `archive`
- `dev-workflow`
- `dmir-compiler-analysis`
- `dtvm-perf-profile`

Codex inserts newly created marketplace and plugin tables before a trailing
comment. The tail anchor gives Codex an insertion point after `END`, so those
tables remain outside the managed block. The entries are rendered from
`dotfiles/skills.map.sh`. This verified Codex 0.145.0 interface does not require
worktree enumeration or path escaping.

When migrating an old EOF-only block, preserve and move out the suffix starting
at the first foreign table header, including headers with valid surrounding
whitespace; never delete that suffix. Missing block markers may be created.
Duplicate, partial, or reversed block markers, duplicate anchors, and an anchor
at or before `END` must fail closed.

Claude Code 2.1.129 and newer suppress the same names through project
`.claude/settings.json`:

```json
{
  "skillOverrides": {
    "archive": "off",
    "dev-workflow": "off",
    "dmir-compiler-analysis": "off",
    "dtvm-perf-profile": "off"
  }
}
```

`skills.sh sync` replaces the complete `skillOverrides` object with the
map-derived name-to-`"off"` mapping. It preserves other settings keys and
removes stale overrides. `skills.sh check` requires exact equality.
`release.sh` applies the same check before any write and directs drift recovery
to `bash DTVMDotfiles/skills.sh sync`.

After a successful release or sync, start a new task or restart the client so
discovery/config caches cannot retain old routing.

The map and checked-in Claude adapter describe the target policy. Editing or
committing them does not change either live client adapter; only an explicit
sync/release reconciles live user and project state. This integration branch
has not performed that live release.

## Positive skill routing

Route current work to the personal replacements:

- `dtvm-dev-workflow`: drive the default DTVM change lifecycle and gates
- `dtvm-dev-cycle`: run feature, architecture, breaking-change, and explicit
  `/dev-cycle` work
- `dtvm-archive`: archive exact merged changes only on an explicit request
- `dtvm-worktree-bootstrap`: create and fully initialize a DTVM worktree
- `dtvm-cold-compile-profile`: produce a reproducible cold-compile evidence bundle
- `dtvm-compiler-path-analysis`: map measured hotspots to current compiler source
- `dtvm-compile-time-optimize`: explicitly invoked end-to-end optimization loop
- `dtvm-run-reth-replay`: freeze, strictly replay, and seal a DTVM–Reth corpus
- `dtvm-write-report`: write and lint decision-first reader-facing DTVM reports

The two retired packages, `dmir-compiler-analysis` and `dtvm-perf-profile`,
remain versioned historical sources and are not published.

The old tracked skills are historical migration inputs, not workflow entry
points. Focused skills own one capability; the orchestrator composes them
without duplicating their detailed procedures.

## Worktrees

Use `dtvm-worktree-bootstrap`, which delegates to:

```bash
bash DTVMDotfiles/worktree-init.sh /absolute/worktree/path
```

Do not substitute raw `git worktree add` or a generic worktree skill. The DTVM
initializer handles submodules and dotfile links. The personal skill derives
CMake from current CI and runs the build gate after initialization.

For an already initialized worktree, `worktree-sync.sh` links project config
back to the primary checkout. `CLAUDE.local.md` is never linked. Worktree
initialization does not reconcile user-level skill links or Codex
configuration; `release.sh` and `skills.sh` own that independent lifecycle.

## Safe operations

| Goal | Command |
|---|---|
| No-write release preview | `RELEASE_CHECK=1 bash DTVMDotfiles/release.sh` |
| No-write personal-skill preview | `RELEASE_CHECK=1 bash DTVMDotfiles/skills.sh sync` |
| Render adapters and reconcile personal skills | `bash DTVMDotfiles/skills.sh sync` |
| Verify links and exact adapter state | `bash DTVMDotfiles/skills.sh check` |
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
