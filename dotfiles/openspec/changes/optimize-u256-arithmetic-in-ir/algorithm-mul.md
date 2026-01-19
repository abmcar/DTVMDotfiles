# U256 乘法算法分析与实现方案

## 1. intx 库的实现

### 1.1 算法选择: Schoolbook Multiplication

intx 库对 U256 乘法使用经典的 **Schoolbook Multiplication (学校乘法)** 算法,实现在 `intx.hpp:1524-1542`:

```cpp
template <unsigned N>
inline constexpr uint<2 * N> umul(const uint<N>& x, const uint<N>& y) noexcept
{
    constexpr auto num_words = uint<N>::num_words;  // 对于 uint256, num_words = 4

    uint<2 * N> p;  // 512-bit 结果
    for (size_t j = 0; j < num_words; ++j)     // 外层循环: y 的每个字
    {
        uint64_t k = 0;  // 进位
        for (size_t i = 0; i < num_words; ++i) // 内层循环: x 的每个字
        {
            auto a = addc(p[i + j], k);                          // p[i+j] + carry
            auto t = umul(x[i], y[j]) + uint128{a.value, a.carry};  // 64x64->128 + 前面的和
            p[i + j] = t[0];  // 低64位
            k = t[1];         // 高64位作为新进位
        }
        p[j + num_words] = k;  // 最终进位
    }
    return p;
}
```

**算法特点**:
- 双层循环,外层遍历 y 的每个 64-bit 字,内层遍历 x 的每个 64-bit 字
- 每次内层循环执行一次 64x64->128 位乘法
- 对于 256-bit 乘法,共需要 16 次 64x64 乘法 (4x4)
- 复杂度: O(n²) where n = num_words

### 1.2 64x64->128 乘法的三种实现策略

```cpp
inline constexpr uint128 umul(uint64_t x, uint64_t y) noexcept
{
    // 策略 1: 编译器内建 __int128 (GCC/Clang)
    #if INTX_HAS_BUILTIN_INT128
        return builtin_uint128{x} * builtin_uint128{y};

    // 策略 2: MSVC intrinsic _umul128 (x64)
    #elif defined(_MSC_VER) && defined(_M_X64)
        unsigned __int64 hi = 0;
        const auto lo = _umul128(x, y, &hi);
        return {lo, hi};

    // 策略 3: 可移植实现 - 使用 32x32->64 分解
    #endif
        // 将 64-bit 分解为两个 32-bit
        uint64_t xl = x & 0xffffffff;
        uint64_t xh = x >> 32;
        uint64_t yl = y & 0xffffffff;
        uint64_t yh = y >> 32;

        // 4 次 32x32 乘法
        uint64_t t0 = xl * yl;
        uint64_t t1 = xh * yl;
        uint64_t t2 = xl * yh;
        uint64_t t3 = xh * yh;

        // Karatsuba 风格的组合
        uint64_t u1 = t1 + (t0 >> 32);
        uint64_t u2 = t2 + (u1 & 0xffffffff);

        uint64_t lo = (u2 << 32) | (t0 & 0xffffffff);
        uint64_t hi = t3 + (u2 >> 32) + (u1 >> 32);
        return {lo, hi};
}
```

**优先级**: 策略 1 > 策略 2 > 策略 3

## 2. 现代 CPU 指令集支持

### 2.1 BMI2 (Bit Manipulation Instruction Set 2)

**MULX 指令** (Haswell 2013+):
- 功能: 64x64 -> 128 无符号乘法
- 优势:
  - 不影响 FLAGS 寄存器,允许更好的指令调度
  - 支持三操作数形式: `mulx rdx, rax, [mem]`
  - 延迟更低,吞吐量更高

### 2.2 ADX (Multi-Precision Add-Carry Extensions)

**ADCX/ADOX 指令** (Broadwell 2014+):
- `ADCX`: 使用 CF (Carry Flag) 的带进位加法
- `ADOX`: 使用 OF (Overflow Flag) 的带进位加法
- **关键优势**: 使用不同标志位,支持**双进位链并行**

示例:
```asm
; 传统方式 (串行,依赖 CF)
mul  rax        ; 影响 CF
adc  rbx, 0     ; 依赖 CF
adc  rcx, 0     ; 依赖 CF

; BMI2+ADX 优化 (并行)
mulx rdx, rax, [mem]  ; 不影响 FLAGS
adcx rbx, rax         ; 使用 CF 链
adox rcx, rdx         ; 使用 OF 链 (可与 ADCX 并行!)
```

### 2.3 CPU 支持情况

| 微架构 | BMI2 (MULX) | ADX (ADCX/ADOX) |
|--------|-------------|-----------------|
| Intel Haswell (2013) | ✅ | ❌ |
| Intel Broadwell (2014) | ✅ | ✅ |
| AMD Zen (2017) | ✅ | ❌ |
| AMD Zen 2 (2019) | ✅ | ✅ |
| ARM64 | UMULH 指令 | - |

## 3. 算法复杂度对比

| 算法 | 复杂度 | 256-bit 乘法次数 | 适用范围 |
|-----|--------|-----------------|---------|
| Schoolbook | O(n²) | 16 | ≤512 bit |
| Karatsuba | O(n^1.585) | ~9-10 | 512-2048 bit |
| Toom-Cook-3 | O(n^1.465) | ~5-6 | >2048 bit |

**结论**: 对于 256-bit,Schoolbook 算法是最优选择
- Karatsuba 的交叉点约在 512-1024 bit
- 常数因子使得 Schoolbook 在小尺寸更快

## 4. LLVM IR 实现方案

### 4.1 方案 1: 直接表达算法逻辑 (推荐)

在 IR 中直接实现 Schoolbook 算法,使用 64-bit 操作:

```cpp
EVMMirBuilder::Operand EVMMirBuilder::handleMul(Operand a, Operand b) {
    U256Inst a_comp = extractU256Operand(a);
    U256Inst b_comp = extractU256Operand(b);
    U256Inst result = {};  // 初始化为 0

    MType* i64Type = &Ctx.I64Type;
    MInstruction* zero = createIntConstInstruction(i64Type, 0);

    // Schoolbook 双层循环
    for (int j = 0; j < 4; j++) {
        MInstruction* carry = zero;

        for (int i = 0; i < 4; i++) {
            if (i + j >= 4) {
                // 超出 256-bit 范围,不需要计算 (EVM 截断)
                break;
            }

            // 64x64->128 乘法
            auto mul_result = create64x64Mul(a_comp[i], b_comp[j]);
            MInstruction* lo = mul_result.lo;
            MInstruction* hi = mul_result.hi;

            // result[i+j] = result[i+j] + lo + carry
            auto add1 = createAddWithCarry(result[i+j], lo);
            auto add2 = createAddWithCarry(add1.value, carry);

            result[i+j] = add2.value;

            // 新进位 = add2.carry + hi
            carry = createAdd(add2.carry, hi);
        }
    }

    return Operand(result, EVMType::UINT256);
}
```

**关键辅助函数**:

```cpp
struct MulResult {
    MInstruction* lo;  // 低 64 位
    MInstruction* hi;  // 高 64 位
};

MulResult EVMMirBuilder::create64x64Mul(MInstruction* x, MInstruction* y) {
    // 方法 1: 如果 LLVM 支持 i128 类型
    MInstruction* result_i128 = createMul(x, y, /*result_type=*/i128);
    MInstruction* lo = createTruncate(result_i128, i64);
    MInstruction* hi = createTruncate(createLShr(result_i128, 64), i64);
    return {lo, hi};

    // 方法 2: 使用 LLVM intrinsic (备选)
    // llvm.umul.with.overflow.i64(x, y)
}
```

### 4.2 LLVM 优化能力

**LLVM 15+ 对多精度乘法的优化**:
- 自动识别 64x64->128 模式
- x86-64: 生成 `MUL` 或 `MULX` 指令
- ARM64: 生成 `MUL` + `UMULH` 指令对
- 自动使用 `ADCX`/`ADOX` 处理进位链 (如果 CPU 支持)

**编译器标志**:
- `-march=haswell`: 启用 BMI2 (MULX)
- `-march=broadwell`: 启用 BMI2 + ADX
- LLVM 会根据 target CPU 自动选择指令

### 4.3 方案 2: 使用 LLVM Intrinsics (可选)

如果需要更精确的控制:

```cpp
// LLVM intrinsic 示例
@llvm.umul.with.overflow.i64(i64 %a, i64 %b) -> {i64, i1}
@llvm.x86.addcarry.64(i8 %carry_in, i64 %a, i64 %b) -> {i8, i64}
```

**优势**: 更精确的代码生成
**劣势**: 失去可移植性 (ARM64 需要不同 intrinsics)

## 5. EVM 规范要求

### 5.1 截断行为

EVM 的 MUL 指令要求:
```
MUL(x, y) = (x * y) mod 2^256
```

在 IR 实现中:
- 512-bit 中间结果只保留低 256-bit
- 循环可以提前终止: `if (i + j >= 4) break;`

### 5.2 零值处理

```
MUL(x, 0) = 0
MUL(0, y) = 0
```

可选优化: 在 IR 中添加零值快速路径

## 6. 实现检查清单

- [ ] 实现 Schoolbook 双层循环逻辑
- [ ] 实现 64x64->128 乘法辅助函数
- [ ] 实现带进位的加法链
- [ ] 正确处理 256-bit 截断
- [ ] 确保 LLVM 生成高效的机器码
- [ ] 通过 EVM 状态测试验证正确性
- [ ] 使用 `perf` 验证指令使用 (MULX/ADCX)

## 7. 参考资料

- intx 源码: `intx.hpp:1524-1542` (umul 实现)
- Intel 指令手册: BMI2, ADX 扩展
- LLVM 文档: Multi-precision arithmetic optimization
- EVM 黄皮书: 算术运算语义
