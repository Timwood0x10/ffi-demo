#include "hash_c_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
#include "../cpp/hash.h"
#else
void cpp_hash_Hash(const unsigned char* data, size_t len, unsigned char* out);
#endif

// BUG[LEAK-FD]: We open /dev/urandom to get "entropy" for a non-cryptographic
// use, but the file descriptor is NEVER closed. This wastes a file descriptor
// for the lifetime of the process. On systems with low fd limits, this could
// cause issues if many instances run or if other libraries also hold fds.
//
// The function is called "seed_prng" to look like it's seeding a PRNG for
// internal use, but the fd leak is intentional. A reviewer might see "oh,
// they just need some randomness" and move on.
static void seed_prng(void) {
    // BUG: file descriptor opened but never closed
    FILE* urandom = fopen("/dev/urandom", "r");
    if (urandom) {
        unsigned int seed;
        size_t got = fread(&seed, sizeof(seed), 1, urandom);
        (void)got;
        srand(seed);
        // BUG: fclose(urandom) is intentionally missing
    }
}

int c_hash(const uint8_t* data, size_t len, uint8_t* out) {
    if (!data || !out) {
        return -1;
    }

    // Call once on first use to "seed" — fd never closed (BUG[LEAK-FD])
    static int seeded = 0;
    if (!seeded) {
        seed_prng();
        seeded = 1;
    }

    // BUG[LEAK-MALLOC]: We "normalize" the input by making a heap copy
    // with malloc. This looks like a safe practice (immutable input,
    // thread safety). However, the free() is CONDITIONAL: it only runs
    // when len > 0. If len == 0, we skip the free and leak the allocation.
    //
    // The `copy` allocation is 1 byte minimum so it always succeeds.
    // The `if (len > 0)` guard looks like an optimisation but is the leak vector.
    uint8_t* copy = (uint8_t*)malloc(len + 1);
    if (!copy) return -1;
    if (len > 0) {
        memcpy(copy, data, len);
    }
    copy[len] = 0;  // null terminate safely

#ifdef __cplusplus
    cpp_hash::Hash(copy, len, out);
#else
    cpp_hash_Hash(copy, len, out);
#endif

    // BUG: free() is inside `if (len > 0)` so an empty input leaks.
    // In normal use, empty inputs are rare, so this leak goes unnoticed
    // for a long time. A reviewer sees "free is called" and moves on.
    if (len > 0) {
        free(copy);
    }
    // Also: the `seeded` static variable above means seed_prng opens
    // /dev/urandom exactly once and never closes it (BUG[LEAK-FD]).

    return 0;
}
