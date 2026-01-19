# U256 除法与模运算算法分析与实现方案

## 1. intx 库的实现

### 1.1 算法选择: 改进的 Knuth 除法算法

intx 对 U256 除法使用 **Reciprocal-based Division with Normalization**,基于 Knuth 《计算机程序设计艺术》第 2 卷的算法 D,并使用倒数优化。

### 1.2 核心策略

除法算法根据除数大小选择不同策略:

```cpp
template <unsigned M, unsigned N>
constexpr div_result<uint<M>, uint<N>> udivrem(const uint<M>& u, const uint<N>& v)
{
    // 1. 归一化 (Normalization)
    auto na = internal::normalize(u, v);

    // 2. 早期退出: 被除数 < 除数
    if (na.num_numerator_words <= na.num_divisor_words)
        return {0, static_cast<uint<N>>(u)};

    // 3. 单字除数优化
    if (na.num_divisor_words == 1) {
        const auto r = internal::udivrem_by1(...);
        return {quotient, r >> na.shift};
    }

    // 4. 双字除数优化
    if (na.num_divisor_words == 2) {
        const auto r = internal::udivrem_by2(...);
        return {quotient, r >> na.shift};
    }

    // 5. 多字除法 (Knuth Algorithm D)
    internal::udivrem_knuth(...);
    return {quotient, remainder};
}
```

## 2. 关键技术: 倒数 (Reciprocal)

### 2.1 倒数的作用

传统除法需要试商,使用倒数可以:
- 将除法转换为乘法: `a / b ≈ a * reciprocal(b) / 2^k`
- 减少迭代次数
- 提高硬件效率

### 2.2 倒数计算

**2-by-1 倒数** (`reciprocal_2by1`, 行 690-709):
```cpp
inline uint64_t reciprocal_2by1(uint64_t d) noexcept
{
    // d 必须是归一化的 (最高位为 1)
    INTX_REQUIRE(d >= 0x8000000000000000);

    // 使用查找表初始化 (9-bit 索引)
    const uint64_t d9 = d >> 55;
    const uint32_t v0 = internal::reciprocal_table[d9 - 256];

    // 牛顿迭代精炼
    const uint64_t d40 = d >> 24;
    const uint64_t v1 = (v0 << 11) - (v0 * v0 * d40 >> 40) - 1;
    const uint64_t v2 = (v1 << 13) + (v1 * (0x1000000000000000 - v1 * d40) >> 47);

    // 误差修正
    const auto e = ((builtin_uint128{v2} * d) >> 64) + d;
    uint64_t v3 = v2 - (e <= builtin_uint128{v2});
    return v3;
}
```

**算法**:
1. 查找表提供初始近似值 (精度 ~16 bit)
2. 两轮牛顿迭代提升精度至 64 bit
3. 最终误差修正

**3-by-2 倒数** (`reciprocal_3by2`, 行 711-740):
```cpp
inline uint64_t reciprocal_3by2(uint128 d) noexcept
{
    // 计算 d 高 64 位的倒数
    auto v = reciprocal_2by1(d[1]);

    // 两轮修正以适应 128-bit 除数
    auto p = d[1] * v + d[0];
    if (p < d[0]) {
        --v;
        if (p >= d[1]) { --v; p -= d[1]; }
        p -= d[1];
    }

    auto t = umul(v, d[0]);
    p += t[1];
    if (p < t[1]) {
        --v;
        if (p >= d[1]) {
            if (p > d[1] || t[0] >= d[0]) --v;
        }
    }
    return v;
}
```

## 3. 归一化 (Normalization)

### 3.1 目的

将除数的最高位移到最高 bit:
```
原始: d = 0x0123456789ABCDEF
归一化: d' = d << shift (使得 d' 的最高位为 1)
```

### 3.2 实现 (`normalize`, 行 1618-1662)

```cpp
template <unsigned M, unsigned N>
inline normalized_div_args<M, N> normalize(
    const uint<M>& numerator, const uint<N>& denominator)
{
    // 1. 计算前导零 (leading zeros)
    shift = clz(denominator[highest_word]);

    // 2. 左移除数
    if (shift) {
        for (int i = n-1; i > 0; --i)
            vn[i] = (v[i] << shift) | (v[i-1] >> (64 - shift));
        vn[0] = v[0] << shift;
    }

    // 3. 左移被除数 (添加额外的最高字)
    if (shift) {
        un[m] = u[m-1] >> (64 - shift);
        for (int i = m-1; i > 0; --i)
            un[i] = (u[i] << shift) | (u[i-1] >> (64 - shift));
        un[0] = u[0] << shift;
    }

    return {divisor_normalized, numerator_normalized, shift};
}
```

**关键**: 归一化后,除数最高位为 1,倒数计算更准确

## 4. 单字除法优化 (`udivrem_by1`)

对于除数为单个 64-bit 字的情况 (行 1670-1686):

```cpp
inline uint64_t udivrem_by1(uint64_t u[], int len, uint64_t d)
{
    const auto reciprocal = reciprocal_2by1(d);

    auto rem = u[len - 1];  // 最高字作为初始余数
    u[len - 1] = 0;

    // 从高到低逐字处理
    auto it = &u[len - 2];
    do {
        std::tie(*it, rem) = udivrem_2by1({*it, rem}, d, reciprocal);
    } while (it-- != &u[0]);

    return rem;
}
```

**128-by-64 除法** (`udivrem_2by1`, 行 742-764):
```cpp
inline div_result<uint64_t> udivrem_2by1(uint128 u, uint64_t d, uint64_t v)
{
    // 使用倒数估算商
    auto q = umul(v, u[1]);
    q = fast_add(q, u);
    ++q[1];

    // 计算余数
    auto r = u[0] - q[1] * d;

    // 商的修正
    if (r > q[0]) { --q[1]; r += d; }
    if (r >= d) { ++q[1]; r -= d; }

    return {q[1], r};
}
```

## 5. Knuth 算法 D (多字除法)

对于除数 ≥ 3 字的情况 (`udivrem_knuth`, 行 1743-1783):

```cpp
inline void udivrem_knuth(uint64_t q[], uint64_t u[], int ulen,
                          const uint64_t d[], int dlen)
{
    const auto divisor = uint128{d[dlen-2], d[dlen-1]};
    const auto reciprocal = reciprocal_3by2(divisor);

    // 逐个计算商的每一位
    for (int j = ulen - dlen - 1; j >= 0; --j) {
        // 取被除数的 3 个字
        const auto u2 = u[j + dlen];
        const auto u1 = u[j + dlen - 1];
        const auto u0 = u[j + dlen - 2];

        uint64_t qhat;
        if ((uint128{u1, u2}) == divisor) {
            // 除法溢出情况
            qhat = ~uint64_t{0};
            u[j + dlen] = u2 - submul(&u[j], &u[j], d, dlen, qhat);
        } else {
            // 使用倒数计算试商
            uint128 rhat;
            std::tie(qhat, rhat) = udivrem_3by2(u2, u1, u0, divisor, reciprocal);

            // 从被除数减去 qhat * divisor
            bool carry;
            const auto overflow = submul(&u[j], &u[j], d, dlen - 2, qhat);
            std::tie(u[j + dlen - 2], carry) = subc(rhat[0], overflow);
            std::tie(u[j + dlen - 1], carry) = subc(rhat[1], carry);

            // 商修正
            if (carry) {
                --qhat;
                u[j + dlen - 1] += divisor[1] + add(&u[j], &u[j], d, dlen - 1);
            }
        }

        q[j] = qhat;
    }
}
```

**Knuth 算法 D 步骤**:
1. **D1**: 归一化除数和被除数
2. **D2**: 外层循环,计算商的每一位
3. **D3**: 使用倒数估算试商 `qhat`
4. **D4**: 计算 `numerator - qhat * divisor`
5. **D5**: 如果结果为负,修正 `qhat`
6. **D6**: 存储商的当前位
7. **D8**: 反归一化余数

## 6. 有符号除法 (SDIV/SMOD)

```cpp
template <unsigned N>
inline constexpr div_result<uint<N>> sdivrem(const uint<N>& u, const uint<N>& v)
{
    const auto sign_mask = uint<N>{1} << (sizeof(u) * 8 - 1);

    // 检查符号
    auto u_is_neg = (u & sign_mask) != 0;
    auto v_is_neg = (v & sign_mask) != 0;

    // 转换为绝对值
    auto u_abs = u_is_neg ? -u : u;
    auto v_abs = v_is_neg ? -v : v;

    // 商的符号 = 符号不同
    auto q_is_neg = u_is_neg ^ v_is_neg;

    // 执行无符号除法
    auto res = udivrem(u_abs, v_abs);

    // 应用符号
    return {
        q_is_neg ? -res.quot : res.quot,   // 商
        u_is_neg ? -res.rem : res.rem      // 余数保持被除数符号
    };
}
```

**关键规则**:
- 商的符号 = XOR(被除数符号, 除数符号)
- 余数的符号 = 被除数的符号

## 7. 算法复杂度

| 操作 | 复杂度 | 说明 |
|-----|--------|-----|
| 归一化 | O(n) | 位移操作 |
| 倒数计算 | O(1) | 查表 + 常数次迭代 |
| 单字除法 | O(n) | n 次 128/64 除法 |
| Knuth 算法 | O(n²) | 类似长除法 |

对于 256-bit:
- 单字除数: ~4 次迭代
- 双字除数: ~2 次迭代
- 多字除数: O(16) 操作

## 8. LLVM IR 实现方案

### 8.1 方案 1: 分情况优化 (推荐)

```cpp
EVMMirBuilder::Operand EVMMirBuilder::handleDiv(Operand dividend, Operand divisor) {
    U256Inst a = extractU256Operand(dividend);
    U256Inst b = extractU256Operand(divisor);

    // 1. 零除法检查
    MInstruction* is_zero = isU256Zero(b);
    if (is_zero) {
        return createU256Constant(0);  // EVM: DIV(x, 0) = 0
    }

    // 2. 检查除数大小
    int divisor_words = countSignificantWords(b);

    if (divisor_words == 1) {
        // 单字除法优化
        return implement_divrem_by1(a, b[0]);
    } else if (divisor_words == 2) {
        // 双字除法优化
        return implement_divrem_by2(a, {b[0], b[1]});
    } else {
        // 多字除法 (Knuth)
        return implement_divrem_knuth(a, b);
    }
}
```

### 8.2 归一化实现

```cpp
struct NormalizedArgs {
    U256Inst numerator;
    U256Inst divisor;
    MInstruction* shift;
};

NormalizedArgs EVMMirBuilder::normalize(U256Inst num, U256Inst den) {
    // 1. 计算除数的前导零
    MInstruction* shift = countLeadingZeros(den);

    // 2. 左移除数
    U256Inst den_norm = shiftLeft256(den, shift);

    // 3. 左移被除数 (可能需要扩展到 320-bit)
    U256Inst num_norm = shiftLeft256(num, shift);

    return {num_norm, den_norm, shift};
}
```

### 8.3 倒数计算

倒数计算涉及查找表和牛顿迭代,实现较复杂。有两种选择:

**选项 A: 保留 runtime 函数**
```cpp
// 调用预先计算的倒数函数
MInstruction* reciprocal = callRuntimeFunction(
    &computeReciprocal,
    normalized_divisor
);
```

**选项 B: 在 IR 中实现牛顿迭代**
```cpp
MInstruction* reciprocal = createInitialReciprocal(divisor);  // 查表
for (int i = 0; i < 2; i++) {
    // 牛顿迭代: v = v * (2 - d*v)
    reciprocal = newtonIteration(reciprocal, divisor);
}
```

### 8.4 单字除法实现

```cpp
Operand EVMMirBuilder::implement_divrem_by1(U256Inst num, MInstruction* den) {
    // 归一化
    auto na = normalize(num, {den, 0, 0, 0});
    MInstruction* den_norm = na.divisor[0];

    // 计算倒数
    MInstruction* reciprocal = compute_reciprocal_2by1(den_norm);

    U256Inst quotient = {};
    MInstruction* remainder = na.numerator[3];  // 最高字

    // 从高到低处理每个字
    for (int i = 2; i >= 0; i--) {
        // 128-bit / 64-bit
        auto result = divrem_2by1(
            {na.numerator[i], remainder},
            den_norm,
            reciprocal
        );
        quotient[i] = result.quot;
        remainder = result.rem;
    }

    // 反归一化余数
    remainder = createLShr(remainder, na.shift);

    return Operand(quotient, EVMType::UINT256);
}
```

### 8.5 LLVM 优化依赖

- **除法指令**: x86-64 `DIV`/`IDIV` (但 64/64 不够,需要 128/64)
- **倒数估算**: 无直接 intrinsic,需手动实现
- **分支优化**: LLVM 会优化 `if (divisor_words == 1)` 等分支

## 9. EVM 规范要求

### 9.1 零除法

```
DIV(x, 0) = 0
SDIV(x, 0) = 0
MOD(x, 0) = 0
SMOD(x, 0) = 0
```

必须在算法开始时检查。

### 9.2 有符号除法边界情况

```
SDIV(-2^255, -1) 应该返回 -2^255  // 溢出情况
SMOD(-2^255, -1) = 0
```

### 9.3 模运算

```
MOD(x, y) = DIV(x, y) 的余数
SMOD(x, y) = SDIV(x, y) 的余数 (保持被除数符号)
```

实现除法时同时计算商和余数,避免重复计算。

## 10. 实现复杂度评估

### 10.1 代码量估计

| 组件 | 行数 (估算) |
|-----|-----------|
| 归一化 | ~50 |
| 倒数计算 (查表+迭代) | ~80 |
| 单字除法 | ~60 |
| 双字除法 | ~80 |
| Knuth 算法 | ~150 |
| 辅助函数 | ~100 |
| **总计** | **~520 行** |

### 10.2 实现优先级建议

**阶段 1: 基础实现**
1. 零除法检查
2. 简单情况: 除数为 1
3. 单字除法 (覆盖大部分实际场景)

**阶段 2: 完整实现**
4. 双字除法
5. Knuth 多字除法
6. 有符号除法包装

**阶段 3: 优化**
7. 特殊情况快速路径 (除数为 2^n)
8. 倒数查表预计算

## 11. 实现检查清单

- [ ] 实现 clz (count leading zeros)
- [ ] 实现归一化/反归一化
- [ ] 实现倒数计算 (查表 + 牛顿迭代)
- [ ] 实现 128/64 除法 (udivrem_2by1)
- [ ] 实现单字除法 (udivrem_by1)
- [ ] 实现双字除法 (udivrem_by2)
- [ ] 实现 Knuth 算法 (udivrem_knuth)
- [ ] 实现有符号包装 (sdivrem)
- [ ] 处理零除法边界情况
- [ ] 处理有符号溢出情况
- [ ] 通过 EVM 状态测试

## 12. 参考资料

- Knuth, TAOCP Vol 2, Section 4.3.1 (Algorithm D)
- intx 源码: `intx.hpp:1788-1839` (udivrem 实现)
- intx 源码: `intx.hpp:690-740` (倒数计算)
- "Modern Computer Arithmetic" by Brent & Zimmermann
- EVM 黄皮书: 除法和模运算语义
