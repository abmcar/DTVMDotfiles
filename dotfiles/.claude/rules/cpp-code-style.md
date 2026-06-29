---
description: C/C++ code style rules for DTVM source files
paths:
  - "src/**/*.cpp"
  - "src/**/*.h"
---

# C/C++ Code Style

## Naming (LLVM conventions)
- Variable names: `GasCost` (PascalCase)
- Function names: `chargeGas` (camelCase)

## Comments
- Only include essential comments — avoid excessive documentation
- All comments must be written in English

## File Rules
- Files must end with a single trailing newline, not a trailing blank line — clang-format enforces this for `.cpp`/`.h`; `format.sh` enforces it separately for `tests/evm_asm`
- Code follows clang-format style

## License Header
New .h and .cpp files must begin with:
```cpp
// Copyright (C) <current year> the DTVM authors. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
```
Stamp the current year for a new file. Existing files may show a range (e.g. `2021-2023`) spanning their edit history; do not copy a stale literal year.

## Formatting
Always run `tools/format.sh check` before finishing, and `tools/format.sh format` to auto-fix.
Run `tools/format.sh tidy-check` to validate identifier naming via clang-tidy (needs a built `build/`; samples a few files).
