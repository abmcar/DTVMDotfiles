# Change: DTVMDotfiles-managed personal DTVM skills

- **Status**: Implemented
- **Date**: 2026-07-23
- **Tier**: Full

## Overview

Make DTVMDotfiles the single source of truth (SSOT) for a small set of
personally maintained DTVM skills. DTVMDotfiles versions the skills in its own
origin and exposes only active skills through per-skill links in the user-level
Claude and Codex discovery directories. DTVM's tracked skills remain unchanged
in every DTVM checkout.

The release path also maintains a narrowly marked block at the end of Codex's
user configuration. That block disables the two superseded,
repository-tracked skills for every currently known DTVM worktree:

- `dtvm-perf-profile`
- `dmir-compiler-analysis`

Project guidance routes new work to these personal skills:

- `dtvm-worktree-bootstrap`
- `dtvm-cold-compile-profile`
- `dtvm-compiler-path-analysis`
- `dtvm-compile-time-optimize`

This design applies the SSOT and progressive-disclosure principles commonly
used by Matt Pocock's skill workflow: each focused capability has one canonical
skill directory, the entry file stays oriented around when and how to use it,
and detailed resources are loaded only when the task needs them. No third-party
skill text is copied into this repository.

## Motivation

DTVM's repository-tracked profiling and compiler-analysis skills can lag the
local workflows used to investigate current compiler behavior. Updating those
files in DTVM would couple personal workflow maintenance to DTVM's product
history and would risk pushing machine- or user-specific process into the DTVM
origin.

Maintaining independent copies directly under `~/.agents/skills` or
`~/.claude/skills` is also insufficient:

- there is no durable, reviewable SSOT across machines;
- Claude and Codex copies can drift;
- a broad directory sync can overwrite unrelated user skills;
- exact Codex disable paths become stale when DTVM worktrees are added;
- agents can continue selecting the old repository skill unless routing and
  discovery are changed together.

DTVMDotfiles already owns the release and worktree-bootstrap boundaries. It is
therefore the appropriate repository for personal DTVM workflow policy, while
DTVM remains the source repository for product code and its tracked skills.

## Goals

1. Version personal DTVM skills in the DTVMDotfiles origin, never in the DTVM
   origin.
2. Establish `DTVMDotfiles/skills/` as the only editable source for these
   personal skills.
3. Represent skill maturity with explicit `active`, `incubator`, and `retired`
   lifecycle directories.
4. Expose each active skill independently in both user-level discovery
   directories.
5. Reconcile skills and Codex configuration through the normal `release.sh`
   path, and reconcile again when a DTVM worktree is initialized.
6. Refuse to overwrite files, directories, or symlinks owned by another
   system.
7. Preserve the bytes and relative order of user Codex configuration outside
   one clearly marked DTVMDotfiles-owned EOF block.
8. Route compile-time investigations through a reproducible profile, source
   analysis, minimal-change, and before/after verification loop.
9. Cover lifecycle transitions, collisions, configuration preservation,
   worktree discovery, and idempotence with isolated integration tests.

## Non-goals

- Modifying, deleting, renaming, or backporting DTVM's tracked
  `.agents/skills/dtvm-perf-profile` or
  `.agents/skills/dmir-compiler-analysis`.
- Publishing personal skills to the DTVM origin.
- Building a general-purpose plugin or package manager.
- Managing arbitrary third-party skills in the user's home directory.
- Overwriting a destination merely because it has the same skill name.
- Making `incubator` or `retired` skills discoverable.
- Running a benchmark, profiler, compiler analysis, or source change as a side
  effect of dotfiles release.
- Hot-reloading a Claude or Codex session that has already completed skill
  discovery.
- Storing credentials, machine-local paths, benchmark results, or build
  artifacts in the personal skill tree.

## Modules, interfaces, and seams

### Affected modules

This repository does not currently define module specifications under
`docs/modules/`. The affected responsibility areas are:

| Area | Responsibility |
|---|---|
| `skills/` | Personal skill SSOT and lifecycle |
| `skills.sh`, `lib/agent_skills.sh` | Check/preflight and reconcile active skill links and the Codex managed block |
| `release.sh`, `worktree-sync.sh` | Preflight before writes and invoke the shared reconciler at the deployment/worktree seams |
| `dotfiles/skills.map.sh` | Declarative list of tracked repository skills suppressed in Codex |
| `dotfiles/CLAUDE.md` | Positive task routing copied to DTVM's local `AGENTS.md` and `GEMINI.md` |
| setup and usage docs | Explain ownership, installation, collision handling, and restart requirements |
| integration tests | Exercise release behavior without touching the real home directory or DTVM checkout |

### Filesystem interface

The source layout is:

```text
DTVMDotfiles/
└── skills/
    ├── active/
    │   └── <skill-name>/
    │       ├── SKILL.md
    │       ├── agents/        # optional UI metadata
    │       ├── references/    # optional, loaded on demand
    │       ├── scripts/       # optional executable helpers
    │       └── assets/        # optional output inputs
    ├── incubator/
    └── retired/
```

For every directory immediately below `skills/active/`, release reconciles:

```text
~/.agents/skills/<skill-name>
    -> <DTVMDotfiles>/skills/active/<skill-name>

~/.claude/skills/<skill-name>
    -> <DTVMDotfiles>/skills/active/<skill-name>
```

The unit of ownership is one skill link. The destination directories themselves
are shared namespaces and are not owned by DTVMDotfiles.

### Command interface

The public entry points remain:

```bash
bash DTVMDotfiles/release.sh
bash DTVMDotfiles/skills.sh check
bash DTVMDotfiles/skills.sh sync
bash DTVMDotfiles/worktree-init.sh [--minimal] <worktree-path>
```

`release.sh` is the canonical deployment entry point. It preflights personal
skill/config collisions and removed-manifest safety before applying the
project-dotfiles release contract, then reconciles personal skill exposure and
the DTVMDotfiles-owned Codex configuration block.

`skills.sh check` is the read-only inspection entry point. `skills.sh sync`
applies only personal-skill link and managed-config reconciliation. This split
allows setup and normal upgrades to stay release-first while lifecycle work and
tests can address the personal-skill subsystem directly.

`worktree-init.sh` continues to initialize submodules and project dotfiles. It
delegates project linking to `worktree-sync.sh`, which refreshes personal
skill/configuration state after the new worktree becomes discoverable. Exact
paths for that worktree therefore do not require manual configuration.

### Codex configuration interface

DTVMDotfiles owns only the text between its start and end markers at EOF in
`~/.codex/config.toml`. The generated entries use exact `SKILL.md` paths and
`enabled = false` for the two superseded tracked skills in each worktree
reported by the DTVM git repository. EOF placement is required because TOML
array-of-tables has no marker-based scope reset; suffix keys would otherwise
belong to the final skill entry.

```toml
# BEGIN DTVMDotfiles managed agent skills
# END DTVMDotfiles managed agent skills
```

All content outside that block belongs to the user or another system. A
reconcile may move an existing managed block to EOF and replace its contents,
but it preserves unowned bytes and their relative order without reformatting
or reinterpreting them.

### Routing interface

The project-level `CLAUDE.md` is still the source copied locally to `AGENTS.md`
and `GEMINI.md`. It routes:

- worktree creation and initialization to `dtvm-worktree-bootstrap`;
- cold compilation measurement to `dtvm-cold-compile-profile`;
- source-level explanation of a measured compiler path to
  `dtvm-compiler-path-analysis`;
- the end-to-end verified optimization loop to
  `dtvm-compile-time-optimize`.

The old tracked skills are historical sources that may be inspected while
authoring the replacements. They are not workflow entry points.

### System seams

1. **Project mirroring versus personal skills**: `dotfiles/` continues to use
   manifest-bounded release/store semantics. `skills/` is edited directly in
   DTVMDotfiles and is exposed through links; it is not collected from DTVM.
2. **Repository ownership versus user discovery**: Git tracks skill content in
   DTVMDotfiles, while home-directory links only make that content
   discoverable.
3. **Worktree discovery versus Codex exact paths**: Git is authoritative for
   the set of currently known DTVM worktrees; the managed block is derived
   state.
4. **Disk state versus session state**: release changes files and links on disk,
   but skill discovery for an already running session may remain cached.
5. **DTVMDotfiles origin versus DTVM origin**: release writes local guidance
   into a DTVM checkout as it already does. It also refreshes DTVM's tracked
   `AGENTS.md` as local generated state, but never stages, commits, or pushes
   it; no personal skill source is added to DTVM commits.

## Invariants

1. **Origin isolation**: personal skill source is committed only to
   DTVMDotfiles. No implementation step stages or pushes it in a DTVM
   worktree.
2. **Single source of truth**: the canonical content is
   `DTVMDotfiles/skills/<lifecycle>/<name>`. User discovery locations contain
   links, not copied skill trees.
3. **Lifecycle visibility**: only immediate children of `skills/active/` are
   exposed. `incubator` and `retired` are versioned but undiscoverable.
4. **Focused names**: the four new names do not shadow the superseded tracked
   skill names.
5. **Per-skill ownership**: reconciliation may create, update, or remove only
   links that it can prove belong to this DTVMDotfiles skill set. It never owns
   all of `~/.agents/skills` or `~/.claude/skills`.
6. **Fail-closed collision handling**: an existing foreign file, directory, or
   symlink, or a symlink component in a write destination, causes a non-zero
   result and remains untouched. Users must inspect and resolve the collision
   explicitly.
7. **Scoped configuration mutation**: only one uniquely identifiable managed
   EOF block in Codex configuration may be replaced. Ambiguous marker state is
   an error, not permission to rewrite the file. A valid replacement is
   written through a temporary file in the config directory and an atomic
   `mv`.
8. **Complete known-worktree coverage**: each known DTVM worktree contributes
   disable entries for both superseded tracked skills. Reconciliation removes
   stale derived entries when Git no longer reports a worktree.
9. **Deterministic reconciliation**: the same SSOT, home path, and worktree set
   produce the same links and managed block. Re-running release is idempotent.
10. **Positive routing**: project guidance names the intended personal skill
    for each task. It does not depend solely on telling an agent what not to
    use.
11. **No session-state promise**: a successful reconcile guarantees disk state,
    not immediate rediscovery by a running agent session.
12. **Removed-file safety**: a manifest-managed file removed from the new SSOT
    receives the same local hash gate as an overwritten file. Forced removal
    backs up locally modified content outside the DTVM repository first. A
    DTVM-tracked path is never removed, even when its bytes match the old
    manifest.
13. **Origin guard**: release may create a local tracked `AGENTS.md` diff, but
    the DTVM index must remain empty and tracked DTVM skill files must remain
    unchanged.

## Skill boundaries

### `dtvm-worktree-bootstrap`

Owns `git worktree add`, complete initialization through the DTVMDotfiles
worktree scripts, CMake derivation from the current CI source of truth, and a
hard `dtvmapi` / `libdtvmapi.so` build gate. It is model-invoked for a DTVM
branch/worktree request and is not a generic Git worktree tutorial.

### `dtvm-cold-compile-profile`

Owns repeatable measurement of cold DTVM compilation. It records the clean
baseline commit, source status/patch, selected host identity, CMake cache,
binary, corpus, command, raw perf data/report, JIT dump, timings, metadata, and
an integrity manifest before calling a function a hotspot. It rejects
untracked source, dirty submodules, and corpus symlinks, bundles the profiler
implementation, and puts source/binary/cache/corpus identity guards in the
rerun script. Rerun still requires the recorded external repo/build/corpus
paths to exist. It reports inherited helper and inspection processes such as
`objdump` separately.

### `dtvm-compiler-path-analysis`

Owns source-level tracing of an already measured compiler hotspot from the
baseline bundle through the current EVM → dMIR → CGIR → RA → post-RA →
MC/object pipeline. It produces an evidence table, falsifiable hypotheses, and
a minimal implementation seam without changing source. Historical cost tables
are not treated as current evidence.

### `dtvm-compile-time-optimize`

Is available only through explicit invocation. It establishes a baseline,
uses the worktree-bootstrap skill only when isolated inputs are missing,
invokes the cold-profile and compiler-path-analysis skills, and hands an
evidence-backed minimal `src/**` change to `compiler-agent` under AGENTS
routing. It compares before/after results using the same ancestry, build,
corpus, normalized command, and a predeclared paired-sample policy. Acceptance
requires the full confidence interval to clear a frozen practical-effect
threshold, plus matching perf attribution and correctness gates; an unverified
change is never reported as an optimization.

## Migration

### Existing machine

1. Commit or store any pending edits to currently mirrored project dotfiles.
2. Update the DTVMDotfiles checkout to the revision containing this change.
3. Run `bash DTVMDotfiles/release.sh` from the DTVM workspace. The old
   DTVMDotfiles-managed `.agents/skills/worktree-bootstrap/SKILL.md` leaves the
   manifest in this migration. If it was locally modified, release aborts
   before writes; store/review it, then use explicit `RELEASE_FORCE=1` to back
   it up outside the DTVM repository and remove it. A DTVM-tracked path is
   never removed.
4. Run `bash DTVMDotfiles/skills.sh check`.
5. If release or check reports a foreign collision, inspect that exact path. Move,
   rename, or deliberately remove it only after establishing its owner, then
   rerun release.
6. Inspect the four links in both user discovery directories.
7. Inspect only the marked DTVMDotfiles block in `~/.codex/config.toml` and
   confirm that all current DTVM worktrees are represented.
8. Start a new Claude/Codex session, or restart the client where necessary.
9. Verify the DTVM index is empty and the two tracked legacy skill directories
   have no diff. A local generated `M AGENTS.md` is expected but must not be
   staged.

No DTVM branch, commit, or push is part of this migration. Release does refresh
the tracked `AGENTS.md` working-tree file locally.

### New machine

The existing bootstrap flow clones DTVMDotfiles, runs `release.sh`, and then
runs the released initialization script. Personal skill links and Codex
configuration therefore arrive through release; there is no separate skill
installer.

### New worktree

Use `dtvm-worktree-bootstrap`, which delegates to the DTVMDotfiles worktree
initializer. The initializer refreshes the managed Codex block after Git knows
about the new worktree. Start subsequent agent work in a new session so the
updated skill/configuration state is loaded.

### Lifecycle transition

- Develop a draft under `skills/incubator/<name>`.
- Promote it with a version-controlled move into `skills/active/<name>`, review
  its `SKILL.md`, and run release.
- Retire it with a version-controlled move into `skills/retired/<name>` and run
  release so DTVMDotfiles-owned discovery links are removed.

Moving a directory alone changes the SSOT; release is what reconciles derived
home-directory state.

### DTVMDotfiles checkout relocation

Absolute links into an older checkout are intentionally treated as foreign.
After proving with `readlink` that an exact same-name link targets an obsolete
`<old-checkout>/skills/active/<name>`, remove only that link and rerun sync.
The reconciler does not infer ownership across checkout paths.

## Failure modes and recovery

| Failure | Expected behavior | Recovery |
|---|---|---|
| Foreign destination has the same skill name | Abort without overwriting that path | Identify its owner; rename or remove it intentionally, then rerun release |
| Managed link points at an older checkout | Treat it as foreign; do not infer ownership across roots | Prove the exact old same-name target with `readlink`, remove only that link, then sync |
| Active skill is moved to `incubator` or `retired` | Remove only the corresponding DTVMDotfiles-owned links | Rerun release and verify with `readlink` |
| Codex file has no managed block | Add one while preserving existing content | Rerun release, then inspect the marked block |
| Codex file has malformed or duplicate markers | Fail closed rather than guess boundaries | Repair the marker structure manually from a backup, then rerun |
| A worktree was added outside the supported initializer | Its exact paths are absent until reconciliation | Run `release.sh` or the worktree initializer |
| A worktree was pruned | Its disable entries remain derived state until reconciliation | Run `release.sh` to regenerate the block |
| Current session still offers old discovery state | Files are correct but the process cache is stale | Start a new session or restart the client |
| A personal skill has invalid metadata or missing instructions | Link creation alone cannot make it usable | Fix and validate the skill in DTVMDotfiles, then rerun release |
| Release preflight finds a collision or malformed markers | Abort before project-dotfiles or personal-skill writes | Resolve the exact collision/marker error and rerun the idempotent release |
| A removed old-manifest file was locally modified | Abort before project writes | Store/review it; explicit force backs it up outside DTVM before removal |
| A removed path is DTVM-tracked, crosses a symlink, or Git ownership cannot be determined | Fail closed before deletion | Repair ownership/path state; do not force |
| A later non-preflight release stage fails | Earlier independent operations may already be current | Fix the reported stage and rerun release; do not broadly delete derived state |

## Test plan

All integration tests use a temporary home directory and a temporary Git
repository/worktree graph. They must not read or mutate the developer's real
home configuration.

### Skill lifecycle

- Create links for every active skill in both discovery directories.
- Confirm each link resolves to the matching DTVMDotfiles active directory.
- Run reconciliation twice and assert identical results.
- Move an owned skill from active to incubator and to retired; assert its owned
  links are removed while unrelated links remain.
- Add an active skill and assert no parent-directory replacement occurs.

### Collision protection

- Pre-create a regular file at an intended destination.
- Pre-create a directory at an intended destination.
- Pre-create a symlink owned by another source.
- For each case, assert non-zero status and byte-for-byte preservation of the
  foreign object.
- Reject symlinked discovery/config ancestors and lexical `active/../foreign`
  targets without redirected writes.
- Treat an old-checkout absolute link as foreign and preserve it exactly.

### Codex configuration

- Start with no config file and assert a valid managed block is created.
- Start with user content before and after the block and assert it is preserved
  byte-for-byte.
- Create multiple DTVM worktrees and assert two exact disable entries per
  worktree.
- Remove a worktree and assert its derived entries disappear on reconcile.
- Run reconciliation twice and assert no duplicated blocks or entries.
- Supply malformed or duplicate markers and assert fail-closed behavior.
- Exercise paths containing spaces, quotes, backslashes, and TOML-forbidden
  control characters.
- Parse the result and assert user suffix keys remain top-level while the
  managed array-of-tables block is at EOF.

### Integration

- Assert `release.sh` invokes reconciliation after normal dotfile release.
- Assert `worktree-init.sh` refreshes reconciliation for a newly known
  worktree.
- Assert generated local `AGENTS.md` and `GEMINI.md` contain the same positive
  routing as `CLAUDE.md`.
- Assert a locally modified file leaving the old manifest aborts before writes,
  and explicit force backs it up outside DTVM before removal; reject tracked
  paths, symlink escapes, unsafe recovery roots, and indeterminate Git
  ownership.
- Exercise a complete and identity-guarded cold-profile bundle/rerun with a fake
  perf driver; reject changed commit/patch/corpus, runtime source mutation,
  dirty submodules, corpus symlinks, and untracked source.
- Run shell syntax/static checks used by this repository.
- Verify the real DTVM index is empty and tracked legacy DTVM skill files have
  no diff; allow only the documented local generated `AGENTS.md` route diff.

## Rollout

1. Land the four reviewed skill directories and reconciliation implementation
   together in the DTVMDotfiles branch.
2. Pass isolated integration tests and shell checks.
3. Pull the DTVMDotfiles revision on one machine and run release.
4. Verify links, the managed Codex block, positive routing, and a newly created
   test worktree.
5. Start fresh Claude and Codex sessions and smoke-test explicit invocation of
   each personal skill.
6. Roll out to other machines through the normal DTVMDotfiles pull-and-release
   flow.

## Rollback

There is no generic rollback command; rollback is deliberately ownership
bounded.

Preferred rollback keeps ownership explicit:

1. While the new reconciler is still available, move the active personal skills
   to `skills/retired/` and run release to remove owned discovery links.
2. Remove the DTVMDotfiles-managed Codex block using the same bounded
   reconciliation path, or remove exactly the marked block after backing up the
   file.
3. Revert the DTVMDotfiles change if desired.
4. Start a new session to rediscover the repository-tracked behavior.

If the implementation has already been reverted, remove only links whose
resolved targets are proven to be inside the former
`DTVMDotfiles/skills/active/` tree, and remove only the marked Codex block.
Never recursively delete either shared user skill directory. DTVM product
history requires no rollback because this change never enters the DTVM origin.

## Implementation plan

### Phase 1: Architecture and skill boundaries

- [x] Confirm the DTVMDotfiles/DTVM origin boundary.
- [x] Define lifecycle states, skill names, interfaces, and invariants.
- [x] Complete and review the four focused skill packages.

### Phase 2: Reconciliation

- [x] Implement per-skill, fail-closed link reconciliation.
- [x] Implement bounded Codex configuration reconciliation for all known
  worktrees.
- [x] Expose `skills.sh check`/`sync` and invoke sync from release and worktree
  initialization.

### Phase 3: Routing, documentation, and validation

- [x] Document setup, ownership, lifecycle, failure recovery, and routing.
- [x] Add isolated integration coverage for active-only publication, both
  discovery roots, idempotence, collision preflight, config preservation,
  worktree enumeration/path escaping, dry-run, and `worktree-sync`.
- [x] Complete the safety matrix: every foreign collision shape, symlinked
  ancestors, relocation, malformed marker variants, removed-worktree pruning,
  EOF TOML semantics, safe old-manifest removal, generated aliases, and the
  full `worktree-init` seam.
- [x] Validate the cold-profile helper's sealed bundle, bundled rerun,
  identity guards, symlink rejection, and no-index-write dry run.
- [x] Run final verification and update this status to `Implemented`.
