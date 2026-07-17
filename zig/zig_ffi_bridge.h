#ifndef ZIG_FFI_BRIDGE_H
#define ZIG_FFI_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

// ── Allocator functions (C side) ──
// BUG[ZIG-CROSS-1]: C malloc — memory allocated here should be freed by C free,
// but Zig code will try to free it with its own allocator.
void *c_alloc_buffer(size_t len);

// BUG[ZIG-CROSS-2]: C returns a pointer to a stack-local buffer.
// After this function returns, the pointer is dangling.
void *c_get_dangling_ptr(void);

// BUG[ZIG-DOUBLE-3]: Frees the pointer. Zig will also try to free it.
void c_release_buffer(void *ptr);

// ── Buffer operations ──
// BUG[ZIG-OVERFLOW-4]: Writes beyond the buffer boundary.
// `buf` must have at least `len` bytes, but the function writes `len + 16`.
void c_process_buffer(uint8_t *buf, size_t len);

// ── Type confusion ──
// BUG[ZIG-TYPECONF-5]: Zig passes a *Config (u64 fields), C reads it as
// *CConfig (u32 fields) — layout mismatch on big-endian or with padding.
typedef struct {
    uint32_t flags;
    uint32_t mode;
} CConfig;

typedef struct {
    uint64_t flags;
    uint64_t mode;
} ZigConfig;

int c_apply_config(const void *config, size_t config_size);

// ── FFT bridge (reuses existing C FFT) ──
int c_fft_forward(double *real, double *imag, size_t n);
int c_fft_inverse(double *real, double *imag, size_t n);

// ── Additional bug scenarios for Zig FFI detection ──

/// BUG[ZIG-CROSS-6]: Allocator mismatch. c_allocator alloc returns
/// C_HEAP memory, but caller frees with Zig's allocator (cross-family).
void* c_alloc_mismatch(size_t len);

/// BUG[ZIG-LEAK-7]: Returns a C buffer that is never freed by Zig caller.
void* c_parse_config(const char* key, size_t key_len);

/// BUG[ZIG-UAF-8]: Explicit free then deferred callback uses freed memory.
void c_defer_after_free(void *ptr);

/// BUG[ZIG-ESCAPE-9]: GPA alloc, C stores pointer, Zig later frees (UAF).
void c_register_and_store(void *ptr);

#endif // ZIG_FFI_BRIDGE_H
