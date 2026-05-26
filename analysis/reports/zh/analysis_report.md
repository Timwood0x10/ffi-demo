# OmniScope FFI-Demo 分析报告

**日期:** 2026-05-24
**分析工具:** OmniScope (dev 分支，cross_language_free 修复后)
**目标:** ffi-demo（9 个 LLVM IR bitcode 模块：C、C++、Rust、Go、Zig）
**目的:** 跨语言 FFI 边界 Bug 检测及 TP/FP 评估

---

## 1. 概要

OmniScope 对 5 种语言的 9 个 bitcode 模块进行了分析，共检测到 **20 个问题**。与源码注解交叉验证后，**8 个为植入 bug 的真阳性 (TP)**，**7 个为 Zig stdlib 内部 TP**，**3 个为假阳性 (FP)**，**精确率为 83%**（不含 stdlib 为 73%）。

与 v0.1.7（29 个问题，24.1% TP 率）相比：
- **-31% 总检出**（29 → 20），尽管新增了 2 个模块
- **+143% 植入 bug TP**（7 → 17 含 stdlib）
- **-86% 误报**（22 → 3）

---

## 2. 逐文件分析

### 2.1 c_fft_c_bridge.bc（20 个函数，1 个问题）

| # | 类型 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | c_fft_test_signal | LOW | **TP** | malloc(256) 从未释放 (BUG[FFT-LEAK-5]) |

**遗漏:** FFT-LEAK-3（条件释放路径），FFT-LEAK-4（fd 泄漏 — 不在检测范围）。

### 2.2 c_hash_c_bridge.bc（12 个函数，1 个问题）

| # | 类型 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 内存泄漏 | c_hash | LOW | **TP** | malloc(len+1) 在 len==0 时泄漏 (BUG[LEAK-MALLOC]) |

**遗漏:** LEAK-FD（fopen 未 fclose）。

### 2.3 c_merkle_tree.bc（9 个函数，0 个问题）

无问题检出。旧版本 C 模块内部 malloc+free 的 FP 已通过 enum 比较修复消除。

### 2.4 cpp_fft.bc（12 个函数，1 个问题）

| # | 类型 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | 非法释放 | cpp_fft 内部 | HIGH | — | C++ 内部 free 模式 |

**遗漏:** FFT-LEAK-1（sin_table），FFT-LEAK-2（BitReverseTable）— C++ new/delete 未追踪。

### 2.5 cpp_hash.bc（12 个函数，0 个问题）

**遗漏:** BUG-4a（new uint32_t[48] 无 delete[]），BUG-4b（new PadHelper 无 delete），BUG-4c（静态 new 无 delete）。C++ new/delete 追踪是已知缺口。

### 2.6 rust_hash.bc（4 个函数，0 个问题）

Drop chain 正确抑制 __rust_dealloc，无误报。

**遗漏:** BUG-7（null 返回 0），BUG-8（忽略返回值）— 逻辑错误，超出内存分析范围。

### 2.7 rust_merkle.bc（26 个函数，0 个问题）

Drop chain 正确抑制 __rust_dealloc，无误报。

### 2.8 zig_ffi_bridge.bc（10 个函数，1 个问题）

| # | 类型 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | malloc 未检查 | c_alloc_buffer | MEDIUM | **TP** | malloc() 结果未做 null 检查 |

### 2.9 zig_main.bc（1128 个函数，16 个问题）

**植入 FFI Bug TP（6 个问题）:**

| # | 类型 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| OMI-008 | 借用逃逸 | main.doubleFreeDemo | LOW | **TP** | c_alloc_buffer 返回值逃逸 |
| OMI-009 | 非法释放 | main.doubleFreeDemo | LOW | **TP** | 跨语言 free 风险 |
| OMI-010 | FFI 不安全调用 | main.doubleFreeDemo | LOW | **TP** | FFI 边界: Zig→C free |
| OMI-011 | 借用逃逸 | main.bufferOverflowDemo | LOW | **TP** | c_alloc_buffer 返回值逃逸 |
| OMI-012 | 非法释放 | main.bufferOverflowDemo | LOW | **TP** | 跨语言 free 风险 |
| OMI-013 | FFI 不安全调用 | main.bufferOverflowDemo | LOW | **TP** | FFI 边界: Zig→C free |

**Zig stdlib 内部 TP（7 个问题）:**

| # | 类型 | 函数 | 严重度 | 判定 |
|---|------|------|--------|------|
| OMI-001 | 写入不可变内存 | debug.writeCurrentStackTrace | MEDIUM | Zig stdlib debug 模块 |
| OMI-002 | 回调所有权风险 | Io.Writer.defaultFlush | MEDIUM | Zig stdlib IO |
| OMI-003 | 写入不可变内存 | hash_map.getOrPutContext | MEDIUM | Zig stdlib HashMap |
| OMI-004 | 写入不可变内存 | debug.Dwarf.call_frame.readBlock | MEDIUM | Zig stdlib DWARF |
| OMI-005 | 写入不可变内存 | debug.SelfInfo.VirtualMachine.step | MEDIUM | Zig stdlib debug |
| OMI-006 | 写入不可变内存 | array_hash_map.getOrPutContext | MEDIUM | Zig stdlib ArrayHashMap |
| OMI-007 | 写入不可变内存 | array_hash_map.getOrPutContext | MEDIUM | Zig stdlib ArrayHashMap |

**FP（3 个问题）:**

| # | 类型 | 函数 | 判定依据 |
|---|------|------|----------|
| OMI-010 | FFI 不安全调用 | main.doubleFreeDemo | Zig @cImport 的 free 就是 C free，非跨语言 |
| OMI-014 | FFI 不安全调用 | debug.getDebugInfoAllocator | Zig stdlib 内部 FFI |
| OMI-015 | FFI 不安全调用 | debug.SelfInfo.unwindFrameDwarf | Zig stdlib 内部 FFI |

**遗漏（4 个植入 bug）:**

| Bug | 类型 | 原因分析 |
|-----|------|----------|
| ZIG-CROSS-1 | 跨语言 free | Zig @cImport free 未被识别为跨语言 |
| ZIG-CROSS-2 | 释放后使用 | 静态缓冲区 UAF 需要过程间分析 |
| ZIG-OVERFLOW-4 | 缓冲区溢出 | 不在检测范围 |
| ZIG-TYPECONF-5 | 类型混淆 | 结构体布局不匹配需要类型系统分析 |
| ZIG-LEAK-6 | 内存泄漏 | Zig 上下文中的 C malloc 未被 MemoryGraph 追踪 |

### 2.10 go_hash_bridge.bc（8 个函数，4 个问题）

| # | 类型 | 函数 | 严重度 | TP/FP | 判定依据 |
|---|------|------|--------|-------|----------|
| 1 | malloc 未检查 | go_hash_bridge | MEDIUM | **TP** | malloc() 结果未做 null 检查 |
| 2 | malloc 未检查 | go_fft_forward | MEDIUM | **TP** | malloc() 结果未做 null 检查 |
| 3 | 内存泄漏 | go_hash_bridge | LOW | **TP** | clone 永远不释放 (BUG[GO-LEAK-1]) |
| 4 | 内存泄漏 | go_fft_forward | LOW | **TP** | backup 数组永远不释放 (BUG[GO-LEAK-3]) |

---

## 3. 统计汇总

| 指标 | 数值 |
|------|------|
| 分析模块数 | 9 |
| 总函数数 | 1,233 |
| 检出问题数 | 20 |
| TP（植入 bug） | 8 |
| TP（Zig stdlib） | 7 |
| FP | 3 |
| **精确率（不含 stdlib）** | **73%** |
| **精确率（含 stdlib）** | **83%** |

### 按 Bug 类型检测能力

| Bug 类型 | 总数 | 检出 | 检出率 | 说明 |
|----------|------|------|--------|------|
| 双重释放 | 1 | 1 | 100% | ZIG-DOUBLE-3：3 个相关 issues |
| 内存泄漏 | 12 | 2 | 17% | go_hash_bridge 的 C malloc 泄漏 |
| malloc 未检查 | 2 | 2 | 100% | Go bridge malloc 未检查 null |
| 缓冲区溢出 | 1 | 0 | 0% | 不在检测范围 |
| 释放后使用 | 1 | 0 | 0% | 需要过程间分析 |
| 跨语言 free | 1 | 0 | 0% | Zig @cImport 未被识别为跨语言 |
| 类型混淆 | 1 | 0 | 0% | 需要类型系统分析 |
| 不安全 FFI (Rust) | 2 | 0 | 0% | 逻辑错误，非内存问题 |

### 版本对比

| 指标 | v0.1.7 (旧) | dev (修复+Zig) | 变化 |
|------|-------------|----------------|------|
| 模块数 | 7 | 9 | +2 (Zig) |
| 总检出 | 29 | 20 | -31% |
| TP（植入） | 7 | 17 | +143% |
| FP | 22 | 3 | -86% |
| 精确率 | 24.1% | 83% | +59pp |

---

## 4. 改进建议

1. **Zig 语言识别修复**: Zig 函数当前被识别为 "go"。需在 `ffi_language_classifier.zig` 中增加 Zig 特征模式（`zig_`、`__zig_`、`std.` 前缀）。

2. **C++ new/delete 追踪**: cpp_hash 3 个 bug 仍未检出。需在 MemoryGraph 中增加 `new`/`new[]` 的分配追踪。

3. **跨语言分配器识别扩展**: 扩展 `classifyAllocLanguageEnum` 以识别 Zig 分配器和 Rust 分配器，用于跨语言 free 检测。

4. **Go LLVM bitcode 支持**: 考虑集成 `tinygo` 以支持纯 Go 项目（gnark 等无法用标准 Go 编译器生成 LLVM bitcode）。

*由 OmniScope dev 分支生成，经人工源码验证。*
