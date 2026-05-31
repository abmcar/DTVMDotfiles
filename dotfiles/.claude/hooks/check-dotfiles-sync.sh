#!/bin/bash
# PostToolUse hook: warn when a DTVMDotfiles-managed file is modified.
# Case glob below must stay aligned with MIRRORED_ITEMS in DTVMDotfiles/lib/sync_common.sh.
# CLAUDE.local.md is per-machine, not managed by this hook.

set -euo pipefail

INPUT=$(cat)
# Extract file_path with jq (portable; matches the sibling hooks in settings.json).
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || true

[ -z "$FILE_PATH" ] && exit 0
# Defense in depth: dir-walk requires an absolute path; CC tool schema enforces this anyway.
case "$FILE_PATH" in /*) ;; *) exit 0 ;; esac

# Resolve repo root by walking up from FILE_PATH until we find the manifest.
# Using $0-relative paths breaks in worktrees (.claude/ is symlinked to main repo).
d="$(dirname "$FILE_PATH")"
while [ "$d" != "/" ] && [ ! -f "$d/.claude/.dtvm-manifest.json" ]; do d="$(dirname "$d")"; done
[ "$d" = "/" ] && exit 0
REPO_ROOT="$d"

# Make path relative to the main repo root (found via the manifest walk above).
REL_PATH="${FILE_PATH#"$REPO_ROOT"/}"

# If path didn't change, it's outside the repo
[ "$REL_PATH" = "$FILE_PATH" ] && exit 0

# A managed file edited inside a registered worktree arrives prefixed with that
# worktree's path (e.g. .worktrees/feat/<branch>/ or .claude/worktrees/<name>/,
# possibly through a symlinked .claude/). Strip the prefix of whichever registered
# worktree of THIS repo contains it, so the managed-item match fires regardless of
# branch-name depth or symlinks. String-prefix match against `git worktree list`
# (not `rev-parse --show-toplevel`, which would follow symlinks back to main or
# resolve into a nested independent repo). Nested independent repos like
# docs/research (DTVM-Papers, its own .git) are NOT registered worktrees, so they
# keep their prefix and the docs/research/* reminder still fires.
case "$REL_PATH" in
    .worktrees/*|.claude/worktrees/*)
        while IFS= read -r wt; do
            wt_rel="${wt#"$REPO_ROOT"/}"
            [ "$wt_rel" = "$wt" ] && continue   # the main repo entry (or outside REPO_ROOT)
            case "$REL_PATH" in
                "$wt_rel"/*) REL_PATH="${REL_PATH#"$wt_rel"/}"; break ;;
            esac
        done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
        ;;
esac

# Check against managed items
MANIFEST="$REPO_ROOT/.claude/.dtvm-manifest.json"
case "$REL_PATH" in
    .claude/*|CLAUDE.md|init.sh|perf/*.sh|perf/*.hex|.agents/skills/worktree-bootstrap/*)
        # store.sh is manifest-guided — only files in the manifest will be picked up.
        # New files in managed directories need a one-time bootstrap via release.sh.
        if [ -f "$MANIFEST" ] && grep -q "\"$REL_PATH\":" "$MANIFEST"; then
            echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[dotfiles-sync] A DTVMDotfiles-managed file was modified. Remember to run store.sh and push DTVMDotfiles before ending this session."}}'
        else
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"[dotfiles-sync] $REL_PATH is in a managed directory but NOT yet in .claude/.dtvm-manifest.json. store.sh will skip it. Bootstrap once with: cp '$REL_PATH' DTVMDotfiles/dotfiles/'$REL_PATH' && bash DTVMDotfiles/release.sh\"}}"
        fi
        ;;
    docs/research/*)
        echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[paper-repo] docs/research/ is a separate git repo (DTVM-Papers). Remember to commit and push it independently before ending this session."}}'
        ;;
esac

exit 0
