---
name: dtvm-dotfiles-usage
description: Explain and operate the DTVMDotfiles workflow. Use when the user asks how to set up from DTVMDotfiles, how `release.sh` and `store.sh` work, how `exclude.map.sh` and `skills.map.sh` behave, how managed versus external skills are handled, or how to sync dotfiles changes between `DTVMDotfiles` and the parent DTVM workspace.
---

# DTVMDotfiles Usage

Treat the checked-in DTVMDotfiles scripts and docs as authoritative.

Read these files before answering any workflow question or making changes:

- `DTVMDotfiles/release.sh`
- `DTVMDotfiles/store.sh`
- `DTVMDotfiles/lib/sync_common.sh`
- `DTVMDotfiles/dotfiles/exclude.map.sh`
- `DTVMDotfiles/dotfiles/skills.map.sh`
- `DTVMDotfiles/RELEASE_STORE_README.md`
- `DTVMDotfiles/QUICK_START.md`

## Use This Skill For

- explaining how to bootstrap a workspace with `setup_from_dotfiles.sh`
- explaining or editing the `release.sh` / `store.sh` workflow
- deciding whether a skill should be `managed` or `external`
- explaining why `.git/info/exclude` contains generated entries
- debugging why a dotfiles-managed file did or did not sync

Do not stretch this skill into general git workflow or unrelated DTVM build/test
questions.

## Workflow

1. Identify whether the request is about setup, release, store, exclude
   generation, or skill synchronization.
2. Re-read the relevant script and the matching DTVMDotfiles doc before making
   assertions. The docs are summaries; the shell scripts are the source of
   truth.
3. For skill handling:
   - `managed` means DTVMDotfiles owns the skill content under
     `DTVMDotfiles/dotfiles/.agents/skills/`
   - `external` means the skill is owned by another git workflow and must not
     be copied into DTVMDotfiles
4. Remember that `release.sh` generates parent `.git/info/exclude` from
   `exclude.map.sh` and auto-adds `.agents/skills/<skill>/` for every
   `managed` skill.
5. Remember that `store.sh` rebuilds `exclude.map.sh` from parent
   `.git/info/exclude`, but filters out those auto-derived managed-skill
   exclude lines.

## Output Requirements

When answering a DTVMDotfiles usage question, include:

- which script or file is authoritative for that answer
- whether the behavior happens during `release.sh`, `store.sh`, or both
- whether the path or skill should be treated as `managed` or `external`
- any follow-up command the user should run, such as `./release.sh` or
  `./store.sh`
