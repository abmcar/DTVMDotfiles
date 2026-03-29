---
description: Commit message and PR title conventions
globs: []
alwaysApply: false
---

# Commit and PR Conventions

Follow the conventions defined in `commitlint.config.js`.

## Format
```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

## Type (required)
- `feat` - A new feature
- `fix` - A bug fix
- `docs` - Documentation only changes
- `style` - Code style changes (formatting, white-space, etc.)
- `refactor` - Code changes that neither fix bugs nor add features
- `perf` - Performance improvements
- `test` - Adding or correcting tests
- `build` - Build system or dependency changes
- `ci` - CI configuration changes
- `chore` - Other changes that don't modify src or test files

## Scope (required)
- `core` - Core engine code
- `runtime` - Runtime library
- `compiler` - Compiler related
- `evm` - EVM interpreter and handlers
- `examples` - Example code
- `docs` - Documentation related
- `tools` - Tool related
- `deps` - Dependency related
- `ci` - CI related
- `test` - Test related
- `other` - Other changes
- `` (empty) - No specific scope

## Rules
- Header must not exceed 100 characters
- Subject must not end with a period
- Type must be lowercase
- Use imperative mood in subject (e.g., "add feature" not "added feature")

## PR Title Format
PR titles follow the same format: `<type>(<scope>): <subject>`
