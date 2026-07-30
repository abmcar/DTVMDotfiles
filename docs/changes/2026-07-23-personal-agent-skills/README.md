# Change: DTVMDotfiles-managed personal DTVM skills

- **Status**: Accepted
- **Date**: 2026-07-23
- **Tier**: Full

## Overview

Make DTVMDotfiles the single source of truth (SSOT) for a small set of
personally maintained DTVM skills. DTVMDotfiles versions the skills in its own
origin and exposes only active skills through per-skill links in the user-level
Claude and Codex discovery directories. DTVM's tracked skills remain unchanged
in every DTVM checkout.

The target release path also maintains a closed managed block near the end of
Codex's user configuration, followed by a fixed tail anchor. The map-derived
target policy disables four superseded repository-tracked skills by name:

- `archive`
- `dev-workflow`
- `dtvm-perf-profile`
- `dmir-compiler-analysis`

Claude Code 2.1.129 and newer disable the same names through project
`skillOverrides`. Both policies are static and independent of the number,
location, or lifetime of DTVM worktrees.

`dotfiles/skills.map.sh` is the sole suppression-policy SSOT.
`skills.sh sync` deterministically renders both client adapters from its
`legacy-repo` entries: the Codex name block and the complete Claude Code
`skillOverrides` object. The Claude adapter is checked into DTVMDotfiles;
other keys in `.claude/settings.json` remain project configuration. Any map
ownership value other than `legacy-repo` fails before writes.

Project guidance routes new work to these ten active personal skills:

- `dtvm-archive`
- `dtvm-worktree-bootstrap`
- `dtvm-cold-compile-profile`
- `dtvm-compile-time-optimize`
- `dtvm-compiler-path-analysis`
- `dtvm-dev-cycle`
- `dtvm-dev-workflow`
- `dtvm-profile-reth-replay`
- `dtvm-run-reth-replay`
- `dtvm-write-report`

`skills/retired/` retains `dmir-compiler-analysis` and `dtvm-perf-profile` as
undiscoverable historical sources. The checked-in map and Claude adapter are
the target state for this integration branch; the branch has not run
`skills.sh sync` or `release.sh` against the live adapters. Until that explicit
rollout, live clients can continue to reflect the previously released two-name
policy.

This design applies the SSOT and progressive-disclosure principles commonly
used by Matt Pocock's skill workflow: each focused capability has one canonical
skill directory, the entry file stays oriented around when and how to use it,
and detailed resources are loaded only when the task needs them. Matt Pocock's
`skills` CLI remains an optional authoring and installation ecosystem, not a
runtime dependency. Its currently documented Codex global path differs from
OpenAI's `$HOME/.agents/skills` discovery path, so DTVMDotfiles publishes
directly to the client discovery roots. No third-party skill text is copied
into this repository.

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
- agents can continue selecting the old repository skill unless routing and
  discovery are changed together.

DTVMDotfiles already owns the release boundary and project configuration. It
is therefore the appropriate repository for personal DTVM workflow policy,
while DTVM remains the source repository for product code and its tracked
skills.

## Goals

1. Version personal DTVM skills in the DTVMDotfiles origin, never in the DTVM
   origin.
2. Establish `DTVMDotfiles/skills/` as the only editable source for these
   personal skills.
3. Represent skill maturity with explicit `active`, `incubator`, and `retired`
   lifecycle directories.
4. Expose each active skill independently in both user-level discovery
   directories.
5. Generate both client suppression adapters from one declarative map, require
   exact Claude adapter equality before release, and keep the policy
   independent of worktree initialization.
6. Refuse to overwrite files, directories, or symlinks owned by another
   system.
7. Preserve the bytes and relative order of user Codex configuration outside
   one closed DTVMDotfiles-owned block, keep a fixed EOF tail anchor for
   Codex-owned table insertion, and suppress the same old names in Claude
   Code's project settings.
8. Route compile-time investigations through a reproducible profile, source
   analysis, minimal-change, and before/after verification loop.
9. Route development lifecycle, explicit archival, Reth capture/replay, and
   reader-facing reporting through focused active skills.
10. Cover lifecycle transitions, collisions, configuration preservation,
   static name policy, worktree independence, and idempotence with isolated
   integration tests.

## Non-goals

- Modifying, deleting, renaming, or backporting DTVM's tracked
  `.agents/skills/archive`, `.agents/skills/dev-workflow`,
  `.agents/skills/dtvm-perf-profile`, or
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
| `skills.sh`, `lib/agent_skills.sh` | Render and check the Claude/Codex adapters, then reconcile active skill links |
| `release.sh` | Require the checked-in Claude adapter to be current before any write, then deploy and reconcile user-level state |
| `worktree-sync.sh` | Link project configuration without changing user-level skill/config state |
| `dotfiles/skills.map.sh` | Sole declarative SSOT for tracked repository skill names suppressed in both clients |
| `dotfiles/.claude/settings.json` | Project settings whose complete `skillOverrides` object is a checked-in adapter rendered from the map |
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

`release.sh` is the canonical deployment entry point. Before any write, it
preflights personal skill/config collisions, requires the Claude
`skillOverrides` object to equal the map-derived policy, and checks
removed-manifest safety. If the adapter drifts, release stops and directs the
operator to `bash DTVMDotfiles/skills.sh sync`. A valid release applies the
project-dotfiles contract, then reconciles personal skill exposure and the
DTVMDotfiles-owned Codex configuration block and tail anchor.

`skills.sh check` is the read-only inspection entry point. It requires exact
equality between map-derived overrides and the checked-in Claude object, in
addition to checking links and Codex configuration. `skills.sh sync` replaces
the entire `skillOverrides` object from the map, preserves other settings keys,
removes stale overrides, renders the Codex adapter, and reconciles links.
Therefore a map change must run sync before release. An ordinary release with
an unchanged map still reconciles user-level links and Codex configuration at
the end.

`worktree-init.sh` continues to initialize submodules and project dotfiles. It
delegates project linking to `worktree-sync.sh`. Neither command reconciles
user-level personal-skill links or Codex configuration. The static name policy
does not change when a worktree is added or removed.

### Codex configuration interface

DTVMDotfiles owns only the text between its start and end markers in
`~/.codex/config.toml`. A fixed tail anchor remains at EOF, outside the managed
block. `skills.sh sync` renders the entries from the `legacy-repo` names in
`dotfiles/skills.map.sh`; each entry uses `name` and
`enabled = false` for the four superseded tracked skills. This interface has
been verified with Codex 0.145.0. It requires neither Git worktree enumeration
nor path escaping.

```toml
# BEGIN DTVMDotfiles managed agent skills
# Generated by DTVMDotfiles; edit dotfiles/skills.map.sh, not this block.
[[skills.config]]
name = "archive"
enabled = false

[[skills.config]]
name = "dev-workflow"
enabled = false

[[skills.config]]
name = "dmir-compiler-analysis"
enabled = false

[[skills.config]]
name = "dtvm-perf-profile"
enabled = false
# END DTVMDotfiles managed agent skills
# DTVMDotfiles agent skills tail anchor
```

Codex inserts newly created marketplace and plugin tables before a trailing
comment. The external tail anchor gives Codex that insertion point: such
tables land between `END` and the anchor and remain outside the managed block.
All content outside the block belongs to the user or another system.

Older releases used `END` itself as the EOF comment. A Codex-owned table could
therefore be inserted inside that old block. During migration, reconciliation
finds the first foreign table header inside the old block, ignoring valid
leading and trailing whitespace when classifying it. It preserves the suffix
from that header through the line before `END` and moves it outside the new
managed block. It does not delete or reinterpret that foreign suffix.
Reconciliation preserves the relative order of unowned bytes.

### Claude Code configuration interface

Claude Code 2.1.129 and newer apply project-level skill suppression through
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

The `skillOverrides` object is a generated adapter, not an independent policy
source. `skills.sh sync` replaces the complete object with the sorted
map-derived name-to-`"off"` mapping. This removes stale or extra overrides and
restores missing or changed entries. The JSON transformation preserves all
other top-level settings keys. `skills.sh check` compares the complete object
for exact equality.

The rendered file follows the existing project-dotfiles release and
worktree-linking flow. It is checked into DTVMDotfiles so release can deploy it,
but the object must not be maintained by hand.

### Routing interface

The project-level `CLAUDE.md` is still the source copied locally to `AGENTS.md`
and `GEMINI.md`. It routes:

- ordinary improvements and routine fixes to `dtvm-dev-workflow`;
- features, architecture changes, breaking changes, and explicit `/dev-cycle`
  work to `dtvm-dev-cycle`;
- explicit post-merge archival to `dtvm-archive`;
- worktree creation and initialization to `dtvm-worktree-bootstrap`;
- cold compilation measurement to `dtvm-cold-compile-profile`;
- source-level explanation of a measured compiler path to
  `dtvm-compiler-path-analysis`;
- the end-to-end verified optimization loop to
  `dtvm-compile-time-optimize`;
- frozen Reth corpus capture and strict offline replay to
  `dtvm-run-reth-replay`;
- paired full-window real-block replay measurement and process-wide perf
  attribution on that frozen corpus to `dtvm-profile-reth-replay`;
- reader-facing technical and performance artifacts to `dtvm-write-report`.

The old tracked skills are historical sources that may be inspected while
authoring the replacements. They are not workflow entry points.

### System seams

1. **Project mirroring versus personal skills**: `dotfiles/` continues to use
   manifest-bounded release/store semantics. `skills/` is edited directly in
   DTVMDotfiles and is exposed through links; it is not collected from DTVM.
2. **Repository ownership versus user discovery**: Git tracks skill content in
   DTVMDotfiles, while home-directory links only make that content
   discoverable.
3. **Policy SSOT versus client adapters**: `skills.map.sh` owns the suppressed
   names. The checked-in Claude object and user-level Codex block are rendered
   outputs; neither may introduce an independent name.
4. **User-level publication versus worktree initialization**: active skills
   and Codex suppression are reconciled once in user configuration; worktrees
   only receive project dotfiles, including Claude Code settings.
5. **Disk state versus session state**: release changes files and links on disk,
   but skill discovery for an already running session may remain cached.
6. **DTVMDotfiles origin versus DTVM origin**: release writes local guidance
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
4. **Focused names**: the ten active names do not shadow the four suppressed
   tracked skill names. The two retired packages remain undiscoverable.
5. **Per-skill ownership**: reconciliation may create, update, or remove only
   links that it can prove belong to this DTVMDotfiles skill set. It never owns
   all of `~/.agents/skills` or `~/.claude/skills`.
6. **Fail-closed collision handling**: an existing foreign file, directory, or
   symlink, or a symlink component in a write destination, causes a non-zero
   result and remains untouched. Users must inspect and resolve the collision
   explicitly.
7. **Scoped configuration mutation**: only one uniquely identifiable closed
   managed block in Codex configuration may be replaced. One tail anchor must
   follow `END` and remain at EOF. Ambiguous block markers, duplicate anchors,
   or an anchor at or before `END` are errors, not permission to rewrite the
   file. A valid replacement is written through a temporary file in the
   config directory and an atomic `mv`.
8. **Single suppression-policy source**: only `dotfiles/skills.map.sh` defines
   suppressed repository skill names. The Codex entries and complete Claude
   `skillOverrides` object must equal the policy rendered from its
   `legacy-repo` entries.
9. **Static cross-worktree suppression**: both adapters contain the same
   name-based policy. Worktree paths never enter either adapter.
10. **Deterministic reconciliation**: the same SSOT, home path, and unowned
   configuration bytes produce the same links, managed block, and tail anchor.
   Re-running release is idempotent.
11. **Positive routing**: project guidance names the intended personal skill
    for each task. It does not depend solely on telling an agent what not to
    use.
12. **No session-state promise**: a successful reconcile guarantees disk state,
    not immediate rediscovery by a running agent session.
13. **Removed-file safety**: a manifest-managed file removed from the new SSOT
    receives the same local hash gate as an overwritten file. Forced removal
    backs up locally modified content outside the DTVM repository first. A
    DTVM-tracked path is never removed, even when its bytes match the old
    manifest.
14. **Origin guard**: release may create a local tracked `AGENTS.md` diff, but
    the DTVM index must remain empty and tracked DTVM skill files must remain
    unchanged.

## Skill boundaries

### `dtvm-dev-workflow`

Owns the default propose → plan → execute → verify lifecycle for ordinary DTVM
improvements and routine fixes. Only typo-, comment-, test-only, or clearly
behavior-preserving trivial changes may use its documented proposal-skip path.

### `dtvm-dev-cycle`

Owns feature implementation, new capabilities, architecture or breaking
changes, and explicit `/dev-cycle` requests. It remains opt-in and falls back
to Full-tier `dtvm-dev-workflow` when not discoverable.

### `dtvm-archive`

Owns only explicit requests to archive exact already-merged changes. It
verifies preconditions, moves them to
`docs/_archive/<YYYY-MM>/<slug>/`, and stops at the local `git mv` without an
index update, commit, push, or archive PR.

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

### `dtvm-run-reth-replay`

Owns endpoint readiness, a frozen finalized block-window capture, strict
offline DTVM replay, and checksummed evidence sealing. It does not treat the
manifest-verified adapter slice as a standalone Rust workspace.

### `dtvm-profile-reth-replay`

Owns paired fresh-process performance measurement and process-wide perf
attribution on an already frozen, strict-correct Reth witness window. It does
not capture witnesses, and delegates one-shot compiler evidence to
`dtvm-cold-compile-profile`.

### `dtvm-write-report`

Owns reader-facing DTVM technical, performance, benchmark, profiling,
experiment, and optimization reports. It applies the DTVM-specific narrative
and terminology contract and requires deterministic artifact and final-output
lint before handoff.

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
3. Ensure `jq` is available, then run `bash DTVMDotfiles/release.sh` from the
   DTVM workspace. The old
   DTVMDotfiles-managed `.agents/skills/worktree-bootstrap/SKILL.md` leaves the
   manifest in this migration. If it was locally modified, release aborts
   before writes; store/review it, then use explicit `RELEASE_FORCE=1` to back
   it up outside the DTVM repository and remove it. A DTVM-tracked path is
   never removed.
4. Run `bash DTVMDotfiles/skills.sh check`.
5. If release or check reports a foreign collision, inspect that exact path. Move,
   rename, or deliberately remove it only after establishing its owner, then
   rerun release.
6. Inspect each active-skill link in both user discovery directories.
7. Inspect only the marked DTVMDotfiles block in `~/.codex/config.toml` and
   confirm that it contains the four static name-based disable entries. Inspect
   the EOF tail anchor and confirm that any Codex-owned tables lie outside the
   block. Inspect project `.claude/settings.json` and confirm that
   `skillOverrides` disables the same names.
8. Start a new Claude/Codex session, or restart the client where necessary.
9. Verify the DTVM index is empty and the four tracked legacy skill
   directories have no diff. A local generated `M AGENTS.md` is expected but
   must not be staged.

No DTVM branch, commit, or push is part of this migration. Release does refresh
the tracked `AGENTS.md` working-tree file locally.

### New machine

The existing bootstrap flow clones DTVMDotfiles, runs `release.sh`, and then
installs `jq` through `apt` when it is missing before the first release. It then
runs the released initialization script, which also declares `jq` as a system
dependency. Personal skill links and Codex configuration therefore arrive
through release; there is no separate skill installer.

### New worktree

Use `dtvm-worktree-bootstrap`, which delegates to the DTVMDotfiles worktree
initializer for submodules, project dotfile links, CI-derived CMake
configuration, and the build gate. It does not refresh user-level skills or
Codex configuration because those are independent of the worktree set.

### Lifecycle transition

- Develop a draft under `skills/incubator/<name>`.
- Promote it with a version-controlled move into `skills/active/<name>`, review
  its `SKILL.md`, and run release.
- Retire it with a version-controlled move into `skills/retired/<name>` and run
  release so DTVMDotfiles-owned discovery links are removed.

Moving a directory alone changes the SSOT; release is what reconciles derived
home-directory state.

### Suppression-policy change

Edit only `dotfiles/skills.map.sh`, then run `bash skills.sh sync` and
`bash skills.sh check`. Review and commit the map together with the generated
`dotfiles/.claude/settings.json`, then run release. Do not edit
`skillOverrides` directly.

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
| Codex file has no managed block | Add a closed block and EOF tail anchor while preserving existing content | Rerun release, then inspect the marked block and anchor |
| A valid old block has no tail anchor | Preserve any foreign table suffix and migrate to the anchored layout | Run release or sync; no manual table movement is required |
| Codex file has malformed or duplicate block markers, duplicate anchors, or an anchor at or before `END` | Fail closed rather than guess boundaries | Repair the marker structure manually from a backup, then rerun |
| Claude `skillOverrides` differs from the map-derived object | `check` reports drift and release stops before any write | Run `bash DTVMDotfiles/skills.sh sync`, review the generated adapter, then rerun release |
| Claude settings is invalid JSON or `skillOverrides` is not an object | Fail before adapter, project, or user writes | Repair the non-generated settings structure, then run sync |
| A worktree is added or pruned | User-level links and static Codex policy remain unchanged | No personal-skill reconciliation is required |
| Claude Code is older than 2.1.129 | Project `skillOverrides` support is outside the verified range | Upgrade Claude Code before relying on suppression |
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
- Assert the block contains exactly four `name`-based disable entries.
- Assert the fixed tail anchor is the final line while the managed `END` marker
  may precede Codex-owned tables.
- Insert a Codex-owned table between `END` and the tail anchor and assert
  reconciliation preserves the file byte-for-byte.
- Put a foreign table suffix inside a legacy EOF-only block and assert
  reconciliation preserves it and moves it outside the managed block.
- Add and remove DTVM worktrees and assert the block does not change.
- Run reconciliation twice and assert no duplicated blocks or entries.
- Supply malformed or duplicate block markers and duplicate or misplaced tail
  anchors, then assert fail-closed behavior.
- Parse the result and assert user and Codex-owned tables remain outside the
  closed managed block.

### Client policy adapters

- Derive the expected name set from `skills.map.sh` and assert both adapters
  contain that policy.
- Rewrite the complete Claude `skillOverrides` object, preserve other settings
  keys, and remove stale overrides.
- Require exact equality in `skills.sh check`.
- Introduce Claude adapter drift and assert release stops before project or
  user-level writes.

### Integration

- Assert `release.sh` invokes reconciliation after normal dotfile release.
- Assert `worktree-init.sh` leaves user-level links and Codex configuration
  unchanged while linking project dotfiles.
- Assert release deploys the checked-in Claude adapter after the write gate.
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

1. [x] Complete review of all ten active and two retired skill packages on
   the local DTVMDotfiles integration branch.
2. [x] Pass the publishing gate, registered skill tests, validation hooks,
   shell syntax checks, and final diff review.
3. [ ] Land the reviewed SSOT and four-name map-derived adapters in the
   DTVMDotfiles origin; do not publish them to the DTVM origin.
4. [ ] Pull that DTVMDotfiles revision on one machine and explicitly run
   sync/release.
5. [ ] Verify ten links in both discovery roots, both four-name client
   policies, positive routing, and a newly created test worktree.
6. [ ] Start fresh Claude and Codex sessions and smoke-test explicit invocation
   of each personal skill.
7. [ ] Roll out to other machines through the normal DTVMDotfiles
   pull-and-release flow.

## Rollback

There is no generic rollback command; rollback is deliberately ownership
bounded.

Preferred rollback keeps ownership explicit:

1. While the new reconciler is still available, move the active personal skills
   to `skills/retired/` and run release to remove owned discovery links.
2. Remove the DTVMDotfiles-managed Codex block and its fixed tail anchor using
   the same bounded reconciliation path, or remove exactly those markers and
   managed lines after backing up the file.
3. Revert the DTVMDotfiles change if desired.
4. Start a new session to rediscover the repository-tracked behavior.

If the implementation has already been reverted, remove only links whose
resolved targets are proven to be inside the former
`DTVMDotfiles/skills/active/` tree, and remove only the marked Codex block.
Also remove the exact fixed tail anchor. Never recursively delete either shared
user skill directory. DTVM product history requires no rollback because this
change never enters the DTVM origin.

## Implementation plan

### Phase 1: Architecture and skill boundaries

- [x] Confirm the DTVMDotfiles/DTVM origin boundary.
- [x] Define lifecycle states, skill names, interfaces, and invariants.
- [x] Stage ten active focused skill packages and two retired historical
  packages in the local integration branch.
- [x] Complete the cross-skill review of all ten active packages.

### Phase 2: Reconciliation

- [x] Implement per-skill, fail-closed link reconciliation.
- [x] Implement bounded Codex configuration reconciliation with four static
  name-based entries.
- [x] Generate the complete Claude adapter from the shared map, enforce exact
  equality before release, and keep worktree initialization independent.
- [ ] Exercise the four-name target policy in an explicit live sync/release.

### Phase 3: Routing, documentation, and validation

- [x] Document setup, ownership, lifecycle, failure recovery, and routing.
- [x] Add isolated integration coverage for active-only publication, both
  discovery roots, idempotence, collision preflight, config preservation,
  static name suppression, dry-run, and worktree independence.
- [x] Complete the safety matrix: every foreign collision shape, symlinked
  ancestors, relocation, malformed marker variants, static policy stability,
  anchored-tail TOML semantics, safe legacy foreign-table migration, safe
  old-manifest removal, generated aliases, and the full `worktree-init` seam.
- [x] Validate the cold-profile helper's sealed bundle, bundled rerun,
  identity guards, symlink rejection, and no-index-write dry run.
- [x] Pass strict package validation for all ten active skills, every
  registered script-bearing-skill hook, and the explicit repository test
  registry on the integrated branch.
- [ ] Merge the verified implementation in DTVMDotfiles, then update this
  status to `Implemented`.
