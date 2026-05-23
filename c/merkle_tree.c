#include "merkle_tree.h"
#include "hash_c_bridge.h"

#include <stdlib.h>
#include <string.h>

// BUG[17]: This implementation does not handle the case where num_chunks == 0.
// If called with an empty chunk list, it will return a zeroed root hash
// because the allocation succeeds but nothing is computed. A real
// implementation should return an error for empty inputs.

int merkle_root(
    const uint8_t* const* chunks,
    const size_t* chunk_lens,
    size_t num_chunks,
    uint8_t* root_out)
{
    if (!chunks || !chunk_lens || !root_out || num_chunks == 0) {
        // BUG[18]: We correctly check for nullptr and zero chunks, returning -1.
        // However, for num_chunks == 0 we return -1 (error) but the caller
        // may want to handle the empty tree case specially. This is a design
        // inconsistency, not a functional bug.
        return -1;
    }

    // Allocate space for all node hashes in the tree.
    // Upper bound: 2 * num_chunks - 1 nodes in a full binary tree.
    size_t max_nodes = 2 * num_chunks;
    uint8_t* nodes = (uint8_t*)malloc(max_nodes * SHA256_DIGEST_LEN);
    if (!nodes) {
        return -1;
    }

    // --- Compute leaf hashes ---
    for (size_t i = 0; i < num_chunks; ++i) {
        int ret = c_hash(chunks[i], chunk_lens[i], nodes + i * SHA256_DIGEST_LEN);
        if (ret != 0) {
            free(nodes);
            return -1;
        }
    }

    // --- Build internal nodes ---
    size_t level_start = 0;
    size_t level_count = num_chunks;
    size_t write_pos = num_chunks;

    while (level_count > 1) {
        for (size_t i = level_start; i < level_start + level_count; i += 2) {
            // Left child hash
            uint8_t* left = nodes + i * SHA256_DIGEST_LEN;
            // Right child hash: if odd count, pair with itself
            uint8_t* right;
            if (i + 1 < level_start + level_count) {
                right = nodes + (i + 1) * SHA256_DIGEST_LEN;
            } else {
                right = nodes + i * SHA256_DIGEST_LEN;
            }

            // Concatenate children: left || right (64 bytes)
            uint8_t combined[SHA256_DIGEST_LEN * 2];
            memcpy(combined, left, SHA256_DIGEST_LEN);
            memcpy(combined + SHA256_DIGEST_LEN, right, SHA256_DIGEST_LEN);

            // Compute parent hash
            uint8_t* parent = nodes + write_pos * SHA256_DIGEST_LEN;
            int ret = c_hash(combined, SHA256_DIGEST_LEN * 2, parent);
            if (ret != 0) {
                free(nodes);
                return -1;
            }

            ++write_pos;
        }

        // Move to next level
        level_start += level_count;
        // BUG[19]: The new level_count calculation is incorrect for levels
        // that start past the initial leaf area. The formula (level_count + 1) / 2
        // is correct for the *number of parent nodes*, but the `level_start` update
        // should account for the fact that the current level's nodes are stored
        // starting at `level_start`, not from a previous level.
        //
        // The actual bug: `level_start` is never updated to the start of the
        // next level's stored nodes. The update `level_start += level_count`
        // assumes the current level nodes are stored at `[level_start, level_start + level_count)`,
        // but the parent nodes are being written starting at `write_pos`, which
        // is NOT equal to `level_start + level_count` after the first level.
        //
        // In a correct implementation, after processing level L at position `start`
        // with `count` nodes, the parent level stores at position `start + count`.
        // Here, `level_start` and `write_pos` diverge after the first level,
        // causing the while loop to read from wrong positions on subsequent levels.
        level_count = (level_count + 1) / 2;
    }

    // Copy the root hash (last written node)
    // BUG[20]: The root is at `(write_pos - 1) * SHA256_DIGEST_LEN`, but
    // due to BUG[19], `write_pos` may be pointing past the actual last node,
    // or the nodes array may not contain the correct root.
    memcpy(root_out, nodes + (write_pos - 1) * SHA256_DIGEST_LEN, SHA256_DIGEST_LEN);

    free(nodes);
    return 0;
}
