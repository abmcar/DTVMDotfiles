---
description: After pushing to a branch with an open PR, monitor CI and follow a strict diagnose → local-repro → local-test → push loop on failure.
globs: []
alwaysApply: true
---

# PR Push → CI Watch → Fix Loop

When you run `git push` (or any helper that pushes, e.g. `gh pr create`) and
the current branch has an open PR, follow this loop. Do not treat the push
as the end of the task.

## 1. Detect

After the push completes, run `gh pr view --json state,number,url`. Apply
this rule iff `state == "OPEN"`. Otherwise the push was the deliverable; stop.

## 2. Monitor

Find the run for the just-pushed commit, not an older one:

```bash
gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" \
            --commit "$(git rev-parse HEAD)" \
            --json databaseId,status,conclusion,workflowName -L 20
```

Watch live with `gh run watch <id>`, or use the `loop` skill / `ScheduleWakeup`
in the background (≤270s cadence stays in one prompt-cache window — see `loop`
skill description). Per `feedback_ci_watch_no_permission.md`: emit one line
per status change, no chatter between checks.

## 3. On failure — find the root cause

Defer to `.claude/rules/ci-test-discipline.md` Rule 2. Identify the **root
cause**, not the trigger (`feedback_symptom_vs_root_cause.md`). If the cause
cannot be identified from the logs and flag comparison, stop and report.
Do not push a guess.

## 4. MANDATORY — reproduce locally and run the right test suite

**Skipping this step is the #1 historical failure mode.** Before pushing a
fix:

1. Reproduce the CI failure locally with CI-faithful flags
   (`.claude/rules/dtvm-build-config.md`). No repro → no push.
2. Apply the fix.
3. Run the suites that map to the touched paths per
   `.claude/rules/dtvm-local-test.md` "Test Selection by Touched Path".
   Touching multiple buckets → run **all** matching suites. If the fix
   touches paths outside that table (e.g. `.github/workflows/`, build
   scripts, `tools/`), state which suite(s) you chose and why.
4. Every required suite must pass locally. One failure → fix is not done;
   iterate.
5. Run the full `CLAUDE.md` Quality Gates: `tools/format.sh check`, build
   the relevant target, run the suite(s) above, and verify no new compiler
   warnings.

If a required suite cannot be run, follow `ci-test-discipline.md` Rule 1
(report the skip + reason) and stop for user input before pushing.

## 5. Re-push

Create a **new commit** (never `--amend` a pushed commit; never force-push).
Follow `.claude/rules/commit-conventions.md`. `git push`, then return to
Step 2 with the new commit.

## 6. Stop conditions

Stop the loop and report when ANY of these holds:

- All required checks pass on the latest commit → write `result:` with PR URL
  and check status.
- **3 fix-and-re-push attempts** without all green → escalate with a concrete
  next-step trigger (`feedback_no_vague_observation_advice.md`), e.g. "the
  failure reproduces only with flag Y — please confirm before I disable it".
- PR state changes to closed/merged mid-loop → stop, report final state.
- No CI run appears within ~5 min of the push → infrastructure issue, report;
  do not loop.
- Failure is structurally outside the diff (infra outage, unrelated flaky
  job) → state which job and why, with evidence from recent history on `main`.

## Hazards

- **Skipping Step 4 is the #1 historical failure mode** — local-pass is a
  precondition for re-push, not a "nice to have".
- **Do not silently re-trigger** failed runs without a code change. `gh run
  rerun` masks flakiness; use it only when the failure is confirmed unrelated
  to the diff, and say so.
