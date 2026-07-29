# Current-source trace anchors

Use these searches as entry points. Read the matched definitions and their
callers; the source commit from the evidence bundle is authoritative.

## Contents

- [Pipeline spine](#pipeline-spine)
- [Ambiguous sampled symbols](#ambiguous-sampled-symbols)
- [Frontend and lowering invariants](#frontend-and-lowering-invariants)
- [Synchronous assembly-dump branch](#synchronous-assembly-dump-branch)
- [Evidence rules](#evidence-rules)

## Pipeline spine

```bash
rg -n "CacheNeedsSPP|performEVMJITCompile|EagerEVMJITCompiler::compile" \
  src/runtime/evm_module.* src/action/compiler.* src/compiler/evm_compiler.cpp
rg -n "getBytecodeCache|initBytecodeCache|buildBytecodeCache|buildGasChunksSPP|EnableSPP" \
  src/runtime/evm_module.* src/evm/evm_cache.* src/compiler/evm_compiler.cpp
rg -n "buildEVMFunction|compileEVMToMC|EVMMirBuilder::compile" \
  src/compiler/evm_frontend src/compiler/evm_compiler.cpp
rg -n "compileMIRToCgIR|MVerifier|DeadMBasicBlockElim|X86CgLowering|X86CgPeephole|CgPhiElimination" \
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
  → EVMModule::getBytecodeCache [cold first access]
  → EVMModule::initBytecodeCache
  → evm::buildBytecodeCache
  → buildGasChunksSPP [full SPP only when enabled and blocks are nonempty]
  → buildEVMFunction [install the function type]
  → EVMJITCompiler::compileEVMToMC
  → EVMMirBuilder::compile [build MIR]
  → JITCompilerBase::compileMIRToCgIR
  → MVerifier / DeadMBasicBlockElim
  → X86CgLowering [constructor] → X86CgPeephole [constructor]
  → CgPhiElimination::runOnCgFunction
  → FastRA [constructor] or greedy support constructors / CgRAGreedy / CgVirtRegRewriter
  → PrologEpilogInserter / ExpandPostRAPseudos
  → X86MCLowering / X86MCInstLower
  → emitObjectBuffer
```

For the default non-PGJ cold-cache route, prove that module setup sets
`CacheNeedsSPP=true` before `performEVMJITCompile` and that the timer starts in
`EagerEVMJITCompiler::compile`. Include the cache-build hops only on first
access. Mark warm-cache and profile-guided JIT (PGJ) routes conditional. Inside
`buildGasChunksSPP`, include the full SPP route only when `EnableSPP` is true
and blocks are nonempty.

Verify every arrow at the recorded commit. Label constructor side effects;
`X86CgLowering`, `X86CgPeephole`, and register-allocation constructors execute
pipeline work.

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

## Frontend and lowering invariants

The retired `dmir-compiler-analysis` guide captured several structural
invariants that remain useful as search leads. Verify each one against the
bundle's source commit before relying on it:

- EVM U256 values are normally represented as four little-endian `i64` limbs.
  Trace all four definitions and uses when evaluating a frontend rewrite.
- Multi-limb addition lowers through a carry-flag chain. Materialization such
  as `protectUnsafeValue` prevents intervening flag-clobbering expressions;
  prove instruction adjacency before changing or removing it.
- Paired pseudo-operations such as low/high multiply-result extraction may
  communicate through lowering-side state. Trace both operations and their
  ordering as one unit.
- Runtime calls trade a smaller IR graph for ABI moves, caller-saved pressure,
  and out-of-line work. Attribute both compile-time and runtime effects before
  proposing inlining.

Useful current-source searches:

```bash
rg -n "protectUnsafeValue|handleBinaryArithmetic|handleMul" \
  src/compiler/evm_frontend
rg -n "lowerAdcExpr|lowerEvmUmul128|Umul128HiRegs" \
  src/compiler/target/x86 src/compiler/cgir
rg -n "isRAExpensiveOpcode|MIR_OPCODE_WEIGHT" \
  src/compiler/evm_frontend
```

Do not reuse historical per-opcode instruction counts or latency tables as
evidence. Reconstruct the emitted IR at the recorded commit and pair static
counts with perf samples or focused counters.

## Synchronous assembly-dump branch

```bash
rg -n "ZEN_ENABLE_JIT_LOGGING|ZEN_ENABLE_LINUX_PERF" \
  "$BUNDLE/metadata/CMakeCache.txt"
rg -n "ZEN_ENABLE_JIT_LOGGING|ZEN_ENABLE_LINUX_PERF|ZEN_ENABLE_MULTIPASS_JIT_LOGGING" \
  src/CMakeLists.txt
rg -n "ZEN_ENABLE_JIT_LOGGING|ZEN_ENABLE_LINUX_PERF|asm_dump.cpp" \
  src/compiler/CMakeLists.txt
rg -n "ZEN_ENABLE_LINUX_PERF|ZEN_ENABLE_MULTIPASS_JIT_LOGGING|dumpAsm" \
  src/compiler/compiler.cpp
rg -n "objdump|system\\s*\\(" src/compiler/utils/asm_dump.cpp
```

Prove the branch in order: CMake cache option, `src/CMakeLists.txt` macro
mapping, `src/compiler/CMakeLists.txt` source inclusion, `compiler.cpp`
`dumpAsm` branch, then the `objdump` / `system` child. Classify samples under
`objdump` or its shell as inherited child cost.

## Evidence rules

- Cite `path + symbol`, adding current line numbers only as navigation.
- Pair a perf call chain with source call sites for each claimed dynamic route.
- Label template dispatch, constructor side effects, and inferred hops.
- Treat timer containment as scope, not cost evidence; require samples or a
  focused counter before recommending a cache/SPP seam.
- Count current IR or calls only when the hypothesis needs that count.
- Re-measure costs; static per-opcode and instruction-cost tables drift.
