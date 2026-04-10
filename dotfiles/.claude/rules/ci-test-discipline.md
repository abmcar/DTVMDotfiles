---
description: Behavioral rules for testing discipline — never skip required tests, never push without confirmation, follow CI failure investigation protocol.
globs: []
alwaysApply: true
---

# CI Test Discipline

## Rule 1: Never silently skip required tests

If the user's prompt or change doc specifies a test command and it fails to
run, you MUST report the failure explicitly. Do not substitute a different
test and claim equivalence.

Say: "I could not run <X> because <reason>. The results below are from <Y>
only — this does not cover the same scope."

Do not declare "tests pass" when you skipped a required test category.

## Rule 2: Push requires explicit user confirmation

Do not run `git push` unless the user's prompt explicitly says to push
(e.g., "push", "push it", "push to origin", "push 上去").

After tests pass, report the results and wait. Example:
"All tests pass. Ready to push when you say so."

## Rule 3: CI failure investigation protocol

When local tests pass but CI fails, follow this protocol — do not skip steps:

1. `gh run view <id> --log-failed` — get the exact CI failure output.
2. Compare `build/CMakeCache.txt` against the CI workflow env vars in
   `.github/workflows/dtvm_evm_test_x86.yml`. Look for flag differences
   (`CPU_EXCEPTION`, `VIRTUAL_STACK`, `LIBEVM`, `JIT_PRECOMPILE_FALLBACK`).
3. If flags differ, reconfigure locally with CI flags (see
   `.claude/rules/dtvm-build-config.md`) and re-test.
4. If flags match and the failure still does not reproduce locally, **report
   the discrepancy to the user**. Include: which flags match, what the CI
   error is, and what you tried. Do NOT push a speculative fix.
