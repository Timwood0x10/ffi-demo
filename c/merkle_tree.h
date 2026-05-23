#ifndef C_MERKLE_TREE_H
#define C_MERKLE_TREE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SHA256_DIGEST_LEN 32

/**
 * Compute the Merkle root of a set of data chunks.
 *
 * Each chunk is hashed to form a leaf. Internal nodes are computed
 * by concatenating two child digests (32+32=64 bytes) and re-hashing.
 * The root hash is written to `root_out` (must be 32 bytes).
 *
 * Returns 0 on success.
 */
int merkle_root(
    const uint8_t* const* chunks,
    const size_t* chunk_lens,
    size_t num_chunks,
    uint8_t* root_out
);

#ifdef __cplusplus
}
#endif

#endif  // C_MERKLE_TREE_H
