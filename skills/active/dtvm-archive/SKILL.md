---
name: dtvm-archive
description: Archive specifically identified, completed DTVM change documents with a local git mv. Use only when the user explicitly asks to archive those exact DTVM changes after merge; never invoke automatically from dtvm-dev-workflow, dtvm-dev-cycle, merge or completion status alone, or general cleanup. Stop after the move without updating the archive index, committing, pushing, or opening a PR.
---

# DTVM Change Archival

Move only the DTVM change documents named in the user's explicit archive
request. Treat requests to finish a workflow, merge a branch, or clean up
completed work as insufficient authorization.

## Resolve the Target

1. Read the repository's current `AGENTS.md` and follow any stricter rule.
2. Require each requested source to match
   `docs/changes/YYYY-MM-DD-<slug>/`.
3. If the user did not identify the exact change, list candidates and stop for
   a choice. Do not infer a target from status or recency.
4. Derive the destination as
   `docs/_archive/<YYYY-MM>/<slug>/`. Use the current UTC month for `YYYY-MM`
   unless the user explicitly chose another archive month.

## Verify Preconditions

Before changing files, verify:

- the source exists, is tracked, and its checklist is complete;
- the implementation is merged into the current integration branch;
- required tests and review completed before the merge;
- related `docs/modules/` specifications already reflect contract changes;
- the exact source and destination paths have no local modifications or
  untracked files; and
- the destination does not exist.

Report any failed or unverifiable condition and stop. Leave unrelated dirty
files untouched; never stash, reset, clean, or rewrite them.

## Move and Stop

The explicit archive request authorizes the move once all preconditions pass.
Create only the required month directory, then run:

```bash
git mv "docs/changes/YYYY-MM-DD-<slug>" \
    "docs/_archive/<YYYY-MM>/<slug>"
```

Inspect `git status --short` for the two exact paths and hand off the staged
rename. Stop there.

Do not update `docs/_archive/README.md`, edit historical archived content, run
`git add`, commit, push, open an archive PR, or remove the branch/worktree. If
an archived change needs more work, create a new change proposal that
references it instead of editing the archive.
