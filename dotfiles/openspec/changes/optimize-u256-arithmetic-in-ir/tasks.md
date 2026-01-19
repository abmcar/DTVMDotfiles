# Implementation Tasks

## 算法参考文档

在开始实现前,请仔细阅读以下算法分析文档:
- **[algorithm-mul.md](./algorithm-mul.md)** - U256 乘法算法分析与实现方案
- **[algorithm-div-mod.md](./algorithm-div-mod.md)** - U256 除法与模运算算法分析与实现方案

这些文档详细说明了:
- intx 库的实现原理和算法选择
- 现代 CPU 指令集优化机会 (BMI2, ADX)
- 推荐的 LLVM IR 实现方案
- EVM 规范要求和边界情况处理

## 1. Core U256 Arithmetic Operations
- [ ] 1.1 Implement `handleMul` with IR instructions (4x64 multiplication with carry handling)
- [ ] 1.2 Implement `handleDiv` with IR instructions (4x64 unsigned division)
- [ ] 1.3 Implement `handleMod` with IR instructions (4x64 unsigned modulo)
- [ ] 1.4 Implement `handleSDiv` with IR instructions (4x64 signed division with two's complement)
- [ ] 1.5 Implement `handleSMod` with IR instructions (4x64 signed modulo)

## 2. Modular Arithmetic Operations
- [ ] 2.1 Implement `handleAddMod` with IR instructions (512-bit intermediate for overflow handling)
- [ ] 2.2 Implement `handleMulMod` with IR instructions (512-bit intermediate for overflow handling)

## 3. Helper Functions and Utilities
- [ ] 3.1 Add helper function for multi-precision multiplication
- [ ] 3.2 Add helper function for multi-precision division
- [ ] 3.3 Add helper function for sign detection and two's complement conversion
- [ ] 3.4 Add helper function for zero division check

## 4. Testing and Validation
- [ ] 4.1 Run full EVM state tests: `python3 tools/run_evm_tests.py -r build/dtvm -m multipass --format evm --enable-evm-gas`
- [ ] 4.2 Verify all tests pass with new implementations
- [ ] 4.3 Run performance benchmark: `perf record -g -k 1 ./build/dtvm --format evm -m multipass perf/fibr.evm.hex --gas-limit 0xFFFFFFFFFFFF --calldata c6c2ea170000000000000000000000000000000000000000000000000000000000080003 --enable-evm-gas`
- [ ] 4.4 Compare performance metrics before and after optimization

## 5. Code Quality and Documentation
- [ ] 5.1 Add inline comments explaining IR instruction sequences
- [ ] 5.2 Document algorithm choices and trade-offs in code comments

## 6. Optional Optimizations (if time permits)
- [ ] 6.1 Add constant folding for division/modulo by powers of 2
- [ ] 6.2 Add specialized paths for small operands (< 64-bit)
- [ ] 6.3 Optimize common patterns (e.g., multiply-then-divide sequences)
