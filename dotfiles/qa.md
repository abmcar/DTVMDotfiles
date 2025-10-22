DTVM-EVMJIT 质量保证方案 v1.0

# 一、测试策略矩阵

| 测试维度       | 方法                  | 覆盖率目标 | 验证工具          | 实施优先级 |
|----------------|-----------------------|------------|------------------|------------|
| 语义一致性     | 参考实现对比测试      | 100%操作码 | evmone            | P0         |
| 异常处理       | 场景测试+边界测试     | 100%异常路径| 自定义测试集    | P0         |
| Gas计量        | 差分测试              | 分精度验证 | Geth基准套件     | P0         |
| 安全漏洞       | 模糊测试+符号执行     | 边界全覆盖 | Echidna+Manticore| P0         |
| Shanghai兼容性 | 功能测试              | 100%EIP覆盖| 官方测试集       | P0         |
| 性能测试       | 压力测试              | 回归检测   | 自定义基准       | P1         |

# 二、分层测试方案

## 2.1 单元测试规范

### 优先级策略（按使用频率+基础依赖）
1. **P0 - 核心指令**：STOP, PUSH系列, POP, DUP系列, SWAP系列, ADD, SUB, MUL, DIV, MOD, JUMP, JUMPI, JUMPDEST
2. **P0 - 存储操作**：MLOAD, MSTORE, MSTORE8, SLOAD, SSTORE
3. **P0 - 环境指令**：ADDRESS, BALANCE, ORIGIN, CALLER, CALLVALUE, CALLDATALOAD, CALLDATASIZE, CALLDATACOPY, CODESIZE, CODECOPY, GASPRICE, EXTCODESIZE, EXTCODECOPY, RETURNDATASIZE, RETURNDATACOPY
4. **P0 - 调用指令**：CREATE, CALL, CALLCODE, RETURN, DELEGATECALL, CREATE2, STATICCALL, REVERT, INVALID, SELFDESTRUCT
5. **P1 - 算术运算**：SDIV, SMOD, ADDMOD, MULMOD, EXP, SIGNEXTEND
6. **P1 - 逻辑运算**：LT, GT, SLT, SGT, EQ, ISZERO, AND, OR, XOR, NOT, BYTE, SHL, SHR, SAR, KECCAK256
7. **P1 - 区块信息**：BLOCKHASH, COINBASE, TIMESTAMP, NUMBER, PREVRANDAO, GASLIMIT, CHAINID, SELFBALANCE, BASEFEE, BLOBHASH, BLOBBASEFEE
8. **P2 - 日志操作**：LOG0, LOG1, LOG2, LOG3, LOG4
9. **P2 - 临时存储**：TLOAD, TSTORE, MCOPY


## 2.2 集成测试流程

### Shanghai兼容性测试
**EIP覆盖清单**：
- EIP-3855: PUSH0指令
- EIP-3860: initcode大小限制
- EIP-3651: 降低COINBASE地址访问成本

**EIP-3860测试用例**：
```solidity
contract InitCodeLimitTest {
    function testMaxInitCode() external {
        bytes memory maxCode = new bytes(49152); // 最大允许
        bytes memory oversizedCode = new bytes(49153); // 超限1字节

        // 验证正常创建
        assert(vm.create(maxCode) == SUCCESS);

        // 验证超限拒绝
        assert(vm.create(oversizedCode) == INITCODE_TOO_LARGE);
    }
}
```

## 2.3 安全测试专项

### 模糊测试策略
1. **字节码级模糊**：随机生成有效/无效操作码序列
2. **输入数据模糊**：随机生成合约调用时的输入参数(calldata)和合约存储状态(storage)
3. **边界值测试**：
   - **栈边界**：栈空、栈满(1024)、栈下溢、栈上溢
   - **内存边界**：内存分配0字节、内存扩容边界、内存访问越界
   - **Gas边界**：Gas不足、Gas溢出、Gas精确消耗验证
   - **存储边界**：存储槽0值、存储槽非0值、存储清除退款
   - **调用边界**：调用深度1024、调用参数边界、返回值边界
   - **代码边界**：空代码、最大代码大小、无效跳转目标
   - **数据边界**：calldata空数据、calldata最大长度、returndata边界
   - **u256数据类型边界**：由于系统采用4个u64表达u256，需充分测试涉及u256操作的指令，包括：
     * 基本算术运算：ADD, SUB, MUL, DIV, MOD, SDIV, SMOD, ADDMOD, MULMOD, EXP
     * 位运算和逻辑运算：AND, OR, XOR, NOT, SHL, SHR, SAR
     * 比较运算：LT, GT, SLT, SGT, EQ, ISZERO
     * 其他操作：SIGNEXTEND, BYTE
     * 对于多操作数指令（如ADDMOD需要3个操作数，MULMOD需要3个操作数），需要对每个操作数分别进行以下测试：
         * 单操作数边界测试：每个操作数独立处于0-3个u64可表达范围内或超过u256表达范围
         * 组合边界测试：多个操作数同时处于边界值的情况，验证复杂场景下的正确性
   - **算术边界**：
     * 除零操作（DIV, SDIV, MOD, SMOD）：验证返回0而非异常
     * 算术溢出/下溢：验证按模运算截断，不产生异常

### 攻击向量测试
- 调用深度限制测试（防止重入攻击）：测试调用深度达到1024时的行为
- 内存溢出测试：测试内存访问超大偏移量时的行为
- 栈溢出测试：测试栈深度达到1024边界时的行为
- 栈超限测试：测试栈深度超过1024时的行为
- 栈下溢测试：测试空栈执行POP操作时的行为

## 2.4 异常处理测试

### 异常处理测试策略
异常处理测试旨在验证DTVM-EVMJIT在遇到各种异常情况时能够正确处理并返回适当的错误状态，确保虚拟机的稳定性和安全性。

### 异常场景分类

#### 1. 操作码异常（优先级：P0）
- 无效操作码执行：执行0x00-0xFF之间未定义的操作码
- JUMP/JUMPI跳转到无效目标（非JUMPDEST指令位置）
- 预编译合约调用异常（通过CALL系列操作码调用预编译合约时发生的异常）

#### 2. 内存访问异常（优先级：P0）
- 内存越界访问（涉及指令：MLOAD, MSTORE, MSTORE8, CALLDATACOPY, CODECOPY, EXTCODECOPY, RETURNDATACOPY）
- 内存分配失败（涉及指令：MLOAD, MSTORE, MSTORE8, CALLDATACOPY, CODECOPY, EXTCODECOPY, RETURNDATACOPY）
- 内存复制异常（涉及指令：CALLDATACOPY, CODECOPY, EXTCODECOPY, RETURNDATACOPY, MCOPY）

#### 3. Gas相关异常（优先级：P0）
- Gas不足（涉及指令：所有消耗Gas的指令，特别是CALL系列、CREATE系列、SSTORE、MSTORE/MSTORE8等高Gas消耗指令）
- Gas溢出（涉及指令：所有消耗Gas的指令，特别是EXP、KECCAK256等Gas计算可能溢出的指令）
- Gas退款异常（涉及指令：SSTORE、SELFDESTRUCT）

#### 4. 合约调用异常（优先级：P0）
- 调用深度超限（涉及指令：CALL, CALLCODE, DELEGATECALL, STATICCALL）
- 合约创建失败（涉及指令：CREATE, CREATE2）
- 返回数据异常（涉及指令：RETURN, REVERT, RETURNDATACOPY, RETURNDATASIZE）

#### 5. 存储异常（优先级：P1）
- 存储访问异常（涉及指令：SLOAD, SSTORE, TLOAD, TSTORE）
- 存储Gas计算异常（涉及指令：SLOAD, SSTORE）

#### 6. 区块链状态异常（优先级：P1）
- 区块信息访问异常（涉及指令：BLOCKHASH, COINBASE, TIMESTAMP, NUMBER, PREVRANDAO, GASLIMIT, CHAINID, BASEFEE, BLOBHASH, BLOBBASEFEE）
- 账户状态异常（涉及指令：BALANCE, EXTCODESIZE, EXTCODECOPY, EXTCODEHASH, SELFBALANCE）

# 三、自动化实施

## 3.1 CI/CD管道规划
- **测试触发机制**：代码提交、PR合并、定时执行
- **测试分层**：单元测试 → 集成测试 → 兼容性测试 → 安全测试
- **结果通知**：测试失败自动通知、质量报告生成
- **环境管理**：测试环境隔离、依赖版本控制

## 3.2 可用外部EVM测试集

### 合约文件测试集
对于包含Solidity合约文件的测试集，可以通过以下方式使用：
- 使用solc编译器将Solidity合约文件编译成EVM字节码
- 将编译后的字节码作为DTVM_EVMJIT的输入执行
- 对比执行结果与evmone等参考实现工具的执行结果差异，验证正确性

**推荐的合约文件测试集**：
1. **OpenZeppelin测试集**
   - GitHub: https://github.com/OpenZeppelin/openzeppelin-contracts
   - 特点：包含大量经过审计的安全合约，涵盖ERC20、ERC721等标准实现

2. **Solidity官方测试集**
   - GitHub: https://github.com/ethereum/solidity
   - 特点：包含各种语法和功能测试的合约文件

3. **Compound协议合约**
   - GitHub: https://github.com/compound-finance/compound-protocol
   - 特点：DeFi项目中的复杂合约，包含复杂的数学运算和状态管理

4. **Uniswap合约**
   - GitHub: https://github.com/Uniswap
   - 特点：AMM DEX的核心合约，包含复杂数学计算和资金管理逻辑


## 3.3 测试数据管理

### 测试用例优先级
1. **P0测试集**：高频指令 + Shanghai EIP
2. **P1测试集**：中频指令 + 边界条件
3. **P2测试集**：低频指令 + 历史兼容性

# 四、质量度量体系

## 4.1 技术指标

| 指标类别 | 目标值 | 监控频率 | 说明 |
|----------|--------|----------|------|
| 指令准确率 | 100% | 每次提交 | 与参考实现执行结果一致性 |
| Gas准确率 | 100% | 每次提交 | 与参考实现的Gas消耗差异 |
| 内存安全 | 无泄漏 | 每次提交 | 内存使用正确性 |
| 边界处理 | 100%覆盖 | 每次提交 | 所有边界条件正确处理 |

## 4.2 关键里程碑
- 高频指令测试完成
- 149个指令完整覆盖
- Shanghai兼容性验证
- 性能基准建立# Updated from DTVMDotfiles
