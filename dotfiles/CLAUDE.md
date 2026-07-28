# DTVM Development Guide

DTVM is a deterministic VM with EVM ABI compatibility. Core implementation is in C/C++ under `src/`.

## Key Principles
- Preserve determinism — avoid host-specific, non-deterministic behavior
- Prefer touching `third_party/` only when explicitly required
- Keep edits minimal and localized; follow existing patterns
- Update or add tests when behavior changes
- Never hype a direction as paper-worthy without rigorous novelty evidence

## Task Routing

### Direct Execution
- Typo-only, comment-only, and test-only changes
- Clearly behavior-preserving trivial fixes
- Format checks, simple git operations
- Code review or explanation of a specific function

### Delegate to Sub-Agent
- **compiler-agent**: All `src/` code changes
- **perf-agent**: Profiling, benchmark analysis, performance comparison
- **test-agent**: Running test suites, CI reproduction, test result analysis
- **research-agent**: Codebase exploration, web research, information gathering (read-only)
- **doc-agent**: Change document creation/update, module spec maintenance
- Use parallel dispatch when tasks are independent

### Research First (EnterPlanMode)
- New features, architecture changes, or breaking changes
- Ambiguous requirements where scope is unclear
- Multi-file refactors affecting 5+ files
- Performance work requiring profiling before coding

### Personal DTVM Skill Routing

DTVMDotfiles releases the following user-level skills from its own
`skills/active/` SSOT. Route work positively by task:

- **`dtvm-worktree-bootstrap`**: create a DTVM branch/worktree, run the
  project initializer, derive CMake from the current CI source of truth, and
  require the `dtvmapi` / `libdtvmapi.so` build gate
- **`dtvm-cold-compile-profile`**: measure cold compilation and identify
  profiler-backed hotspots in a reproducible, integrity-checked baseline
  bundle; report inherited helpers such as `objdump` separately
- **`dtvm-compiler-path-analysis`**: trace a measured hotspot through the
  current EVM → dMIR → CGIR → RA → post-RA → MC/object source, producing an
  evidence table, falsifiable hypotheses, and a minimal implementation seam
- **`dtvm-write-report`**: turn verified DTVM technical, performance, profiling,
  benchmark, experiment, or optimization evidence into a concise
  decision-first report and block handoff when its deterministic lint fails
- **`dtvm-compile-time-optimize`**: orchestrate the complete
  profile → source analysis → minimal compiler change → same-corpus
  before/after verification loop; this skill is used only when explicitly
  invoked

When the user explicitly invokes the end-to-end optimization workflow, use
`dtvm-compile-time-optimize`. It uses `dtvm-worktree-bootstrap` when isolated
worktrees are missing, composes the two focused analysis skills, then delegates
the evidence-backed minimal `src/**` change through `compiler-agent` and
preserves the correctness and paired-benchmark evidence gates.

Every reader-facing DTVM technical or performance report must use
`dtvm-write-report` and pass its artifact and final-output lint. Data Analytics
may validate evidence, build visualizations, and package HTML, but its generic
audience templates and QA labels do not override DTVM's narrative,
information-budget, language, or experiment-terminology contract.

DTVM's tracked `dtvm-perf-profile` and `dmir-compiler-analysis` skills are
historical sources for maintaining the replacements, not workflow entry
points. Do not invoke them for current work.

## Development Workflow

The default lifecycle (propose → plan → execute → verify-and-archive) is
driven by the upstream `dev-workflow` skill (`.agents/skills/dev-workflow/`)
for feature, enhancement, refactor, optimization, and bug-fix implementation.
Classify every implementation before execution. Only typo-only, comment-only,
test-only, or clearly behavior-preserving trivial fixes may skip proposal work;
record a specific `N/A` reason when they do.

For **feature implementation** or explicit `/dev-cycle` invocation, escalate
to the opt-in `dev-cycle` skill (`~/claude-sync/skills/dev-cycle/`) — see its
SKILL.md for the full lifecycle. Do not auto-invoke `/dev-cycle` for routine
fixes.

### DTVM-specific constraints (override or supplement skill defaults)

- **Change documents live in `docs/changes/YYYY-MM-DD-<slug>/README.md`**
  inside this repo. This is a project requirement and **overrides** the
  `~/changes/` SSOT default in `CLAUDE.shared.md` — DTVM change docs are
  project artifacts and ship with the PR, not personal drafts.
  - **Full tier** (`template.md`): cross-module, architecture, new capabilities
  - **Light tier** (`template-light.md`): single-module, well-scoped improvements
- A change to runtime semantics, determinism, gas accounting, compiler
  scheduling, a module contract, or security requires a change document.
  Bug fixes with design implications require at least a Light document,
  regardless of file count.
- Consult relevant `docs/modules/` specs during planning.
- High-stakes review (paper, plan, PR closure, direction-doc): dispatch Opus +
  Codex as parallel reviewers in separate Agent calls; target 1–2 rounds, hard-
  cap 3, with `model: "opus"` set explicitly. Keep this manual two-Agent dispatch
  for interactive reviews; reach for the Workflow tool only when you need
  deterministic round-cap counting or aggregation across many findings — use one
  or the other, not both.
- After merge: only when the user explicitly asks, use the `archive` skill to
  move the change to `docs/_archive/<YYYY-MM>/`; halt at the local `git mv` —
  never open an archive PR (project convention: merged docs otherwise stay in
  `docs/changes/`).

### Dotfiles Sync Rule

DTVMDotfiles has two ownership flows:

1. For a file deployed into this DTVM workspace and listed in
   `MIRRORED_ITEMS`, collect live edits before release:

```bash
bash DTVMDotfiles/store.sh
cd DTVMDotfiles && git add -A && git commit -m "<message>" && git push && cd ..
```

2. For a personal skill, edit the SSOT directly under
   `DTVMDotfiles/skills/{active,incubator,retired}/`, then validate and
   reconcile it:

```bash
cd DTVMDotfiles
RELEASE_CHECK=1 bash skills.sh sync
bash release.sh
bash skills.sh check
git add skills && git commit -m "<message>" && git push
cd ..
```

Personal skill source is committed only to the DTVMDotfiles origin, never to
the DTVM origin.

Release regenerates this checkout's tracked `AGENTS.md` from `CLAUDE.md` as
local derived state. Never stage, commit, or push that generated DTVM diff as
part of a personal-skill change; verify the DTVM index remains empty.

**Order matters for mirrored workspace files**: never run `release.sh` between
editing a managed live file and running `store.sh`. Personal skills use the
opposite, SSOT-first flow and are never collected from DTVM or the user-level
links. Manifest mechanics, release reconciliation, worktree symlinks, and the
generated `AGENTS.md`/`GEMINI.md` are documented in
`.claude/rules/dtvm-dotfiles-usage.md`.

## Quality Gates

**Before finishing any code task, verify:**
1. `tools/format.sh check` passes
2. Changed code compiles: `cmake --build build --target <relevant_target>`
3. Relevant tests pass — run `tools/dtvm_local_test.sh --auto`, which selects suites by touched path per `.claude/rules/dtvm-local-test.md`
4. No new compiler warnings in build output

**Before creating commits/PRs:**
1. Provide exactly one declaration:
   - `Change doc: docs/changes/YYYY-MM-DD-<slug>/README.md`
   - `N/A: <specific reason allowed by the skip criteria above>`
2. Validate it locally:
   `python3 tools/check_change_doc.py --base-ref origin/main --declaration "<declaration>"`
3. Follow `.claude/rules/commit-conventions.md`.

The pull request template and CI require the same declaration. CI validates
the declaration and referenced path; reviewers validate whether an `N/A`
reason satisfies the semantic skip criteria.

**After `git push` to a branch with an open PR:** follow the CI-watch loop in `.claude/rules/pr-push-ci-watch.md`.

## Worktrees

Create DTVM worktrees with the `dtvm-worktree-bootstrap` skill (wraps
`DTVMDotfiles/worktree-init.sh`: submodule init + dotfiles symlink; worktrees
under `.worktrees/`, gitignored). The initializer also reconciles the
user-level personal-skill links and Codex's exact-path disables after Git knows
about the new worktree. **MUST** use it — not a generic worktree skill or raw
`git worktree add`, which won't init submodules, sync dotfiles, or refresh that
derived configuration — for any experimental branch (perf, algorithm, SPP),
whether or not that branch already has an open PR or reviewed commits. Never
`git checkout -b` an experimental branch in the primary checkout (repo root):
that pins the main checkout off its integration branch. Branch inside a
`.worktrees/` worktree even when starting fresh from a clean `main`.
Resource and mechanics rules: `.claude/rules/dtvm-perf-worktree-lab.md`.

## Where things live

- Delegate specialized work to sub-agents to reduce context pollution.
- Domain knowledge → `.claude/rules/` (most are path-scoped, load on demand) and `.claude/commands/`; upstream skills → `.agents/skills/`.
- Personal DTVM workflow SSOT → `DTVMDotfiles/skills/`; only `active/` is
  exposed through user-level `~/.agents/skills` and `~/.claude/skills` links.
- General build: `docs/start.md`
- CI-faithful EVM build: `.claude/rules/dtvm-build-config.md`
- Perf workflows: `.claude/commands/dtvm-evmone-benchmark.md`, `.claude/commands/dtvm-jit-lowering-inspection.md`
- Cold compilation profiling: `dtvm-cold-compile-profile`; measured compiler
  path analysis: `dtvm-compiler-path-analysis`; verified optimization:
  `dtvm-compile-time-optimize`; reader-facing reports: `dtvm-write-report`.

## Code Style

C/C++ style and the `tools/format.sh format` / `check` workflow:
`.claude/rules/cpp-code-style.md` (path-scoped to `src/**`; loads when you touch C++).
