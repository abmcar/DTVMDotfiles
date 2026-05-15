---
description: Commit message and PR title conventions
globs: []
alwaysApply: true
---

# Commit and PR Conventions

The authoritative type/scope enum and length rules live in
`commitlint.config.js` at the repo root — read it directly rather than
trust any summary here.

## Format
```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

Both commit messages and **PR titles** follow this format.

## Additional conventions

- Use imperative mood in subject ("add feature", not "added feature").
- PR description must explain what changed and why.
