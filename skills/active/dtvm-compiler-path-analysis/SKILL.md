---
name: dtvm-compiler-path-analysis
description: Source-trace measured DTVM compile hotspots through the current dMIR, CGIR, register-allocation, and machine-code pipeline. Use when perf names a high-share compiler symbol, a suspected pass such as isDead or setInsertBlock, or a minimum source seam is needed before editing src/.
---

# DTVM Compiler Path Analysis

Build a **source trace** from measured symbol to current implementation. Treat
historical cost tables and remembered line numbers as leads, never evidence.

## 1. Bind the trace to evidence

Start from a completed `dtvm-cold-compile-profile` bundle. Verify:

```bash
grep -Fx "status=complete" "$BUNDLE/status.txt"
(
  cd "$BUNDLE"
  sha256sum -c manifest.sha256
)
```

Record the bundle's source commit, command hash, command/DSO, raw symbol, and
percentage. Demangle C++ symbols with `c++filt`, retaining the raw name.

If the hot command is `objdump`, a shell, linker, or another child, trace that
process boundary first. Do not relabel inherited work as an in-process compiler
pass.

Completion criterion: every requested hotspot has a raw symbol, demangled
symbol, command, DSO, share, and matching bundle identity.

## 2. Trace current source

Read [references/source-trace.md](references/source-trace.md) for pipeline
anchors and search patterns. Run its `rg` searches against the commit recorded
in the bundle. Use symbol names and call sites as anchors rather than stored
line numbers.

For ambiguous names such as `isDead` or `setInsertBlock`, identify the sampled
class and its callers before assigning a stage. Follow the live route across:

```text
EVM frontend → dMIR → CGIR lowering → RA → post-RA → MC → object loading
```

Use perf call chains as dynamic evidence and source call sites as static
evidence. Mark a hop inferred when either side is missing.

Completion criterion: each hot symbol reaches a pipeline entry point or a
proved child-process boundary, with every hop backed by a file-and-symbol
anchor.

## 3. Form falsifiable hypotheses

For each high-share route, state:

- the cost mechanism: call volume, allocation, graph walk, repeated lookup,
  serialization, or synchronous child work;
- the evidence already present;
- one measurement that would falsify the mechanism;
- correctness and determinism invariants at risk;
- the smallest source seam that could change the mechanism.

Static occurrence counts do not estimate runtime cost. Derive cost from the
current source shape plus measured samples, and request counters or focused
instrumentation when attribution remains ambiguous.

Completion criterion: every proposed seam has a measured mechanism, a
falsifier, and named invariants; otherwise report that no defensible seam is
available.

## 4. Return the analysis

Use this evidence table:

| Perf share | Command / DSO | Symbol | Stage | Definition anchor | Route evidence | Interpretation |
|---:|---|---|---|---|---|---|

Then report:

1. the full source trace;
2. ranked hypotheses and falsifiers;
3. the minimum implementation seam, or `none`;
4. a focused verification plan tied to the baseline bundle;
5. uncertainties and inherited-child cost.

The analysis is complete only when every selected hotspot is accounted for and
the recommended seam can be handed to `compiler-agent` without rediscovering
the route.
