#!/usr/bin/env bash
# Guard against direct git checkout/rebase/switch in main working directory.
# Reminds to use worktrees for multi-branch operations.

CMD=$(jq -r '.tool_input.command // empty')

# Only care about git checkout/rebase/switch (not git checkout -- file)
case "$CMD" in
  git\ checkout\ --*|git\ checkout\ .) exit 0 ;;
  git\ checkout\ *|git\ switch\ *|git\ rebase\ *)
    ;;
  *) exit 0 ;;
esac

DIRTY=$(git status --porcelain 2>/dev/null | head -3)
BRANCH=$(git branch --show-current 2>/dev/null)

MSG="[git-branch-guard] Branch operation: $CMD"
if [ -n "$DIRTY" ]; then
  MSG="$MSG | DIRTY TREE on '$BRANCH' — uncommitted changes at risk"
fi
MSG="$MSG | REMINDER: use worktree for multi-branch work (git worktree add .worktrees/<name> <branch>)"

jq -nc --arg ctx "$MSG" '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": $ctx}}'
