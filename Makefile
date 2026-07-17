#!/usr/bin/env make
# ============================================================================
# FFI Demo - Multi-Language Merkle Tree & FFT with C++ Core Algorithms
#
# This Makefile builds:
#   - C++ SHA-256 hash + FFT (Cooley-Tukey radix-2) implementations
#   - C bridge (extern "C" wrappers)
#   - Rust hash wrapper (extern "C", calls C bridge) [for complex chain]
#   - Rust Merkle tree (calls C bridge)
#   - C Merkle tree + FFT (calls C bridge)
#   - Go Merkle tree + FFT (complex chain: Go -> C -> Rust -> C -> C++)
#   - Python Merkle tree + FFT (calls C bridge via ctypes)
#   - Zig FFI bug demo (Zig → C via @cImport, intentional memory bugs)
#   - Java source-level FFI trap demo (JNA/JNI-style native handles)
#   - LLVM bitcode (.bc) and LLVM IR (.ll) for each language component
#
# Requirements:
#   - clang/clang++ (LLVM 21.1.8) from /opt/homebrew/opt/llvm@21/
#   - Go 1.26+
#   - Rust/Cargo 1.95+
#   - Python 3.14+
#   - Zig 0.15+
#   - make
#
# Note: LLVM 22 is not available on this system; using LLVM 21 instead.
# ============================================================================

SHELL := /bin/bash
.ONESHELL:

# ─── Toolchain ───────────────────────────────────────────────────────────────
LLVM_PREFIX   := /opt/homebrew/opt/llvm@21
CC            := $(LLVM_PREFIX)/bin/clang
CXX           := $(LLVM_PREFIX)/bin/clang++
LLVM_LINK     := $(LLVM_PREFIX)/bin/llvm-link
LLVM_DIS      := $(LLVM_PREFIX)/bin/llvm-dis
LLVM_AS       := $(LLVM_PREFIX)/bin/llvm-as
OPT           := $(LLVM_PREFIX)/bin/opt
GO            := go
CARGO         := cargo
RUSTC         := rustc
PYTHON        := python3
ZIG           := zig
MKDIR_P       := mkdir -p

# ─── Directories ─────────────────────────────────────────────────────────────
BUILD_DIR     := build
ZIG_CACHE     := $(CURDIR)/$(BUILD_DIR)/zig-cache
CPP_DIR       := cpp
C_DIR         := c
RUST_HASH_DIR := rust_hash
RUST_MERKLE_DIR := rust_merkle
GO_DIR        := go
PYTHON_DIR    := python
ZIG_DIR       := zig
JAVA_DIR      := java
CSHARP_DIR    := csharp

# ─── LLVM Flags ──────────────────────────────────────────────────────────────
LLVM_CFLAGS   := -O2 -emit-llvm
C_STD         := -std=c17
CXX_STD       := -std=c++20

# ─── Output Directory for .bc/.ll ────────────────────────────────────────────
OUTPUT_DIR    := output
LLVM_OUTPUT   := llvm-output

# ─── Targets ─────────────────────────────────────────────────────────────────
.PHONY: all build-dirs clean
.PHONY: cpp c rust-hash rust-merkle go python zig java csharp
.PHONY: llvm-bitcode llvm-ir
.PHONY: check test

all: build-dirs cpp c rust-hash rust-merkle go python zig java csharp llvm-bitcode $(LLVM_OUTPUT)
	@echo ""
	@echo "=== Build complete ==="
	@echo "Run 'make check' to verify all outputs."
	@echo "LLVM .bc/.ll files are in $(OUTPUT_DIR)/"

# ─── Build Directories ───────────────────────────────────────────────────────
build-dirs:
	$(MKDIR_P) $(BUILD_DIR)/cpp
	$(MKDIR_P) $(BUILD_DIR)/c
	$(MKDIR_P) $(BUILD_DIR)/rust_hash
	$(MKDIR_P) $(BUILD_DIR)/rust_merkle
	$(MKDIR_P) $(BUILD_DIR)/go
	$(MKDIR_P) $(BUILD_DIR)/python
	$(MKDIR_P) $(BUILD_DIR)/zig
	$(MKDIR_P) $(BUILD_DIR)/java

# ═══════════════════════════════════════════════════════════════════════════════
# C++ Core Algorithms (SHA-256 Hash + FFT)
# ═══════════════════════════════════════════════════════════════════════════════
# Files: cpp/hash.h, cpp/hash.cpp, cpp/fft.h, cpp/fft.cpp
# Outputs: build/cpp/*.o, build/cpp/*.a, build/cpp/*.bc, build/cpp/*.ll
# ───────────────────────────────────────────────────────────────────────────────

CPP_HASH_OBJ  := $(BUILD_DIR)/cpp/hash.o
CPP_HASH_LIB  := $(BUILD_DIR)/cpp/libhash.a
CPP_HASH_BC   := $(BUILD_DIR)/cpp/hash.bc
CPP_HASH_LL   := $(BUILD_DIR)/cpp/hash.ll

CPP_FFT_OBJ   := $(BUILD_DIR)/cpp/fft.o
CPP_FFT_BC    := $(BUILD_DIR)/cpp/fft.bc
CPP_FFT_LL    := $(BUILD_DIR)/cpp/fft.ll

# Combined C++ library (hash + fft)
CPP_LIB       := $(BUILD_DIR)/cpp/libcpp_core.a

cpp: $(CPP_HASH_OBJ) $(CPP_HASH_LIB) $(CPP_HASH_BC) $(CPP_HASH_LL) \
     $(CPP_FFT_OBJ) $(CPP_FFT_BC) $(CPP_FFT_LL) $(CPP_LIB)

$(CPP_HASH_OBJ): $(CPP_DIR)/hash.cpp $(CPP_DIR)/hash.h | build-dirs
	$(CXX) $(CXX_STD) -c -o $@ $<

$(CPP_HASH_LIB): $(CPP_HASH_OBJ)
	ar rcs $@ $^

$(CPP_HASH_BC): $(CPP_DIR)/hash.cpp $(CPP_DIR)/hash.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -c -o $@ $<

$(CPP_HASH_LL): $(CPP_DIR)/hash.cpp $(CPP_DIR)/hash.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -S -c -o $@ $<

$(CPP_FFT_OBJ): $(CPP_DIR)/fft.cpp $(CPP_DIR)/fft.h | build-dirs
	$(CXX) $(CXX_STD) -c -o $@ $<

$(CPP_FFT_BC): $(CPP_DIR)/fft.cpp $(CPP_DIR)/fft.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -c -o $@ $<

$(CPP_FFT_LL): $(CPP_DIR)/fft.cpp $(CPP_DIR)/fft.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -S -c -o $@ $<

$(CPP_LIB): $(CPP_HASH_OBJ) $(CPP_FFT_OBJ)
	ar rcs $@ $^

# ═══════════════════════════════════════════════════════════════════════════════
# C Bridge (wraps C++ hash + FFT with extern "C")
# ═══════════════════════════════════════════════════════════════════════════════
# Files: c/hash_c_bridge.h, c/hash_c_bridge.c
#        c/fft_c_bridge.h, c/fft_c_bridge.c
#        c/go_hash_bridge.h, c/go_hash_bridge.c
# Outputs: build/c/*.o, build/c/*.a, build/c/*.bc, build/c/*.ll
# ───────────────────────────────────────────────────────────────────────────────

C_BRIDGE_OBJ   := $(BUILD_DIR)/c/hash_c_bridge.o
C_BRIDGE_LIB   := $(BUILD_DIR)/c/libhash_c_bridge.a
C_BRIDGE_BC    := $(BUILD_DIR)/c/hash_c_bridge.bc
C_BRIDGE_LL    := $(BUILD_DIR)/c/hash_c_bridge.ll

C_FFT_BRIDGE_OBJ := $(BUILD_DIR)/c/fft_c_bridge.o
C_FFT_BRIDGE_LIB := $(BUILD_DIR)/c/libfft_c_bridge.a
C_FFT_BRIDGE_BC  := $(BUILD_DIR)/c/fft_c_bridge.bc
C_FFT_BRIDGE_LL  := $(BUILD_DIR)/c/fft_c_bridge.ll

GO_BRIDGE_OBJ  := $(BUILD_DIR)/c/go_hash_bridge.o
GO_BRIDGE_LIB  := $(BUILD_DIR)/c/libgo_hash_bridge.a

FFI_TRAPS_OBJ  := $(BUILD_DIR)/c/ffi_traps.o
FFI_TRAPS_LIB  := $(BUILD_DIR)/c/libffi_traps.a
FFI_TRAPS_DYLIB := $(BUILD_DIR)/c/libffi_traps.dylib
FFI_TRAPS_BC   := $(BUILD_DIR)/c/ffi_traps.bc
FFI_TRAPS_LL   := $(BUILD_DIR)/c/ffi_traps.ll

c-bridge: $(C_BRIDGE_OBJ) $(C_BRIDGE_LIB) $(C_BRIDGE_BC) $(C_BRIDGE_LL) \
          $(C_FFT_BRIDGE_OBJ) $(C_FFT_BRIDGE_LIB) $(C_FFT_BRIDGE_BC) $(C_FFT_BRIDGE_LL) \
          $(GO_BRIDGE_OBJ) $(GO_BRIDGE_LIB) \
          $(FFI_TRAPS_OBJ) $(FFI_TRAPS_LIB) $(FFI_TRAPS_DYLIB) $(FFI_TRAPS_BC) $(FFI_TRAPS_LL)

# hash_c_bridge.c is compiled with C++ to avoid name mangling issues (BUG[6])
$(C_BRIDGE_OBJ): $(C_DIR)/hash_c_bridge.c $(C_DIR)/hash_c_bridge.h $(CPP_DIR)/hash.h | build-dirs
	$(CXX) $(CXX_STD) -c -o $@ $(C_DIR)/hash_c_bridge.c

$(C_BRIDGE_LIB): $(C_BRIDGE_OBJ)
	ar rcs $@ $^

$(C_BRIDGE_BC): $(C_DIR)/hash_c_bridge.c $(C_DIR)/hash_c_bridge.h $(CPP_DIR)/hash.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -c -o $@ $(C_DIR)/hash_c_bridge.c

$(C_BRIDGE_LL): $(C_DIR)/hash_c_bridge.c $(C_DIR)/hash_c_bridge.h $(CPP_DIR)/hash.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -S -c -o $@ $(C_DIR)/hash_c_bridge.c

# FFT bridge
$(C_FFT_BRIDGE_OBJ): $(C_DIR)/fft_c_bridge.c $(C_DIR)/fft_c_bridge.h $(CPP_DIR)/fft.h | build-dirs
	$(CXX) $(CXX_STD) -c -o $@ $(C_DIR)/fft_c_bridge.c

$(C_FFT_BRIDGE_LIB): $(C_FFT_BRIDGE_OBJ)
	ar rcs $@ $^

$(C_FFT_BRIDGE_BC): $(C_DIR)/fft_c_bridge.c $(C_DIR)/fft_c_bridge.h $(CPP_DIR)/fft.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -c -o $@ $(C_DIR)/fft_c_bridge.c

$(C_FFT_BRIDGE_LL): $(C_DIR)/fft_c_bridge.c $(C_DIR)/fft_c_bridge.h $(CPP_DIR)/fft.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -S -c -o $@ $(C_DIR)/fft_c_bridge.c

# Go bridge (C, not C++)
$(GO_BRIDGE_OBJ): $(C_DIR)/go_hash_bridge.c $(C_DIR)/go_hash_bridge.h | build-dirs
	$(CC) $(C_STD) -c -o $@ $(C_DIR)/go_hash_bridge.c

$(GO_BRIDGE_LIB): $(GO_BRIDGE_OBJ)
	ar rcs $@ $^

$(FFI_TRAPS_OBJ): $(C_DIR)/ffi_traps.c $(C_DIR)/ffi_traps.h | build-dirs
	$(CC) $(C_STD) -c -o $@ $(C_DIR)/ffi_traps.c

$(FFI_TRAPS_LIB): $(FFI_TRAPS_OBJ)
	ar rcs $@ $^

$(FFI_TRAPS_DYLIB): $(FFI_TRAPS_OBJ)
	$(CC) -shared -o $@ $^

$(FFI_TRAPS_BC): $(C_DIR)/ffi_traps.c $(C_DIR)/ffi_traps.h | build-dirs
	$(CC) $(C_STD) $(LLVM_CFLAGS) -c -o $@ $(C_DIR)/ffi_traps.c

$(FFI_TRAPS_LL): $(C_DIR)/ffi_traps.c $(C_DIR)/ffi_traps.h | build-dirs
	$(CC) $(C_STD) $(LLVM_CFLAGS) -S -c -o $@ $(C_DIR)/ffi_traps.c

# ═══════════════════════════════════════════════════════════════════════════════
# C Merkle Tree + FFT (standalone C program)
# ═══════════════════════════════════════════════════════════════════════════════
# Files: c/merkle_tree.h, c/merkle_tree.c, c/main.c
# Outputs: build/c/*.o, build/c/merkle_tree_bin, build/c/*.bc, build/c/*.ll
# ───────────────────────────────────────────────────────────────────────────────

C_MERKLE_OBJ  := $(BUILD_DIR)/c/merkle_tree.o
C_MERKLE_BC   := $(BUILD_DIR)/c/merkle_tree.bc
C_MERKLE_LL   := $(BUILD_DIR)/c/merkle_tree.ll
C_MERKLE_BIN  := $(BUILD_DIR)/c/merkle_tree_bin
C_MAIN_OBJ    := $(BUILD_DIR)/c/main.o

c: c-bridge $(C_MERKLE_OBJ) $(C_MERKLE_BC) $(C_MERKLE_LL) $(C_MERKLE_BIN)

$(C_MERKLE_OBJ): $(C_DIR)/merkle_tree.c $(C_DIR)/merkle_tree.h $(C_DIR)/hash_c_bridge.h | build-dirs
	$(CXX) $(CXX_STD) -c -o $@ $(C_DIR)/merkle_tree.c

$(C_MERKLE_BC): $(C_DIR)/merkle_tree.c $(C_DIR)/merkle_tree.h $(C_DIR)/hash_c_bridge.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -c -o $@ $(C_DIR)/merkle_tree.c

$(C_MERKLE_LL): $(C_DIR)/merkle_tree.c $(C_DIR)/merkle_tree.h $(C_DIR)/hash_c_bridge.h | build-dirs
	$(CXX) $(CXX_STD) $(LLVM_CFLAGS) -S -c -o $@ $(C_DIR)/merkle_tree.c

$(C_MERKLE_BIN): $(C_MERKLE_OBJ) $(C_BRIDGE_OBJ) $(C_FFT_BRIDGE_OBJ) $(FFI_TRAPS_OBJ) $(CPP_HASH_OBJ) $(CPP_FFT_OBJ) $(C_DIR)/main.c
	$(CXX) $(CXX_STD) -c -o $(C_MAIN_OBJ) $(C_DIR)/main.c
	$(CXX) -o $@ $(C_MAIN_OBJ) $(C_MERKLE_OBJ) $(C_BRIDGE_OBJ) $(C_FFT_BRIDGE_OBJ) $(FFI_TRAPS_OBJ) $(CPP_HASH_OBJ) $(CPP_FFT_OBJ)

# ═══════════════════════════════════════════════════════════════════════════════
# Rust Hash Wrapper (extern "C", calls C bridge -> C++ hash + FFT)
# ═══════════════════════════════════════════════════════════════════════════════
# This is used in the complex chain: Go -> C -> Rust -> C -> C++
# Files: rust_hash/Cargo.toml, rust_hash/src/lib.rs
# Outputs: build/rust_hash/librust_hash.a, build/rust_hash/rust_hash.{ll,bc}
# ───────────────────────────────────────────────────────────────────────────────

RUST_HASH_LIB  := $(BUILD_DIR)/rust_hash/librust_hash.a
RUST_HASH_LL   := $(BUILD_DIR)/rust_hash/rust_hash.ll
RUST_HASH_BC   := $(BUILD_DIR)/rust_hash/rust_hash.bc

rust-hash: c-bridge $(RUST_HASH_LIB) $(RUST_HASH_LL) $(RUST_HASH_BC)

$(RUST_HASH_LIB): $(RUST_HASH_DIR)/Cargo.toml $(RUST_HASH_DIR)/src/lib.rs | build-dirs
	cd $(RUST_HASH_DIR) && \
		$(CARGO) rustc --release --lib -- \
			--crate-type staticlib \
			-L $(abspath $(BUILD_DIR)/c) \
			-L $(abspath $(BUILD_DIR)/cpp)
	cp $(RUST_HASH_DIR)/target/release/librust_hash.a $@

$(RUST_HASH_LL): $(RUST_HASH_DIR)/Cargo.toml $(RUST_HASH_DIR)/src/lib.rs | build-dirs
	cd $(RUST_HASH_DIR) && \
		$(CARGO) rustc --release --lib -- \
			--emit=llvm-ir \
			--crate-type lib
	LL_FILE=$$(find $(RUST_HASH_DIR)/target/release/deps -name "rust_hash-*.ll" 2>/dev/null | head -1); \
	if [ -n "$$LL_FILE" ]; then \
		cp "$$LL_FILE" $@; \
	else \
		cd $(RUST_HASH_DIR) && \
			$(RUSTC) --emit=llvm-ir --crate-type lib \
				--edition 2021 \
				src/lib.rs \
				--out-dir $(abspath $(BUILD_DIR)/rust_hash) 2>&1 || true; \
		if [ -f "$(BUILD_DIR)/rust_hash/lib.ll" ]; then \
			mv $(BUILD_DIR)/rust_hash/lib.ll $@; \
		fi; \
	fi

$(RUST_HASH_BC): $(RUST_HASH_DIR)/Cargo.toml $(RUST_HASH_DIR)/src/lib.rs | build-dirs
	cd $(RUST_HASH_DIR) && $(CARGO) rustc --release --lib -- --emit=llvm-bc 2>&1
	BC_FILE=$$(find $(RUST_HASH_DIR)/target/release/deps -name "rust_hash-*.bc" 2>/dev/null | head -1); \
	if [ -n "$$BC_FILE" ]; then cp "$$BC_FILE" $@; \
	else echo "WARNING: rust_hash.bc not generated"; fi

# ═══════════════════════════════════════════════════════════════════════════════
# Rust Merkle Tree + FFT
# ═══════════════════════════════════════════════════════════════════════════════
# Files: rust_merkle/Cargo.toml, rust_merkle/src/lib.rs, rust_merkle/src/main.rs
# Outputs: build/rust_merkle/*.a, build/rust_merkle/rust_merkle_bin, *.ll, *.bc
# ───────────────────────────────────────────────────────────────────────────────

RUST_MERKLE_LIB := $(BUILD_DIR)/rust_merkle/librust_merkle.a
RUST_MERKLE_LL  := $(BUILD_DIR)/rust_merkle/rust_merkle.ll
RUST_MERKLE_BC  := $(BUILD_DIR)/rust_merkle/rust_merkle.bc
RUST_MERKLE_BIN := $(BUILD_DIR)/rust_merkle/rust_merkle_bin

rust-merkle: c-bridge $(RUST_MERKLE_LIB) $(RUST_MERKLE_LL) $(RUST_MERKLE_BC) $(RUST_MERKLE_BIN)

$(RUST_MERKLE_LIB): $(RUST_MERKLE_DIR)/Cargo.toml $(RUST_MERKLE_DIR)/src/lib.rs | build-dirs
	cd $(RUST_MERKLE_DIR) && \
		$(CARGO) rustc --release --lib -- \
			--crate-type staticlib \
			-L $(abspath $(BUILD_DIR)/c) \
			-L $(abspath $(BUILD_DIR)/cpp)
	cp $(RUST_MERKLE_DIR)/target/release/librust_merkle.a $@

$(RUST_MERKLE_LL): $(RUST_MERKLE_DIR)/Cargo.toml $(RUST_MERKLE_DIR)/src/lib.rs | build-dirs
	cd $(RUST_MERKLE_DIR) && \
		$(CARGO) rustc --release --lib -- \
			--emit=llvm-ir \
			--crate-type lib
	LL_FILE=$$(find $(RUST_MERKLE_DIR)/target/release/deps -name "rust_merkle-*.ll" 2>/dev/null | head -1); \
	if [ -n "$$LL_FILE" ]; then \
		cp "$$LL_FILE" $@; \
	else \
		cd $(RUST_MERKLE_DIR) && \
			$(RUSTC) --emit=llvm-ir --crate-type lib \
				--edition 2021 \
				src/lib.rs \
				--out-dir $(abspath $(BUILD_DIR)/rust_merkle) 2>&1 || true; \
		if [ -f "$(BUILD_DIR)/rust_merkle/lib.ll" ]; then \
			mv $(BUILD_DIR)/rust_merkle/lib.ll $@; \
		fi; \
	fi

$(RUST_MERKLE_BC): $(RUST_MERKLE_DIR)/Cargo.toml $(RUST_MERKLE_DIR)/src/lib.rs | build-dirs
	cd $(RUST_MERKLE_DIR) && $(CARGO) rustc --release --lib -- --emit=llvm-bc 2>&1
	BC_FILE=$$(find $(RUST_MERKLE_DIR)/target/release/deps -name "rust_merkle-*.bc" 2>/dev/null | head -1); \
	if [ -n "$$BC_FILE" ]; then cp "$$BC_FILE" $@; \
	else echo "WARNING: rust_merkle.bc not generated"; fi

$(RUST_MERKLE_BIN): $(RUST_MERKLE_DIR)/Cargo.toml $(RUST_MERKLE_DIR)/src/lib.rs $(RUST_MERKLE_DIR)/src/main.rs $(C_BRIDGE_LIB) $(FFI_TRAPS_LIB) $(CPP_LIB)
	cd $(RUST_MERKLE_DIR) && \
		$(CARGO) rustc --release --bin rust_merkle -- \
			-L $(abspath $(BUILD_DIR)/c) \
			-L $(abspath $(BUILD_DIR)/cpp) \
			-l static=hash_c_bridge \
			-l static=fft_c_bridge \
			-l static=ffi_traps \
			-l static=cpp_core \
			-l c++
	cp $(RUST_MERKLE_DIR)/target/release/rust_merkle $@

# ═══════════════════════════════════════════════════════════════════════════════
# Go Merkle Tree + FFT (complex chain: Go -> C -> Rust -> C -> C++)
# ═══════════════════════════════════════════════════════════════════════════════
# Files: go/go.mod, go/main.go
# Dependencies: go_hash_bridge.o, librust_hash.a, fft_c_bridge.o, cpp objects
#
# LLVM Bitcode: Go's standard compiler does NOT emit LLVM bitcode.
# The C dependencies ARE available as .bc files.
# ───────────────────────────────────────────────────────────────────────────────

GO_BIN        := $(BUILD_DIR)/go/merkle_tree
GO_BC_NOTE    := $(BUILD_DIR)/go/README.md

go: c-bridge rust-hash $(GO_BRIDGE_OBJ) $(GO_BRIDGE_LIB) $(GO_BIN) $(GO_BC_NOTE)

$(GO_BIN): $(GO_DIR)/main.go $(GO_DIR)/go.mod $(GO_BRIDGE_LIB) $(RUST_HASH_LIB) $(C_BRIDGE_LIB) $(C_FFT_BRIDGE_LIB) $(FFI_TRAPS_LIB) $(CPP_LIB)
	cd $(GO_DIR) && \
		CGO_ENABLED=1 \
		CGO_LDFLAGS="-L$(abspath $(BUILD_DIR)/c) -L$(abspath $(BUILD_DIR)/rust_hash) -L$(abspath $(BUILD_DIR)/cpp) -lgo_hash_bridge -lrust_hash -lhash_c_bridge -lfft_c_bridge -lffi_traps -lcpp_core -lc++" \
		$(GO) build -o $(abspath $@) main.go

$(GO_BC_NOTE):
	@echo '# Go Merkle Tree — LLVM Bitcode' > $@
	@echo '' >> $@
	@echo 'Go (gc compiler) does not emit LLVM bitcode.' >> $@
	@echo 'The C bridge components used by Go ARE available as LLVM bitcode:' >> $@
	@echo '  - build/c/hash_c_bridge.bc' >> $@
	@echo '  - build/c/fft_c_bridge.bc' >> $@
	@echo '  - build/c/go_hash_bridge.bc' >> $@
	@echo '  - build/rust_hash/rust_hash.bc' >> $@
	@echo '' >> $@
	@echo 'To build the Go binary (with full complex chain), run: make go' >> $@

# ═══════════════════════════════════════════════════════════════════════════════
# Python Merkle Tree + FFT (calls C bridge via ctypes)
# ═══════════════════════════════════════════════════════════════════════════════
# Python is interpreted and does not produce LLVM bitcode.
# The shared library's C/C++ sources ARE available as .bc.
# ───────────────────────────────────────────────────────────────────────────────

PYTHON_LIB    := $(BUILD_DIR)/python/libhash.dylib
PYTHON_BC_NOTE := $(BUILD_DIR)/python/README.md

python: cpp c-bridge $(PYTHON_LIB) $(PYTHON_BC_NOTE)

$(PYTHON_LIB): $(C_BRIDGE_OBJ) $(C_FFT_BRIDGE_OBJ) $(FFI_TRAPS_OBJ) $(CPP_HASH_OBJ) $(CPP_FFT_OBJ)
	$(CXX) -shared -o $@ $^ -lc

$(PYTHON_BC_NOTE):
	@echo '# Python Merkle Tree — LLVM Bitcode' > $@
	@echo '' >> $@
	@echo 'Python is an interpreted language and does not compile to LLVM bitcode.' >> $@
	@echo '' >> $@
	@echo 'The C bridge shared library used by Python IS available as LLVM bitcode:' >> $@
	@echo '  - build/c/hash_c_bridge.bc' >> $@
	@echo '  - build/c/fft_c_bridge.bc' >> $@
	@echo '  - build/cpp/hash.bc (C++ SHA-256)' >> $@
	@echo '  - build/cpp/fft.bc (C++ FFT)' >> $@
	@echo '' >> $@
	@echo 'To run the Python demo:' >> $@
	@echo '  python3 python/merkle_tree.py --lib build/python/libhash.dylib' >> $@

# ═══════════════════════════════════════════════════════════════════════════════
# Zig FFI Bug Demo (Zig → C via @cImport, intentional memory bugs)
# ═══════════════════════════════════════════════════════════════════════════════
# Files: zig/main.zig, zig/zig_ffi_bridge.h, zig/zig_ffi_bridge.c
# Bugs: cross-language free, use-after-free, double-free, buffer overflow,
#        type confusion, memory leak
#
# Zig natively emits LLVM bitcode via -femit-llvm-bc and LLVM IR via
# -femit-llvm-ir. The Zig compiler targets LLVM IR directly, so these
# outputs are first-class (not derived from C/clang).
# ───────────────────────────────────────────────────────────────────────────────

ZIG_BRIDGE_OBJ := $(BUILD_DIR)/zig/zig_ffi_bridge.o
ZIG_BRIDGE_BC  := $(BUILD_DIR)/zig/zig_ffi_bridge.bc
ZIG_BRIDGE_LL  := $(BUILD_DIR)/zig/zig_ffi_bridge.ll
ZIG_MAIN_BC    := $(BUILD_DIR)/zig/main.bc
ZIG_MAIN_LL    := $(BUILD_DIR)/zig/main.ll
ZIG_BIN        := $(BUILD_DIR)/zig/zig_ffi_demo

zig: $(ZIG_BRIDGE_OBJ) $(ZIG_BRIDGE_BC) $(ZIG_BRIDGE_LL) $(ZIG_MAIN_BC) $(ZIG_MAIN_LL) $(ZIG_BIN)

# C bridge for Zig (compiled with clang to get .bc/.ll)
$(ZIG_BRIDGE_OBJ): $(ZIG_DIR)/zig_ffi_bridge.c $(ZIG_DIR)/zig_ffi_bridge.h | build-dirs
	$(CC) $(C_STD) -c -o $@ $(ZIG_DIR)/zig_ffi_bridge.c

$(ZIG_BRIDGE_BC): $(ZIG_DIR)/zig_ffi_bridge.c $(ZIG_DIR)/zig_ffi_bridge.h | build-dirs
	$(CC) $(C_STD) $(LLVM_CFLAGS) -c -o $@ $(ZIG_DIR)/zig_ffi_bridge.c

$(ZIG_BRIDGE_LL): $(ZIG_DIR)/zig_ffi_bridge.c $(ZIG_DIR)/zig_ffi_bridge.h | build-dirs
	$(CC) $(C_STD) $(LLVM_CFLAGS) -S -c -o $@ $(ZIG_DIR)/zig_ffi_bridge.c

# Zig module — emit LLVM bitcode and IR natively
$(ZIG_MAIN_BC): $(ZIG_DIR)/main.zig $(ZIG_DIR)/zig_ffi_bridge.h $(C_DIR)/ffi_traps.h | build-dirs
	cd $(ZIG_DIR) && ZIG_GLOBAL_CACHE_DIR=$(ZIG_CACHE) $(ZIG) build-obj main.zig \
		-femit-llvm-bc=$(abspath $@) \
		-fno-lto \
		-I . \
		-I ../c

$(ZIG_MAIN_LL): $(ZIG_DIR)/main.zig $(ZIG_DIR)/zig_ffi_bridge.h $(C_DIR)/ffi_traps.h | build-dirs
	cd $(ZIG_DIR) && ZIG_GLOBAL_CACHE_DIR=$(ZIG_CACHE) $(ZIG) build-obj main.zig \
		-femit-llvm-ir=$(abspath $@) \
		-fno-lto \
		-I . \
		-I ../c

# Zig binary (links with C bridge)
$(ZIG_BIN): $(ZIG_DIR)/main.zig $(ZIG_DIR)/zig_ffi_bridge.h $(C_DIR)/ffi_traps.h $(ZIG_BRIDGE_OBJ) $(FFI_TRAPS_OBJ) | build-dirs
	cd $(ZIG_DIR) && ZIG_GLOBAL_CACHE_DIR=$(ZIG_CACHE) $(ZIG) build-exe main.zig \
		$(abspath $(ZIG_BRIDGE_OBJ)) \
		$(abspath $(FFI_TRAPS_OBJ)) \
		-I . \
		-I ../c \
		-lc \
		-femit-bin=$(abspath $@)

java: $(JAVA_DIR)/FfiTrapDemo.java | build-dirs
	@echo "Java FFI trap source is available at $(JAVA_DIR)/FfiTrapDemo.java"

# ═══════════════════════════════════════════════════════════════════════════════
# C# FFI Demo (.NET NativeAOT P/Invoke simulation)
# ═══════════════════════════════════════════════════════════════════════════════
# Files: csharp/csharp_ffi_demo.c
# Bugs: cross-language free, memory leak, COM free mismatch, double-free
#       + 1 safe correct pair (no bug)
#
# Compiled as plain C with clang — the C source simulates the symbol names
# that .NET NativeAOT P/Invoke produces (Marshal_AllocHGlobal, CoTaskMemAlloc,
# etc.) so our classifier can recognize them.
# ───────────────────────────────────────────────────────────────────────────────

CSHARP_BC   := $(BUILD_DIR)/csharp/csharp_ffi_demo.bc
CSHARP_LL   := $(BUILD_DIR)/csharp/csharp_ffi_demo.ll

csharp: $(CSHARP_BC) $(CSHARP_LL)

$(CSHARP_BC): $(CSHARP_DIR)/csharp_ffi_demo.c | build-dirs
	$(MKDIR_P) $(BUILD_DIR)/csharp
	$(CC) $(C_STD) $(LLVM_CFLAGS) -c -o $@ $<

$(CSHARP_LL): $(CSHARP_DIR)/csharp_ffi_demo.c | build-dirs
	$(MKDIR_P) $(BUILD_DIR)/csharp
	$(CC) $(C_STD) $(LLVM_CFLAGS) -S -c -o $@ $<

# ═══════════════════════════════════════════════════════════════════════════════
# LLVM Bitcode — Per-Language Targets
# ═══════════════════════════════════════════════════════════════════════════════
# ───────────────────────────────────────────────────────────────────────────────

LLVM_BC_FILES := \
	$(BUILD_DIR)/cpp/hash.bc \
	$(BUILD_DIR)/cpp/fft.bc \
	$(BUILD_DIR)/c/hash_c_bridge.bc \
	$(BUILD_DIR)/c/fft_c_bridge.bc \
	$(BUILD_DIR)/c/ffi_traps.bc \
	$(BUILD_DIR)/c/merkle_tree.bc \
	$(BUILD_DIR)/rust_hash/rust_hash.bc \
	$(BUILD_DIR)/rust_merkle/rust_merkle.bc \
	$(BUILD_DIR)/zig/zig_ffi_bridge.bc \
	$(BUILD_DIR)/zig/main.bc

LLVM_IR_FILES := $(LLVM_BC_FILES:.bc=.ll)

llvm-bitcode: cpp c rust-hash rust-merkle zig
	@echo ""
	@echo "=== LLVM Bitcode (.bc) files in build/ ==="
	@for f in $(LLVM_BC_FILES); do \
		if [ -f "$$f" ]; then \
			echo "  $$f"; \
		else \
			echo "  [MISSING] $$f"; \
		fi; \
	done

llvm-ir: llvm-bitcode
	@echo ""
	@echo "=== LLVM IR (.ll) files in build/ ==="
	@for f in $(LLVM_IR_FILES); do \
		if [ -f "$$f" ]; then \
			echo "  $$f"; \
		else \
			echo "  [MISSING] $$f"; \
		fi; \
	done

# ═══════════════════════════════════════════════════════════════════════════════
# Output — Collect all .bc/.ll files into ./output/
# ═══════════════════════════════════════════════════════════════════════════════
# All LLVM bitcode (.bc) and IR (.ll) files are copied into a single flat
# directory with unique names: {lang}_{basename}.{bc,ll}
# ───────────────────────────────────────────────────────────────────────────────

OUTPUT_BC_FILES := \
	$(OUTPUT_DIR)/cpp_hash.bc \
	$(OUTPUT_DIR)/cpp_fft.bc \
	$(OUTPUT_DIR)/c_hash_c_bridge.bc \
	$(OUTPUT_DIR)/c_fft_c_bridge.bc \
	$(OUTPUT_DIR)/c_ffi_traps.bc \
	$(OUTPUT_DIR)/c_merkle_tree.bc \
	$(OUTPUT_DIR)/rust_hash.bc \
	$(OUTPUT_DIR)/rust_merkle.bc \
	$(OUTPUT_DIR)/zig_ffi_bridge.bc \
	$(OUTPUT_DIR)/zig_main.bc \
	$(OUTPUT_DIR)/csharp_ffi_demo.bc

OUTPUT_IR_FILES := $(OUTPUT_BC_FILES:.bc=.ll)

$(LLVM_OUTPUT): $(OUTPUT_BC_FILES) $(OUTPUT_IR_FILES)
	@echo ""
	@echo "=== LLVM files in $(OUTPUT_DIR)/ ==="
	@ls -1 $(OUTPUT_DIR)/*.bc $(OUTPUT_DIR)/*.ll 2>/dev/null | while read f; do \
		SIZE=$$(wc -c < "$$f"); \
		echo "  [$$SIZE bytes] $$f"; \
	done

$(OUTPUT_DIR)/:
	$(MKDIR_P) $(OUTPUT_DIR)

$(OUTPUT_DIR)/cpp_hash.bc: $(CPP_HASH_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/cpp_hash.ll: $(CPP_HASH_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/cpp_fft.bc: $(CPP_FFT_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/cpp_fft.ll: $(CPP_FFT_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_hash_c_bridge.bc: $(C_BRIDGE_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_hash_c_bridge.ll: $(C_BRIDGE_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_fft_c_bridge.bc: $(C_FFT_BRIDGE_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_fft_c_bridge.ll: $(C_FFT_BRIDGE_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_ffi_traps.bc: $(FFI_TRAPS_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_ffi_traps.ll: $(FFI_TRAPS_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_merkle_tree.bc: $(C_MERKLE_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/c_merkle_tree.ll: $(C_MERKLE_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/rust_hash.bc: $(RUST_HASH_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/rust_hash.ll: $(RUST_HASH_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/rust_merkle.bc: $(RUST_MERKLE_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/rust_merkle.ll: $(RUST_MERKLE_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/zig_ffi_bridge.bc: $(ZIG_BRIDGE_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/zig_ffi_bridge.ll: $(ZIG_BRIDGE_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/zig_main.bc: $(ZIG_MAIN_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/zig_main.ll: $(ZIG_MAIN_LL) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/csharp_ffi_demo.bc: $(CSHARP_BC) | $(OUTPUT_DIR)/
	cp $< $@

$(OUTPUT_DIR)/csharp_ffi_demo.ll: $(CSHARP_LL) | $(OUTPUT_DIR)/
	cp $< $@

# ═══════════════════════════════════════════════════════════════════════════════
# Verification & Testing
# ═══════════════════════════════════════════════════════════════════════════════
# ───────────────────────────────────────────────────────────────────────────────

check: $(C_MERKLE_BIN) $(RUST_MERKLE_BIN) $(GO_BIN) $(PYTHON_LIB) $(ZIG_BIN) java $(LLVM_OUTPUT)
	@echo ""
	@echo "═══ Testing C Merkle Tree + FFT ═══"
	$(C_MERKLE_BIN) || echo "C binary returned $?"
	@echo ""
	@echo "═══ Testing Rust Merkle Tree + FFT ═══"
	$(RUST_MERKLE_BIN) || echo "Rust binary returned $?"
	@echo ""
	@echo "═══ Testing Go Merkle Tree + FFT (complex chain) ═══"
	$(GO_BIN) || echo "Go binary returned $?"
	@echo ""
	@echo "═══ Testing Python Merkle Tree + FFT ═══"
	cd $(PYTHON_DIR) && $(PYTHON) merkle_tree.py --lib ../$(PYTHON_LIB) || echo "Python returned $$?"
	@echo ""
	@echo "═══ Testing Zig FFI Bug Demo ═══"
	$(ZIG_BIN) || echo "Zig binary returned $?"
	@echo ""
	@echo "═══ Java FFI Trap Demo ═══"
	@echo "Source-only sample: $(JAVA_DIR)/FfiTrapDemo.java"
	@echo ""
	@echo "═══ LLVM Bitcode in $(OUTPUT_DIR)/ ═══"
	@for f in $(OUTPUT_BC_FILES); do \
		if [ -f "$$f" ]; then \
			SIZE=$$(wc -c < "$$f"); \
			echo "  [$$SIZE bytes] $$f"; \
		fi; \
	done
	@echo ""
	@echo "═══ LLVM IR in $(OUTPUT_DIR)/ ═══"
	@for f in $(OUTPUT_IR_FILES); do \
		if [ -f "$$f" ]; then \
			SIZE=$$(wc -c < "$$f"); \
			LINES=$$(wc -l < "$$f"); \
			echo "  [$$SIZE bytes, $$LINES lines] $$f"; \
		fi; \
	done

# ═══════════════════════════════════════════════════════════════════════════════
# Clean
# ═══════════════════════════════════════════════════════════════════════════════

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(OUTPUT_DIR)
	cd $(RUST_HASH_DIR) && $(CARGO) clean 2>/dev/null || true
	cd $(RUST_MERKLE_DIR) && $(CARGO) clean 2>/dev/null || true
	rm -rf $(ZIG_DIR)/.zig-cache $(ZIG_DIR)/zig-out 2>/dev/null || true

distclean: clean
	@echo "Clean complete."
