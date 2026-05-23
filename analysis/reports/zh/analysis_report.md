# OmniScope FFI-Demo 分析报告

**日期:** 2026-05-22  
**分析工具:** OmniScope v0.1.7  
**目标:** ffi-demo（7 个 LLVM IR bitcode 模块）  
**目的:** 跨语言 FFI 边界 Bug 检测及 tpFP 评估

---

## 1. 概要

OmniScope 对 C、C++、Rust 三种语言的 7 个 bitcode 模块进行了分析，共检测到 **29 个问题**。与源码注解交叉验证后，**7 个为真阳性 (TP)**，**22 个为假阳性 (FP)**，**tpFP 比率为 1:3.14**（TP 率 = 24.1%）。

---

## 2. 逐文件分析

### 2.1 c_fft_c_bridge.bc

| # | 类别 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | c_fft_test_signal | MEDIUM | **TP** | 对应 BUG[FFT-LEAK-5]: malloc(256) 未释放 |
| 2 | 释放后使用 | c_fft_test_signal | MEDIUM | FP | 源码无 UAF；�| 2 | 释放后使用 | c_fft_test_signal | MEDIUM | FP | 源码无 UAF；�| 2 | 释放后使用 | c_fft_test_signal | MEDIUM | FP | 源码无 UAF；�| 2 | 释放后使用 | c_fft_test_sigrward 是合法 C++ 调用 |
| 6-9 | | 6-9 | | 6-9 | | 6-9 |rward/test_signal | CRITICAL | FP | 合法的 free() 调用；指针追踪混淆 |

**遗漏:** BUG[FFT-LEAK-4]（fopen 未 fclose）—— OmniScope 不追踪文件描述符泄漏。

### 2.2 c_hash_c_bridge.bc

| # | 类别 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | c_hash | MEDIUM | **TP** | 对应 BUG[LEAK-MALLOC]: free() 仅在 len>0 时执行 |
| 2 | 释放后使用 | c_hash | MEDIUM | FP | 源码无 UAF |
| 3 | FFI 不安全调用 | (边界) | — | FP | cpp_hash_Hash 是合法调用 |
| 4 | 非法释放 | c_hash | CRITICAL | FP | free(copy) 合法 |

**遗漏:** BUG[LEAK-FD]（fopen("/dev/urandom") 未 fclose）。

### 2.3 c_merkle_tree.bc

| # | 类别 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | merkle_root | MEDIUM | FP | nodes 在第 103 行正确释放 |
| 2 | 释放后使用 | merkle_root | MEDIUM | FP | 源码无 UAF |
| 3 | 双重释放 | merkle_root | — | FP | 错误路径 free+return 与正常路径 free 互斥 |
| 4 | FFI 不安全调用 | (边界) | — | FP | c_hash 是合法调用 |
| 5 | 非法释放 | merkle_root | HIGH | FP | 合法的 free(nodes) |


 5 | 非法释放 | merkle_root | HIGH | FP | 合法的 ��错误，超出分析范围。

### 2.4 cpp_fft.bc

| # | 类别 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | InitTwiddle | MEDIUM | **TP** | 对应 BUG[FFT-LEAK-1]: sin_table 可能泄漏 |

**遗漏:** BUG[FFT-LEAK-2]（BitReverseTable）—— delete[] rev 掩盖了问题。

### 2.5 cpp_hash.bc

| # | 类别 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | CompressBlock | MEDIUM | **TP** | 对应 BUG[LEAK-2]: ext=new uint32_t[48] 未释放 |
| 2 | 内存泄漏 | Hash | MEDIUM | **TP** | 对应 BUG[LEAK-3]: PadHelper 泄漏；含 BUG[LEAK-1] rotation_cache |
| 3 | FFI 不| 3 | FFI � | (边界) | — | FP | 内部 C++ 调用 |
| 4 | 借用逃逸 | (边界) | — | FP | 源码无借用逃逸 |

### 2.6 rust_hash.bc — 0 个问题

**遗漏:** BUG[7]（空指针返回 0），BUG[8]（忽略返回值）—— 逻辑错误。

### 2.7 rust_merkle.bc

| # | 类别 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | format_digest | MEDIUM | FP | String 由 Rust Drop 自动释放 |
| 2 | 内存泄漏 | MerkleTree::new | MEDIUM | FP | Vec 由 Rust 分配器管理 |
| 3-4 | FFI 不安全调用 | __rust_dealloc | — | FP | Rust 内部分配器 |
| 5-6 | 非法释放 | __rust_dealloc | — | FP | Rust 分配器内部操作 |

**遗漏:** BUG[10]（start 未更新），BUG[13]（大写十六进制）—— 逻辑错误。

---

## 3. 统计汇总

| 指标 | 数值 |
|------|------|
| 检测问题总数 | 29 |
| 真阳性 (TP) | 7 |
| 假阳性 (FP) | 22 |
| **tpFP 比率** | **1:3.14** |
| **TP 率** | **24.1%** |
| 源码已知 Bug | 13 |
| 检测到的 Bug | 5 / 13 |
| 召回率 | 38.5% |

### TP 分类

| 类别 | TP 数量 |
|------|---------|
| 内存泄漏 | 5 |
| 双重释放 | 0 |
| 释放后使用 | 0 |
| 非法释放 | 0 |
| FFI 不安全调用 | 0 |
| 文件描述符泄漏 | 0 |

### FP 根因分析

| 原因 | 数量 | 说明 |
|------|------|------|
| Rust 分配器误分类 | 6 | __rust_dealloc/__rust_alloc 被视为 FFI 边界 |
| 指针别名导致的非法释放 | 5 | FreeValidation 将栈到堆的别名混淆 |
| 所有权追踪导致的 UAF | 3 | PointerOwnership 分配 ID 产生幽灵 UAF |
| 合法 FFI 被标记 | 5 | C→C++ 桥接调用被标记为"FFI 不安全" |
| 托管内存被标记为泄漏 | 3 | 有 Drop 语义的 Rust Vec/String |

---

## 4. 改进建议

1. **Rust 分配器过滤**: 将 `__rust_alloc/__rust_dealloc/__rust_realloc` 加入编译器保留符号
2. **FreeValidation 精度**: 与 MemoryGraph 交叉验证，减少幽灵非法释放
3. **UAF 追踪改进**: 增加所有权转移语义，区分"指针转移到另一作用域"与真实 UAF
4. **FFI 精度**: 仅标记跨分配域调用（malloc+delete, new+free），而非所有跨语言调用

---
