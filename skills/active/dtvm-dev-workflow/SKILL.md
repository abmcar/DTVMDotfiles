---
name: dtvm-dev-workflow
description: Coordinate ordinary DTVM improvements and routine fixes through project-owned change documents, module specs, delegated implementation, and quality gates. Route feature implementation, new features, architecture or breaking changes, and explicit dev-cycle requests to the project-owned dtvm-dev-cycle; use the Full-tier workflow here when that skill is not discoverable.
---

# DTVM Development Workflow

Keep the change document, implementation, module specifications, and evidence
consistent. Treat a passed gate as evidence, not as an intention.

## 1. Select the workflow

Read the current project instructions and inspect the repository state before
planning a mutation. Preserve unrelated and pre-existing worktree changes.

Route escalation before choosing a local path:

- For feature implementation, a new feature, an architecture change, a
  breaking change, or an explicit `dev-cycle` request, invoke the
  project-owned `dtvm-dev-cycle` when it is discoverable and stop this
  workflow.
- If `dtvm-dev-cycle` is not discoverable, state that once and continue here
  at Full tier.
- Do not escalate an ordinary improvement or routine fix to `dtvm-dev-cycle`.

For work that remains in this workflow:

- Use **Full** for the escalation fallback, non-breaking cross-module
  contracts, determinism or security changes, and cross-cutting performance
  work.
- Use **Light** for a single-module, well-scoped improvement with limited blast
  radius.
- Skip proposal and planning only for a typo-only, comment-only, test-only, or
  clearly behavior-preserving trivial fix that the user already authorized.
  A bug fix or single-file change does not qualify by size alone. Start at
  execution and keep every applicable quality gate.

When an isolated DTVM worktree is required, invoke
`dtvm-worktree-bootstrap`. Do not reproduce its branch, submodule, dotfile,
configure, or build procedure.

Completion criterion: record the selected path, tier, repository/worktree, and
the reason `dtvm-dev-cycle` was selected, unavailable, or not required.

## 2. Propose the change

Delegate change-document creation or revision to `doc-agent`. Create exactly:

```text
docs/changes/YYYY-MM-DD-<slug>/README.md
```

Use `docs/changes/template.md` for Full and
`docs/changes/template-light.md` for Light. Set the status to `Proposed` and
update the `docs/changes/README.md` entry when the repository convention
requires it. Define:

- outcome and motivation;
- affected modules and contracts;
- compatibility, determinism, and safety implications;
- implementation phases or checklist;
- tests, risks, and acceptance evidence.

Do not implement a material change while its proposal is still `Proposed`.
After approval, set it to `Accepted`.

Completion criterion: one in-repository change document has the correct path,
tier, accepted scope, and `Accepted` status.

## 3. Build the implementation plan

Consult every affected `docs/modules/<module>/spec.md` before fixing the plan.
Use `research-agent` for read-only codebase or external investigation when the
change crosses unfamiliar code or when evidence is missing.

Record:

- affected files, symbols, contracts, and specs;
- ordered implementation units and their owners;
- build target and touched-path test selection;
- determinism, compatibility, memory-safety, and rollback risks;
- evidence required before each unit and before handoff.

Keep the plan synchronized with the accepted change document. Obtain
confirmation before proceeding when the plan expands the accepted scope.

Completion criterion: every accepted requirement maps to an implementation
unit, an owner, and a verification step; relevant module specs have been read.

## 4. Execute through the project agents

Delegate by ownership:

| Work | Agent |
|---|---|
| Any `src/**` implementation | `compiler-agent` |
| Profiling, benchmarks, or performance comparisons | `perf-agent` |
| Test suites, CI reproduction, and result analysis | `test-agent` |
| Read-only exploration or research | `research-agent` |
| Change documents and module specs | `doc-agent` |

Dispatch independent units in parallel. Give each agent the accepted scope,
exact paths, invariants, expected artifacts, and relevant gates. Keep
integration, scope control, and user communication with the coordinator.

After each logical unit:

1. inspect the diff for unrelated edits;
2. build the affected target when code changed;
3. run focused tests before depending on the unit;
4. update the plan and change-document checklist;
5. stop on a determinism, contract, or ownership violation.

For a high-stakes paper, plan, PR-closure, or direction-document review, follow
the current project instruction for separate Opus and Codex reviewers. Use one
or two rounds and never more than three.

Completion criterion: each unit is integrated, its local evidence is recorded,
and the final diff remains within the accepted scope.

## 5. Verify and close implementation

Run the DTVM gates that apply to the final diff:

```bash
tools/format.sh check
cmake --build build --target <relevant-target>
tools/dtvm_local_test.sh --auto
```

Inspect build output for new compiler warnings. Run any additional tests named
by the change document or affected module spec. Do not substitute a dry run,
an earlier commit's result, or another build directory's result.

Delegate contract/spec synchronization to `doc-agent`. Mark checklist items
from actual evidence. Set the change status to `Implemented` only when the
implementation is complete and merged, module specs reflect contract changes,
and required gates pass. Until merge, report implementation and verification
as complete while leaving the status `Accepted`.

Report the absolute worktree, affected files, gate commands and results,
warnings, remaining risks, and change-document path.

## 6. Keep archival explicit

Do not archive as a normal completion step. Leave merged change documents in
`docs/changes/` unless the user explicitly asks to archive a named change.

On that explicit request, invoke `$dtvm-archive`. Its boundary is a verified
local move into `docs/_archive/<YYYY-MM>/<slug>/`; never push or open an
archive PR.
If `dtvm-archive` is unavailable, stop after reporting that the archival
capability is not deployed. Do not silently reproduce or partially execute its
move.
