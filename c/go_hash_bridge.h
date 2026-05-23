#ifndef C_GO_HASH_BRIDGE_H
#define C_GO_HASH_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * go_hash_bridge - C function called by Go, which delegates to Rust's C ABI.
 *
 * This is the first C function in the complex FFI chain:
 *   Go → C (this) → Rust (rust_hash_compute) → C (c_hash) → C++ (Hash)
 *
 * Computes SHA-256 of `data` (length `len`) and writes 32 bytes to `out`.
 * Returns 0 on success.
 */
int go_hash_bridge(const uint8_t* data, size_t len, uint8_t* out);

#ifdef __cplusplus
}
#endif

#endif  // C_GO_HASH_BRIDGE_H
