---
name: dtvm-dev-cycle
description: Run the complete gated DTVM feature lifecycle from an in-repository change proposal through plan review, delegated implementation, verification, and local handoff. Use when DTVM project routing selects this skill because the user asks to implement a new feature, architecture change, or breaking change, or when the user explicitly invokes `$dtvm-dev-cycle`, `/dtvm-dev-cycle`, or `/dev-cycle`. Do not use for routine fixes; use `dtvm-dev-workflow` for those.
---

# DTVM Development Cycle

Run this workflow after the DTVM project route explicitly selects it for a
qualifying implementation request or the user invokes it directly. Keep
`policy.allow_implicit_invocation: false`: project routing is the explicit
selection mechanism, while generic client discovery must not auto-invoke the
skill. Follow the current DTVM project instructions throughout; they override
this skill when they are more specific. Treat selecting this skill as
authorization for the requested development work, not for publishing or
archiving it.

## 1. Freeze scope and ownership

1. Read the repository instructions and the relevant `docs/modules/` specs.
2. Record the requested outcome, affected contracts, expected tests, and the
   user's publication boundary.
3. Use `$dtvm-worktree-bootstrap` when the required isolated DTVM worktree is
   missing. Never create an experimental DTVM branch in the primary checkout.
4. Classify the change:
   - **Full**: cross-module, architecture, new capability, or breaking change.
   - **Light**: single-module, well-scoped improvement with limited blast
     radius.

Return to this phase whenever implementation would expand the accepted scope.

## 2. Propose and accept

1. Delegate change-document work to `doc-agent`.
2. Create exactly one repository artifact at
   `docs/changes/YYYY-MM-DD-<slug>/README.md`:
   - copy `docs/changes/template.md` for the full tier;
   - copy `docs/changes/template-light.md` for the light tier.
3. Set its status to `Proposed`. Describe motivation, non-goals, invariants,
   affected modules, compatibility, risks, test strategy, and rollback.
4. Present the proposal for acceptance. Do not modify implementation code
   until the proposal is accepted and its status is `Accepted`.

Completion gate: one accepted, correctly located change document defines the
scope and invariants.

## 3. Plan and review

1. Trace the accepted design through current source, module specs, build
   targets, and tests. Use read-only research delegation when useful.
2. Produce an ordered implementation plan with file ownership, delegation,
   intermediate build/test gates, and rollback points.
3. Review the plan for determinism, ABI and compatibility constraints, memory
   safety, scope control, and test coverage.
4. For a high-stakes plan or direction decision, run the independent parallel
   review required by the current DTVM project instructions. Reconcile
   findings in 1–2 rounds and never exceed 3.
5. Present the reviewed plan for confirmation. Do not execute it before that
   confirmation.

Completion gate: the user has confirmed a reviewed, testable plan that stays
inside the accepted proposal.

## 4. Execute through specialized agents

1. Delegate every `src/**` modification to `compiler-agent`; the orchestrating
   agent must not make those edits directly. Provide the accepted change doc,
   exact plan step, invariants, intended files and symbols, required tests, and
   minimal-diff constraint.
2. Delegate test execution and CI reproduction to `test-agent` when available,
   and documentation or module-spec updates to `doc-agent`.
3. Keep `third_party/` unchanged unless the accepted proposal explicitly
   requires it. Keep each implementation unit minimal and localized.
4. After every logical unit, inspect the returned diff and run the planned
   build and test gate. If the diff changes a contract or invalidates the
   proposal, stop and return to proposal or plan review.
5. Review the integrated diff for determinism, host dependence, undefined
   behavior, resource lifetime, ABI compatibility, and unrelated changes.
   Apply the current DTVM high-stakes review rule when the change warrants it.

Completion gate: the implementation matches the confirmed plan, all `src/**`
work came through `compiler-agent`, and review findings are resolved or
explicitly accepted.

## 5. Verify and hand off locally

Run all repository-mandated gates before declaring the local implementation
verified:

```bash
tools/format.sh check
cmake --build build --target <relevant_target>
tools/dtvm_local_test.sh --auto
```

Also run every change-specific test from the accepted plan and confirm the
build output contains no new compiler warnings. Record exact commands, results,
and any skipped gate with its reason. Update affected module specs and record
the local verification evidence in the change document.

Keep the change document at `Accepted` throughout local handoff. Do not set it
to `Implemented` until the implementation has merged into the integration
branch. Only after that merge is verified may `doc-agent` set the status to
`Implemented`.

Hand off the local branch/worktree, diff summary, change-document path, review
result, verification evidence, and residual risks.

Stop at this verified local state. Do not automatically commit, archive, push,
open or update a pull request, merge, or deploy. Perform any of those actions
only when the user separately requests it. After merge, use `$dtvm-archive`
only on an explicit request and stop at the local `git mv`.

## Boundary with `dtvm-dev-workflow`

- Use `dtvm-dev-workflow` for routine fixes and other work outside the qualifying
  implementation categories; allow only its documented trivial-fix shortcut.
- Explicitly select `dtvm-dev-cycle` through DTVM project routing when the user
  asks to implement a new feature, architecture change, or breaking change, or
  when the user directly invokes `$dtvm-dev-cycle`, `/dtvm-dev-cycle`, or
  `/dev-cycle`.
- Require every proposal, acceptance, reviewed-plan, delegated-implementation,
  and verification gate. Do not skip phases merely because the change looks
  small.
- Keep DTVM-specific paths, agent ownership, review policy, and quality gates
  authoritative over generic workflow defaults.
