---
name: dmir-compiler-analysis
description: Preserve the retirement record for the former DTVM dMIR compiler-analysis workflow. This archival skill is not a workflow entry; use dtvm-compiler-path-analysis for current compiler-path analysis.
---

# Retired: dMIR Compiler Analysis

Do not publish or invoke this skill. Use
`dtvm-compiler-path-analysis` from `skills/active/` for current work.

The former repository skill mixed source tracing with static opcode expansions
and x86 cost estimates. Those tables drift with the compiler and are not
preserved as current guidance. The durable parts were curated into
`skills/active/dtvm-compiler-path-analysis/references/source-trace.md`:

- the four-limb U256 representation;
- carry-flag chain and paired pseudo-op invariants;
- current-source tracing anchors;
- the requirement to re-measure costs instead of citing historical estimates.

The original tracked DTVM files remain repository-owned historical artifacts.
DTVMDotfiles suppresses their skill name locally and does not treat those files
as the personal-skill source of truth.
