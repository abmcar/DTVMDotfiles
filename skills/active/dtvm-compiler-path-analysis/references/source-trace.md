# Current-source trace anchors

Use these searches as entry points. Read the matched definitions and their
callers; the source commit from the evidence bundle is authoritative.

## Pipeline spine

```bash
rg -n "performEVMJITCompile|EagerEVMJITCompiler::compile|compileEVMToMC" \
  src/action src/compiler
rg -n "buildEVMFunction|EVMMirBuilder::compile" src/compiler/evm_frontend \
  src/compiler/evm_compiler.cpp
rg -n "compileMIRToCgIR|MVerifier|DeadMBasicBlockElim|X86CgLowering" \
  src/compiler/compiler.cpp src/compiler
rg -n "FastRA|CgRAGreedy|CgVirtRegRewriter|PrologEpilogInserter|ExpandPostRAPseudos" \
  src/compiler/compiler.cpp src/compiler/cgir/pass
rg -n "runOnCgFunction|emitFunctionBody|emitInstruction|X86MCInstLower::lower" \
  src/compiler/cgir/mc_lowering.h src/compiler/target/x86
rg -n "emitObjectBuffer|createObjectFile|mprotect" \
  src/compiler/compiler.cpp src/compiler/evm_compiler.cpp
```

Expected current route:

```text
performEVMJITCompile
  → EagerEVMJITCompiler::compile
  → buildEVMFunction
  → EVMJITCompiler::compileEVMToMC
  → EVMMirBuilder::compile
  → JITCompilerBase::compileMIRToCgIR
  → X86CgLowering
  → FastRA or CgRAGreedy and supporting passes
  → PrologEpilogInserter / ExpandPostRAPseudos
  → X86MCLowering / X86MCInstLower
  → emitObjectBuffer
```

Verify every arrow at the recorded commit; constructors may execute a pass.

## Ambiguous sampled symbols

Extract the class-qualified symbol first:

```bash
c++filt "<raw-symbol>"
rg -n "\\bisDead\\s*\\(" src/compiler
rg -n "\\bsetInsertBlock\\s*\\(" src/compiler
```

Then search the containing class and its callers. `isDead` appears in operand,
slot-index, live-interval, frame, and dead-instruction contexts; these are
different mechanisms. `setInsertBlock` exists in frontend and lowering
builders; use the sampled class and parent frames to select one.

## Synchronous assembly-dump branch

```bash
rg -n "ZEN_ENABLE_LINUX_PERF|ZEN_ENABLE_MULTIPASS_JIT_LOGGING|dumpAsm" \
  src/compiler/compiler.cpp src/compiler/CMakeLists.txt
rg -n "objdump|system\\s*\\(" src/compiler/utils/asm_dump.cpp
```

Classify samples under `objdump` or its shell as inherited child cost. Prove
whether the recorded build enables the source branch from
`metadata/CMakeCache.txt`.

## Evidence rules

- Cite `path + symbol`, adding current line numbers only as navigation.
- Pair a perf call chain with source call sites for each claimed dynamic route.
- Label template dispatch, constructor side effects, and inferred hops.
- Count current IR or calls only when the hypothesis needs that count.
- Re-measure costs; static per-opcode and instruction-cost tables drift.
