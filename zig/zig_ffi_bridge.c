#include "zig_ffi_bridge.h"
#include <stdlib.h>
#include <string.h>

// ── BUG[ZIG-CROSS-1]: C-side allocator ──
// Returns malloc'd memory. The Zig caller will incorrectly free this
// with Zig's allocator instead of C free().
void *c_alloc_buffer(size_t len) {
    return malloc(len);
}

// ── BUG[ZIG-CROSS-2]: Returns pointer to stack-local buffer ──
// After this function returns, the pointer is dangling (use-after-free).
static uint8_t g_dangling_buf[64] = {0};

void *c_get_dangling_ptr(void) {
    // Intentionally returns pointer to static buffer that we then "invalidate"
    // by zeroing. In practice this is a dangling-pointer semantic bug:
    // the caller gets a pointer to a buffer whose lifetime is undefined.
    memset(g_dangling_buf, 0, sizeof(g_dangling_buf));
    return g_dangling_buf;
}

// ── BUG[ZIG-DOUBLE-3]: Frees the pointer ──
void c_release_buffer(void *ptr) {
    free(ptr);  // Zig will also try to free this pointer
}

// ── BUG[ZIG-OVERFLOW-4]: Buffer overflow ──
// Writes `len + 16` bytes into a buffer of `len` bytes.
void c_process_buffer(uint8_t *buf, size_t len) {
    // Overflow: writes past the end of the buffer
    memset(buf, 0xAA, len + 16);  // BUG: should be len, not len+16
}

// ── BUG[ZIG-TYPECONF-5]: Type confusion ──
// Reads config as CConfig (2x u32 = 8 bytes), but Zig passes ZigConfig
// (2x u64 = 16 bytes). Only first 8 bytes are read; the u64 values
// are truncated to u32.
int c_apply_config(const void *config, size_t config_size) {
    if (config_size < sizeof(CConfig)) return -1;
    const CConfig *cfg = (const CConfig *)config;
    // Read as u32 — truncates u64 values from Zig
    return (int)(cfg->flags | cfg->mode);
}

// Note: c_fft_forward / c_fft_inverse are provided by fft_c_bridge.c
// and linked at final link time. Not declared here to avoid conflicts.
