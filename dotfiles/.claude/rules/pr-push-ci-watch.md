---
description: After pushing to a branch with an open PR, monitor CI and follow a strict diagnose → local-repro → local-test → push loop on failure.
globs: []
alwaysApply: true
---

# PR Push → CI Watch → Fix Loop

When you run `git push` (or invoke any helper that does so, e.g. `gh pr create`)
on a branch that has an **open PR**, you MUST follow this loop instead of
treating the push as the end of the task.

## Step 1: Detect whether monitoring applies

After every successful push, run:

```bash
gh pr view --json number,state,url
```

Apply this rule iff the command succeeds AND `state == "OPEN"`. If there is
no PR for the current branch, or the PR is closed/merged, skip this rule —
the push itself was the deliverable.

## Step 2: Monitor CI

Watch the run for the just-pushed commit, not an older one:

```bash
gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" \
            --commit "$(git rev-parse HEAD)" \
            --json databaseId,status,conclusion,workflowName -L 20
```

Then either:

- **Live**: `gh run watch <id>` for a single run, or poll `gh pr checks` every
  ~270s (one cache window — see `loop` skill).
- **Background**: use the `loop` skill or `ScheduleWakeup` if the run is
  expected to take >5 min; do not busy-wait.

Per `feedback_ci_watch_no_permission.md`: while watching, do NOT ask the user
for permission between checkpoints. Watch silently; report only on status
transitions (queued → running → success/failure).

## Step 3: On failure — diagnose root cause

Defer the investigation protocol to `.claude/rules/ci-test-discipline.md`
Rule 2:

1. `gh run view <id> --log-failed`
2. Compare local build flags vs the CI workflow env vars
3. Identify the root cause — not the trigger
   (`feedback_symptom_vs_root_cause.md`)

If the root cause cannot be identified from the logs, stop and report to the
user. Do not push a guess.

## Step 4: MANDATORY — reproduce locally and run the right test suite

**This step is non-negotiable. We have shipped wrong fixes multiple times by
skipping it.** A fix that passes only in your head is not a fix.

Before pushing any fix:

1. **Reproduce the failure locally** with CI-faithful flags
   (`.claude/rules/dtvm-build-config.md`). If you cannot reproduce, do NOT
   push speculative changes — report the discrepancy per `ci-test-discipline.md`
   Rule 2 step 4.
2. **Apply the fix locally.**
3. **Run the test suite that mapped to the touched paths**, per the table in
   `.claude/rules/dtvm-local-test.md` "Test Selection by Touched Path".
   Touching multiple buckets → run **all** matching suites; the bug fix itself
   counts toward path mapping (e.g. fix in `src/compiler/` requires multipass
   unittests + multipass statetest with `-k fork_Cancun`).
4. **All required suites must pass locally.** If even one fails, the fix is
   not done. Iterate on Step 3–4; do not push.
5. Run `tools/format.sh check` (Quality Gate from `CLAUDE.md`).

Only after every required suite passes locally may you proceed to Step 5.

If you cannot run a required suite (missing dependency, environment limitation),
do NOT silently substitute. Per `ci-test-discipline.md` Rule 1 say: "I could
not run <X> because <reason>." and stop for user input before pushing.

## Step 5: Re-push

- Create a **new commit** (never `git commit --amend` on a pushed commit; do
  not force-push). Follow `.claude/rules/commit-conventions.md`.
- `git push` to the same PR branch.
- Return to Step 2 with the new commit.

## Step 6: Stop conditions

Stop the loop and report to the user when ANY of the following holds:

- All required checks pass for the latest commit → write `result:` headline
  with PR URL and check status.
- **3 fix-and-re-push attempts** have completed without all checks turning
  green → escalate; do not silently keep trying. Per
  `feedback_no_vague_observation_advice.md`, the escalation message must
  state a concrete next trigger (e.g. "I need access to X" or "the failure
  reproduces only with Y flag — please confirm before I disable it").
- The failure is structurally outside the diff (infra outage, unrelated
  flaky job) → state which job is unrelated, with evidence (failed step,
  recent history of that job on `main`), and stop.

## Hazards

- **Skipping Step 4 is the #1 historical failure mode.** Local-pass is a
  hard precondition for re-push — not a "nice to have".
- **Do not force-push** to fix CI. Even a one-line fix is a new commit, not
  an amendment of a pushed commit.
- **Do not silently re-trigger** failed runs without a code change. A bare
  `gh run rerun` masks flakiness — only use it when the failure is confirmed
  unrelated to the diff, and say so.
- **Do not trigger-avoid.** Disabling a test, narrowing a filter, or adding a
  retry to make the symptom disappear is not a fix
  (`feedback_symptom_vs_root_cause.md`).

## References

- `.claude/rules/ci-test-discipline.md` Rule 1 & 2 — test discipline +
  failure investigation
- `.claude/rules/dtvm-build-config.md` — CI-faithful local build
- `.claude/rules/dtvm-local-test.md` — local test command construction and
  touched-paths suite-selection table
- `.claude/rules/commit-conventions.md` — commit/PR title format
