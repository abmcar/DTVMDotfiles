---
description: End-to-end fix/optimization workflow — brainstorm → spec → parallel review → execute → parallel review → push gate → CI watch → archive
---

# `/dev-cycle`

User invoked `/dev-cycle` with arguments: `$ARGUMENTS`

This command drives the user's full fix/optimization workflow. Walk phase-by-phase, pausing only at the explicit gates below. Spec of record:
`docs/changes/2026-05-12-dev-cycle-command/README.md` (and `docs/_archive/` after merge).

## Invocation grammar

Parse `$ARGUMENTS`:

| Arguments              | Behavior                                                                                                           |
|------------------------|--------------------------------------------------------------------------------------------------------------------|
| empty                  | Start at Phase 0. Task description must be in the user's invoking turn.                                            |
| `archive` (no slug)    | Phase 7 only. Resolve `<slug>` from the change doc with status `Implemented` whose branch matches `git branch --show-current`. If the resolution is not unique, error and ask the user. |
| `archive <slug>`       | Phase 7 only with the given slug. `<slug>` must match an existing `docs/changes/<slug>/` whose status is `Implemented`. |
| anything else          | Error and print this table.                                                                                        |

Re-entering `/dev-cycle` mid-flow restarts at Phase 0 — there is no resume-from-phase-N facility. If the user wants to skip ahead, invoke the relevant sub-skill directly (`archive`, `opt-validate`, etc.).

## Phase 0 — Brainstorm + Tier

1. Invoke `superpowers:brainstorming` to clarify intent and scope.
2. Decide **Light** vs **Full** tier per `dev-workflow` `SKILL.md`:
   - Full = cross-module / architecture / new capability / breaking change.
   - Light = single-module, well-scoped, limited blast radius.
3. **Escape hatch** — only if the change is a **simple bug fix or typo OR a docs-only edit**, skip Phase 0 with a one-line restatement and proceed to Phase 1 (Light) or directly Phase 3. A "single-file" diff in `src/` is **NOT** sufficient to skip (a one-file peephole rule can be substantive). When in doubt, run Phase 0.
4. Output: one-paragraph problem statement + tier decision. **Stop and confirm with the user before drafting the spec.**

## Phase 1 — Spec / Plan

Produces the change doc at `docs/changes/YYYY-MM-DD-<slug>/README.md`.

- **Light tier**: copy `docs/changes/template-light.md`. Sections: Overview / Motivation / Impact / Checklist. Add an inline `## Implementation` section with ordered steps. The change doc itself is the plan; do not invoke `superpowers:writing-plans`.
- **Full tier**: copy `docs/changes/template.md`. Sections: Overview / Motivation / Impact / Implementation Plan / Compatibility Notes / Risks. Invoke `superpowers:writing-plans` to populate `Implementation Plan` per CLAUDE.md:54-57.
- Set status `Proposed`.
- **Tier upgrade during Phase 1+**: if Phase 2 surfaces cross-module impact for a Light-tier change, halt and ask the user before upgrading. On upgrade: re-copy from `template.md` into the same `docs/changes/<dir>/`, preserving drafted Overview/Motivation/Impact prose.

## Phase 2 — Parallel review of the spec

Dispatch **both reviewers in parallel** (one assistant turn, two `Agent` tool calls) per memory `feedback_parallel_review_two_rounds.md`:

1. **Opus subagent** — `subagent_type: general-purpose`, `model: "opus"` (omit `tools` field; do not pass `tools: all` — memory `feedback_agent_tools_all.md`). Persona: *DTVM senior reviewer; missing edge cases, spec drift, contract violations, ambiguous gates*.
2. **Codex reviewer** — `subagent_type: codex:codex-rescue`, prompt explicitly mentioning `--fresh`. Persona: *skeptic; verify factual claims, flag unsupported assertions, check internal consistency*.

Persist outputs at `docs/changes/<dir>/reviews/round-<N>-{opus,codex}.md`.

- **Target**: 1–2 rounds (user preference). **Hard cap**: 3 rounds (memory canonical).
- **Round layers**: R1 structure, R2 source-fact, R3 cite consistency.
- **Stop early** when both reviewers return `PASS` (or only cosmetic notes).
- **R3 mixed-verdict tiebreaker**: if R3 ends with one PASS and one REVISE, do **not** auto-resolve. Surface the disagreement and stop for user direction. Do **not** run R4.

## Phase 3 — Execute

1. Use `superpowers:executing-plans` against the Implementation / Implementation Plan section of the spec.
2. For code touching `src/` on a branch with an open PR or reviewed commits, **must** use the `worktree-bootstrap` skill (CLAUDE.md:123-129 hazard rule). The skill wraps `DTVMDotfiles/worktree-init.sh`; never use raw `git worktree add`.
3. After each logical unit:
   - **Build gate**: `cmake --build <build-dir> --target dtvmapi -j$(nproc)` by default (matches `opt-validate.md:14` and `worktree-bootstrap`). Override targets: `zen` if the diff only touches `src/cli/`. For CI-faithful flag matrices see `.claude/rules/dtvm-build-config.md`.
   - **Test gate**: see Phase 5 §Test selection — same matrix applies.
4. For perf-tagged changes, also run `/opt-validate` (build → unittests → `/bench-compare`) at the end of Phase 3 instead of in Phase 5.
5. Update change doc status to `Implemented` when execution is complete.

## Phase 4 — Parallel review of the implementation

Same dispatch shape as Phase 2 — **one assistant turn, two `Agent` tool calls in parallel** (Opus subagent + Codex via `codex:codex-rescue` with `--fresh`). Review the diff: `git diff $(git merge-base HEAD main)..HEAD` (use `upstream/main` if `origin` is the personal fork).

Reviewers check:
- Spec compliance (does the implementation match the Implementation section).
- Regression risks.
- Format / build / test status.
- C++ comment style (`.claude/rules/cpp-code-style.md`).
- Commit-message conformance (`.claude/rules/commit-conventions.md`).

Persist outputs under `reviews/impl-round-<N>-{opus,codex}.md`. Target / cap / R3 tiebreaker identical to Phase 2.

## Phase 5 — Pre-push gate

Per `.claude/rules/ci-test-discipline.md` Rule 2 (lines 20–26): do **not** `git push` unless the user explicitly says to push. The format/build/test sequence below comes from CLAUDE.md:101-108 + memory `feedback_verify_before_push.md` (which requires the gate before **every** push, including docs-only).

Steps:

1. `tools/format.sh check`.
2. Build the same target chosen in Phase 3.
3. **Test selection** (`.claude/rules/dtvm-local-test.md`; honoring Rule 1 "never silently skip required tests"):
   - `src/compiler/` or `src/runtime/` touched → multipass `evmone-unittests` + `evmone-statetest -k fork_Cancun`.
   - `src/evm/` touched → interpreter `evmone-unittests` + `evmone-statetest -k fork_Cancun`.
   - `src/tests/` only → `ctest` in the build dir.
   - `docs/`-only or `.claude/`-only or `CLAUDE.md`-only → format check + `ctest` smoke (build is a no-op but still run; full `evmone-*` runs skipped). **Explicitly list in the report what was executed and what was skipped, citing the touched-paths rationale, so Rule 1 is not silently violated.**
   - When in doubt, run multipass unittests + statetest as the safe default and report what was actually executed.
4. Report results as a table (format / build / test rows).

**Stop and wait for user authorization** (`push`, `推上去`, etc.) per Rule 2.

**Rule 2a fast-path** (push without re-asking) requires ALL of:
- Diff is provably one of: `docs/changes/`, `docs/modules/`, `docs/research/`, README/CLAUDE.md, comment/typo/format-only, or a single new test fixture **without changing the test runner** (`.claude/` is **NOT** on this list per `ci-test-discipline.md:33-37`; treat `.claude/` edits as needing authorization).
- The user already granted authorization for this specific work in conversation.

When uncertain: ask.

## Phase 6 — Push + CI watch

Three sub-steps, in order:

### 6a. Feature-branch push

1. Commit (commitlint-compliant message per `.claude/rules/commit-conventions.md`).
2. `git push origin <feature-branch>`. Never force-push to `main`/`master`.
3. From a worktree, `cd` to the main repo first per memory `feedback_pre_push_hook_worktree.local.md`.

### 6b. DTVMDotfiles sync (only if any `MIRRORED_ITEMS` file was touched)

Authoritative command from CLAUDE.md:84-87:

```bash
bash DTVMDotfiles/store.sh
cd DTVMDotfiles && git add -A && git commit -m "<msg>" && git push && cd ..
```

**Hazard guard** (CLAUDE.md:92-94): do **not** invoke `release.sh` between editing managed files (anywhere from Phase 3 onward) and running `store.sh`. As of memory `feedback_dotfiles_release_overwrite.md`, `release.sh` now aborts on local drift unless `RELEASE_FORCE=1` is set — the silent-overwrite hazard is gated, not open, but the guard is still worth enforcing because `RELEASE_FORCE=1` would re-introduce loss.

### 6c. CI watch

1. Resolve the CI run id with a poll loop (avoids `gh run watch`'s "latest workflow" race):
   ```bash
   for i in 1 2 3 4 5 6; do
     run_id=$(gh run list --branch "<feature-branch>" --commit "$(git rev-parse HEAD)" -L 1 --json databaseId -q '.[0].databaseId')
     [ -n "$run_id" ] && break
     sleep 10
   done
   ```
2. `gh run watch "$run_id"`.
3. On failure: follow `.claude/rules/ci-test-discipline.md` Rule 3 (lines 50–63):
   - `gh run view <id> --log-failed` for the exact error.
   - Compare local `build/CMakeCache.txt` vs `.github/workflows/dtvm_evm_test_x86.yml` env block.
   - If flags differ, reconfigure locally with CI flags and re-test.
   - If flags match and failure still does not reproduce locally, **report to the user** with the discrepancy; do NOT push a speculative fix.
4. **Hard cap: 3 fix attempts** (design choice; not memory-cited). An "attempt" = one push that contains a code change beyond regenerating CI metadata. Diagnosing a known-flaky test without pushing does not count. After 3 attempts, summarize attempted diagnoses and stop for user direction. Rationale: avoid trigger-avoid spirals (theme of memory `feedback_symptom_vs_root_cause.md`).

## Phase 7 — Post-merge archive

Triggered explicitly by `/dev-cycle archive [<slug>]`. Not automatic.

**Preconditions** (all five, per `archive` `SKILL.md:19-25`):

| # | Condition | Verify by |
|---|-----------|-----------|
| 1 | Implementation complete | All checklist items in the change doc are checked |
| 2 | Build and tests pass | Phase 5 results or fresh run |
| 3 | Code review approved | `gh pr view --json reviewDecision -q .reviewDecision` returns `APPROVED` |
| 4 | Branch merged | `git fetch upstream && git branch -r --merged upstream/main \| grep -q "<feature-branch>$"`. **GitHub squash-merge does NOT place the branch in this list** (squash creates a new commit on the base whose history does not contain the head-branch commits). **Authoritative fallback**: if `gh pr view --json state -q .state` returns `MERGED`, proceed; the local `--merged` check is informational only. |
| 5 | Module specs updated **if affected** | Related specs in `docs/modules/` reflect any contract changes. Full tier more likely to need this; Light tier rarely touches `docs/modules/`. |

If any precondition fails, report what's missing and stop per `archive` `SKILL.md:27`.

**Sequence**:

1. Invoke the `archive` skill → moves `docs/changes/<slug>/` (including the `reviews/` subdir) to `docs/_archive/<YYYY-MM>/`. Note: the archive index `docs/_archive/README.md` only records one row per change, not per file; review artifacts are preserved but invisible from the index.
2. **After** `archive` returns (it explicitly leaves cleanup to the user per `SKILL.md:63-65`): prune the worktree if one was used:
   ```bash
   rm -rf <worktree-path> && git worktree prune
   ```
   Never use `git worktree remove` (`.claude/rules/dtvm-perf-worktree-lab.md:33-35`).

## Reporting

Throughout the run, surface a one-line phase header before starting each phase so the user can follow along. At each gate, summarize what was done since the last gate.
