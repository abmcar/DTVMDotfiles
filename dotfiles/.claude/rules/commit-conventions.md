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

## What's NOT in commitlint.config.js

- Use imperative mood in subject (e.g., "add feature" not "added feature").
- PR description must explain what changed and why.
- Subject should be a single sentence; no period at end (enforced by config,
  noted here for context).
