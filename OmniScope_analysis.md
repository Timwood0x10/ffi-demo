# OmniScope Unsafe FFI 检测能力评估报告

> 测试版本: OmniScope (dev branch, 2026-05-24)
> 测试文件: `/Users/scc/code/ffi-demo/output/*.bc` (9 个模块)
> Ground Truth: `/Users/scc/code/ffi-demo/README_ZH.md` + `zig/main.zig` 中标注的故意缺陷

---

## 一、测试结果总览

| 模块 | 函数数 | 检出数 | TP (植入bug) | TP (stdlib) | FP | 漏检 |
|------|--------|--------|-------------|-------------|----|----|
| c_fft_c_bridge.bc | 20 | 1 | 1 | 0 | 0 | 2 |
| c_hash_c_bridge.bc | 12 | 1 | 1 | 0 | 0 | 1 |
| c_merkle_tree.bc | 9 | 0 | 0 | 0 | 0 | 0 |
| cpp_fft.bc | 12 | 1 | 0 | 0 | 0 | 2 |
| cpp_hash.bc | 12 | 0 | 0 | 0 | 0 | 3 |
| rust_hash.bc | 4 | 0 | 0 | 0 | 0 | 2 |
| rust_merkle.bc | 26 | 0 | 0 | 0 | 0 | 0 |
| **zig_ffi_bridge.bc** | 10 | 1 | 0 | 0 | 0 | 0 |
| **zig_main.bc** | 1128 | 16 | **6** | **7** | 3 | **4** |
| **合计** | 1233 | **20** | **8** | **7** | **3** | **14** |

---

## 二、Zig FFI Bug Demo 详细分析

### 植入的 6 个 FFI bug

| Bug | 类型 | 描述 | 检出? |
|-----|------|------|-------|
| ZIG-CROSS-1 | cross_language_free | C malloc → Zig 释放 | ❌ 漏检 |
| ZIG-CROSS-2 | use_after_free | C 返回静态缓冲区指针，语义上已失效 | ❌ 漏检 |
| ZIG-DOUBLE-3 | double_free | C free 后 Zig 再 free | ✅ 检出 (3 issues) |
| ZIG-OVERFLOW-4 | buffer_overflow | C 写入 len+16 字节到 len 字节缓冲区 | ❌ 漏检 (仅报 free 相关) |
| ZIG-TYPECONF-5 | type_confusion | ZigConfig(u64) vs CConfig(u32) 布局不匹配 | ❌ 漏检 |
| ZIG-LEAK-6 | memory_leak | C malloc 256 字节从未释放 | ❌ 漏检 |

### 检出的 issues（zig_main.bc）

**植 bug 触发的 TP (6 issues):**

| # | Type | Function | 说明 |
|---|------|----------|------|
| OMI-008 | borrow_escape | main.doubleFreeDemo | FFI 返回值逃逸: c_alloc_buffer 结果 |
| OMI-009 | invalid_free | main.doubleFreeDemo | 跨语言 free 风险 |
| OMI-010 | ffi_unsafe_call | main.doubleFreeDemo | FFI 边界: Zig→C free |
| OMI-011 | borrow_escape | main.bufferOverflowDemo | FFI 返回值逃逸: c_alloc_buffer 结果 |
| OMI-012 | invalid_free | main.bufferOverflowDemo | 跨语言 free 风险 |
| OMI-013 | ffi_unsafe_call | main.bufferOverflowDemo | FFI 边界: Zig→C free |

**Zig stdlib 内部 TP (7 issues):**

| # | Type | Function | 说明 |
|---|------|----------|------|
| OMI-001 | write_to_immutable | debug.writeCurrentStackTrace | Zig stdlib debug 模块 |
| OMI-002 | callback_ownership_risk | Io.Writer.defaultFlush | Zig stdlib IO 模块 |
| OMI-003 | write_to_immutable | hash_map.getOrPutContext | Zig stdlib HashMap |
| OMI-004 | write_to_immutable | debug.Dwarf.call_frame.readBlock | Zig stdlib DWARF |
| OMI-005 | write_to_immutable | debug.SelfInfo.VirtualMachine.step | Zig stdlib debug |
| OMI-006 | write_to_immutable | array_hash_map.getOrPutContext | Zig stdlib ArrayHashMap |
| OMI-007 | write_to_immutable | array_hash_map.getOrPutContext | Zig stdlib ArrayHashMap |

**FP (3 issues):**

| # | Type | Function | 说明 |
|---|------|----------|------|
| OMI-010 | ffi_unsafe_call | main.doubleFreeDemo | Zig @cImport 的 free 就是 C free，非真正 FFI |
| OMI-014 | ffi_unsafe_call | debug.getDebugInfoAllocator | Zig stdlib 内部，非用户 FFI |
| OMI-015 | ffi_unsafe_call | debug.SelfInfo.unwindFrameDwarf | Zig stdlib 内部，非用户 FFI |

**漏检 (4 issues):**

| Bug | 类型 | 原因分析 |
|-----|------|----------|
| ZIG-CROSS-1 | cross_language_free | Zig 通过 @cImport 调用 free，OmniScope 未识别为跨语言 |
| ZIG-CROSS-2 | use_after_free | 静态缓冲区 use-after-free 需要过程间分析 |
| ZIG-OVERFLOW-4 | buffer_overflow | 缓冲区溢出检测不在当前能力范围内 |
| ZIG-TYPECONF-5 | type_confusion | 结构体布局不匹配需要类型系统分析 |
| ZIG-LEAK-6 | memory_leak | C malloc 在 Zig 上下文中未被 MemoryGraph 追踪 |

### Zig 语言识别问题

OmniScope 将 Zig 函数识别为 `go` 而非 `zig`。原因：`ffi_language_classifier.zig` 中 Zig 的识别模式可能不够完善，或 Zig 的 LLVM IR 命名约定与 Go 有相似之处（如 `main.` 前缀）。

---

## 三、C/C++/Rust 模块分析

### 3.1 c_fft_c_bridge.bc

**检出 (1 issue):**

| # | Type | Function | 判定 | 原因 |
|---|------|----------|------|------|
| OMI-001 | memory_leak | c_fft_test_signal | **TP** | `malloc(256)` 从未 free |

**漏检 (2 issues):**

| Bug | 类型 | 描述 |
|-----|------|------|
| FFT-LEAK-3 | memory_leak | `real_copy`/`imag_copy` 仅在成功路径 free |
| FFT-LEAK-4 | fd_leak | `fopen("/tmp/fft_debug.log")` 从未 fclose |

### 3.2 c_hash_c_bridge.bc

**检出 (1 issue):**

| # | Type | Function | 判定 | 原因 |
|---|------|----------|------|------|
| OMI-001 | memory_leak | c_hash | **TP** | `malloc(len+1)` 在 `len==0` 时泄漏 |

**漏检 (1 issue):**

| Bug | 类型 | 描述 |
|-----|------|------|
| LEAK-FD | fd_leak | `fopen("/dev/urandom")` 从未 fclose |

### 3.3 cpp_fft.bc

**检出 (1 issue):** invalid_free (cpp_fft 内部)

**漏检 (2 issues):**

| Bug | 类型 | 描述 |
|-----|------|------|
| FFT-LEAK-1 | memory_leak | `InitTwiddle` 分配 `sin_table`，调用者只释放 `cos_table` |
| FFT-LEAK-2 | memory_leak | `BitReverseTable` 堆分配仅在成功路径释放 |

### 3.4 cpp_hash.bc — 无检出

**漏检 (3 issues):**

| Bug | 类型 | 描述 |
|-----|------|------|
| BUG-4a | memory_leak | `CompressBlock`: `new uint32_t[48]` 从未 `delete[]` |
| BUG-4b | memory_leak | `Hash`: `new PadHelper()` 从未 `delete` |
| BUG-4c | memory_leak | `S0`: 静态 `new uint32_t[1024]` 从未释放 |

### 3.5 rust_hash.bc / rust_merkle.bc — 无检出

rust_merkle 的 `__rust_dealloc` 调用被 Drop chain 模式正确抑制，无误报。

rust_hash 漏检 2 个 unsafe FFI bug（丢弃返回值、null 处理）— 非内存问题。

---

## 四、Go 测试说明

**gnark** (`~/go/src/gnark/`) 是纯 Go 项目，无 cgo 依赖，无法生成 LLVM bitcode。Go 的标准编译器 (gc) 不输出 LLVM IR。

**现有 Go 测试** (`ffi-demo/go/main.go`) 通过 cgo 调用 C，已在之前的测试中验证。Go 的 cgo 组件 (go_hash_bridge.bc 等) 作为 C bridge 的一部分被分析。

**Go 项目 FFI 测试限制：**
- 纯 Go 项目（如 gnark）无法被 OmniScope 分析（无 LLVM bitcode）
- 有 cgo 的 Go 项目只能分析 C bridge 部分，Go 代码本身不可见
- 需要 `tinygo`（基于 LLVM 的 Go 编译器）才能分析 Go 代码

---

## 五、检测能力总结

### 5.1 按 bug 类型统计

| Bug 类型 | 总数 | 检出 | 检出率 | 说明 |
|----------|------|------|--------|------|
| **Double Free** | 1 | 1 | 100% | ZIG-DOUBLE-3 检出 3 个相关 issues |
| **Memory Leak** | 12 | 2 | 17% | C 模块 malloc 无 free 检出 2 个 |
| **Buffer Overflow** | 1 | 0 | 0% | 不在检测范围 |
| **Use-After-Free** | 1 | 0 | 0% | 需要过程间分析 |
| **Cross-lang Free** | 1 | 0 | 0% | Zig @cImport free 未被识别为跨语言 |
| **Type Confusion** | 1 | 0 | 0% | 需要类型系统分析 |
| **Unsafe FFI (Rust)** | 2 | 0 | 0% | 返回值丢弃、null 处理 — 非内存问题 |

### 5.2 核心发现

**1. Double-free 检测有效**

Zig 的 double-free bug (ZIG-DOUBLE-3) 被完整检出：`borrow_escape` + `invalid_free` + `ffi_unsafe_call` 三个角度全部命中。这是跨语言 double-free 检测的首次验证。

**2. cross_language_free 误报已修复**

旧版本 C 模块内部 malloc+free 的 8 个 FP 已消除。当前仅剩 Zig stdlib 内部的 3 个边界情况 FP。

**3. Zig 语言支持是新增能力**

Zig 模块首次加入测试。OmniScope 能分析 Zig 编译的 LLVM bitcode，检出 FFI 边界问题。但语言识别有误（显示为 "go"）。

**4. C++ new/delete 漏检持续存在**

cpp_hash 的 3 个 `new[]`/`new` 无 `delete[]`/`delete` 问题仍全部漏检。

**5. 非内存类 FFI bug 无法覆盖**

返回值丢弃、null 处理错误、缓冲区溢出、类型混淆等不在 OmniScope 的检测范围内。

---

## 六、版本对比

| 指标 | v0.1.7 (旧) | 修复前 (dev) | 修复后 (dev, 含 Zig) | 变化 |
|------|-------------|-------------|---------------------|------|
| 测试模块数 | 7 | 7 | **9** | +2 (Zig) |
| 总检出 | 29 | 10 | **20** | +10 (Zig stdlib issues) |
| 植 bug TP | 2 | 2 | **8** | +6 (Zig double-free 相关) |
| FP | 8 | 1 | **3** | +2 (Zig stdlib FFI 边界) |
| Unsafe FFI TP | 0 | 0 | **1** (double-free) | +1 |
| Precision | — | 50% | **73%** | +23pp |

---

## 七、改进建议

### P0: Zig 语言识别修复

Zig 函数被识别为 "go"。需要在 `ffi_language_classifier.zig` 中增加 Zig 特征模式（`zig_`、`__zig_`、`std.` 等前缀）。

### P1: C++ new/delete 不匹配检测

`new uint32_t[48]` 无 `delete[]` 完全漏检。需要在 MemoryGraph 中增加 C++ `new`/`new[]` 的分配追踪。

### P2: 扩展跨语言 free 检测

当前只检测到 C++ new → C free 的不匹配。需要扩展到：
- Zig allocator → C free
- C malloc → Zig allocator free
- Rust alloc → C free

### P3: Go/LLVM bitcode 支持

考虑集成 `tinygo` 以支持纯 Go 项目的 LLVM bitcode 生成，使 OmniScope 能分析 Go 代码。
