# Strict validation for published skills

- **Status**: Accepted
- **Date**: 2026-07-28
- **Tier**: Full

## Decision

Treat a skill as publishable only after its source package passes one shared,
read-only validation path. DTVMDotfiles does not generate reduced project
mirrors from another repository SSOT. Repository skills that are replaced or
retired remain an ownership and suppression decision; their invalid generated
Claude mirrors are not accepted as adapters merely because their generator
reports them current.

## Contract

`tools/quick_validate.py` validates one skill without writing bytecode or other
derived files. Active DTVMDotfiles skills additionally require:

- exact YAML frontmatter with a matching `name` and non-empty `description`;
- a non-placeholder instruction body;
- a current-schema `agents/openai.yaml` whose UI strings are quoted and whose
  default prompt names the skill;
- local resource references that stay inside the skill and resolve;
- portable scripts with valid Python or shell syntax, with executable bits on
  entry points but not interpreter-invoked resources under `scripts/tests/`;
  and
- a deterministic hook under `skills/validation-hooks/` for every
  script-bearing skill.

Hooks run against a temporary, `.git`-free repository snapshot and skill copy,
with isolated home, cache, temporary directory, and fixed working directory.
The validator fingerprints both copies and the real source before and after
each hook. A mutating hook changes only the disposable copy and is rejected.
The hook registry may name a skill that is not active in the current branch so
that independent skill branches can compose without weakening the final gate.

Repository-level skill and adapter regressions use the explicit
`tests/skill-test-registry.txt` list. The runner does not discover tests
recursively. It executes every registered test once in a separate repository
snapshot and suppresses nested registry execution when a test exercises
`skills.sh`, worktree initialization, or release preflight.

## Entry points

- Validation requires Python 3, PyYAML 6.x, and Bash 4.3 or newer. A missing
  YAML parser is a hard failure, never a fallback to line-oriented parsing.
- `bash skills.sh validate` validates source packages and hooks, then executes
  every registered repository skill test.
- `bash skills.sh check` passes the same gate before checking deployed links
  and client adapters.
- `bash skills.sh sync` and `release.sh` pass the same validation before any
  publication write.

The release command is not a validation test command. Development and CI use
the read-only `validate` and `check` paths.

## Verification

- Run the shared quick validator over every active skill.
- Run `tests/skill_validation_test.sh`.
- Run `tests/agent_skills_test.sh`.
- Run the active-skill hooks.
- Run shell syntax and ShellCheck over changed shell files.
- Run `bash skills.sh check` only against already deployed local state; do not
  run `release.sh` as part of validation.
