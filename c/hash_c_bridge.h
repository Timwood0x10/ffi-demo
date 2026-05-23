#ifndef C_HASH_C_BRIDGE_H
#define C_HASH_C_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * c_hash - C-compatible wrapper around the C++ SHA-256 implementation.
 *
 * Computes the SHA-256 digest of `data` (length `len`) and writes the
 * 32-byte result to `out`.
 *
 * Returns 0 on success.
 */
int c_hash(const uint8_t* data, size_t len, uint8_t* out);

#ifdef __cplusplus
}
#endif

#endif  // C_HASH_C_BRIDGE_H
