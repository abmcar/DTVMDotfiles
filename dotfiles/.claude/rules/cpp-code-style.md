---
description: C/C++ code style rules for DTVM source files
globs: ["src/**/*.cpp", "src/**/*.h"]
alwaysApply: false
---

# C/C++ Code Style

## Naming (LLVM conventions)
- Variable names: `GasCost` (PascalCase)
- Function names: `calcGasCost` (camelCase)

## Comments
- Only include essential comments — avoid excessive documentation
- All comments must be written in English

## File Rules
- Last line must contain exactly one blank line — no more, no less
- Code follows clang-format style

## License Header
New .h and .cpp files must begin with:
```cpp
// Copyright (C) 2025 the DTVM authors. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
```

## Formatting
Always run `tools/format.sh check` before finishing, and `tools/format.sh format` to auto-fix.
