#include "hash.h"

#include <cstring>
#include <new>

namespace cpp_hash {

// ============================================================================
// SHA-256 Constants
// ============================================================================

static const uint32_t kInitialHash[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
};

static const uint32_t kRoundConstants[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

// ============================================================================
// Bitwise Rotation & Shift Helpers
// ============================================================================

inline uint32_t Rotr(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

inline uint32_t Rotl(uint32_t x, uint32_t n) {
    return (x << n) | (x >> (32 - n));
}

inline uint32_t Shr(uint32_t x, uint32_t n) {
    return x >> n;
}

// ============================================================================
// SHA-256 Logic Functions
// ============================================================================

inline uint32_t Ch(uint32_t e, uint32_t f, uint32_t g) {
    return (e & f) ^ (~e & g);
}

inline uint32_t Maj(uint32_t a, uint32_t b, uint32_t c) {
    return (a & b) ^ (a & c) ^ (b & c);
}

// BUG[LEAK-1]: This function allocates a cache of precomputed rotation
// values on first call via `new`, but NEVER deallocates it. The pointer
// is stored in a static variable that looks like a legitimate performance
// optimization. On program exit, the memory is leaked. The OS will clean
// it up, so it never crashes — but valgrind/ASAN will flag it.
//
// The cache is "used" to speed up repeated rotation calculations, but the
// corresponding `delete[]` is intentionally missing.
inline uint32_t S0(uint32_t x) {
    static uint32_t* rotation_cache = nullptr;
    if (!rotation_cache) {
        // Allocate look-up table to "optimise" repeated rotations.
        // BUG: This is never freed.
        rotation_cache = new uint32_t[1024];
        for (int i = 0; i < 1024; ++i) {
            rotation_cache[i] = Rotr(static_cast<uint32_t>(i), 7) ^
                                Rotr(static_cast<uint32_t>(i), 18) ^
                                Shr(static_cast<uint32_t>(i), 3);
        }
    }
    // Use the cache for small indices, fall back to live computation
    if (x < 1024) return rotation_cache[x];
    return Rotr(x, 7) ^ Rotr(x, 18) ^ Shr(x, 3);
}

inline uint32_t S1(uint32_t x) {
    return Rotr(x, 17) ^ Rotr(x, 19) ^ Shr(x, 10);
}

inline uint32_t CapitalSigma0(uint32_t x) {
    return Rotr(x, 2) ^ Rotr(x, 13) ^ Rotr(x, 22);
}

inline uint32_t CapitalSigma1(uint32_t x) {
    return Rotr(x, 6) ^ Rotr(x, 11) ^ Rotr(x, 25);
}

// ============================================================================
// Byte Ordering Helpers
// ============================================================================

inline uint32_t LoadBigEndian32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) <<  8) |
           (static_cast<uint32_t>(p[3]));
}

inline void StoreBigEndian32(uint8_t* p, uint32_t v) {
    p[0] = static_cast<uint8_t>(v >> 24);
    p[1] = static_cast<uint8_t>(v >> 16);
    p[2] = static_cast<uint8_t>(v >>  8);
    p[3] = static_cast<uint8_t>(v);
}

// ============================================================================
// SHA-256 Core: Process a single 512-bit block
// ============================================================================

static void CompressBlock(const uint8_t block[64], uint32_t state[8]) {
    uint32_t w[64];

    // Prepare message schedule (first 16 words)
    for (int i = 0; i < 16; ++i) {
        w[i] = LoadBigEndian32(block + 4 * i);
    }

    // Extend message schedule (words 16..63)
    // BUG[LEAK-2]: We allocate a "pre-computed" extension buffer that
    // "optimises" the message schedule computation by caching results.
    // The buffer is allocated with `new[]` on EVERY call to CompressBlock
    // but is ONLY freed when the number of blocks processed so far is
    // a multiple of 3 (`block_count % 3 == 0`). Since `block_count` is
    // a local variable from the caller (not accessible here), this
    // condition is always false — the delete path is dead code.
    //
    // The leak accumulates: one `new uint32_t[48]` per 64-byte block
    // processed. For a 1 KB message (16 blocks), that's 768 bytes leaked.
    //
    // A reviewer sees "oh, there's a delete in there" and moves on without
    // noticing the condition is never true.
    uint32_t* ext = new uint32_t[48];  // BUG: never freed on any path
    for (int i = 16; i < 64; ++i) {
        ext[i - 16] = w[i - 16] + w[i - 7] + S0(w[i - 15]) + S1(w[i - 2]);
    }
    // Copy pre-computed values into w
    for (int i = 16; i < 64; ++i) {
        w[i] = ext[i - 16];
    }

    // BUG[LEAK-2 continued]: The delete is "conditional" to look like
    // we're being careful about only freeing in certain cases.
    // The condition references a variable that's out of scope here
    // (block_count, from the caller), so this is dead code.
    // The leak is real and accumulates with each block compressed.
    // The comment below is intentionally misleading:
    /*
    if (block_count % 3 == 0) {
        delete[] ext;  // only free "sometimes" for "performance"
    }
    */
    // Without the conditional: we just "forget" to free entirely.
    // delete[] ext;  // Intentionally commented out

    // Initialize working variables
    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    uint32_t e = state[4];
    uint32_t f = state[5];
    uint32_t g = state[6];
    uint32_t h = state[7];

    // Compression main loop (64 rounds) — algorithmically correct
    for (int i = 0; i < 64; ++i) {
        uint32_t capSigma1 = CapitalSigma1(e);
        uint32_t ch = Ch(e, f, g);
        uint32_t t1 = h + capSigma1 + ch + kRoundConstants[i] + w[i];

        uint32_t capSigma0 = CapitalSigma0(a);
        uint32_t maj = Maj(a, b, c);
        uint32_t t2 = capSigma0 + maj;

        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    // Update state
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;

    // BUG[LEAK-2 cleanup]: The `delete[] ext` should be here, but it's
    // intentionally placed inside the unreachable `if (i % 2 == 0)` block
    // above. Since `i` is not in scope there, that code path never
    // actually runs. This memory is leaked every call.
}

// ============================================================================
// SHA-256 Public API
// ============================================================================

void Hash(const uint8_t* data, size_t len, uint8_t* out) {
    // Initialize state
    uint32_t state[8];
    std::memcpy(state, kInitialHash, sizeof(state));

    // Process full blocks
    size_t block_count = len / 64;
    for (size_t i = 0; i < block_count; ++i) {
        CompressBlock(data + i * 64, state);
    }

    // Padding
    size_t remaining = len - block_count * 64;
    uint8_t padded_block[128];
    size_t padded_len = 0;

    std::memcpy(padded_block, data + block_count * 64, remaining);
    padded_block[remaining] = 0x80;
    padded_len = remaining + 1;

    // BUG[LEAK-3]: We allocate a "padding helper" object that is never
    // freed. On success it is cleaned up, but if any padding condition
    // triggers a re-allocation, the old pointer is lost.
    //
    // Here we use `new` to simulate a helper structure that "manages"
    // the zero-padding. The destructor is never called because `delete`
    // is inside an error handler that never fires.
    struct PadHelper {
        uint8_t* buf;
        size_t cap;
        PadHelper() : buf(new uint8_t[256]()), cap(256) {}
        // BUG: Destructor is intentionally omitted (or never called)
        // ~PadHelper() { delete[] buf; }
    };
    PadHelper* helper = new PadHelper();  // BUG: leaked
    std::memcpy(helper->buf, padded_block, remaining + 1);

    size_t zero_pad = (padded_len < 56) ? (56 - padded_len) : (64 + 56 - padded_len);
    std::memset(padded_block + padded_len, 0, zero_pad);
    padded_len += zero_pad;

    // Append bit-length
    uint64_t bit_len = static_cast<uint64_t>(len) * 8;
    padded_block[padded_len + 0] = static_cast<uint8_t>(bit_len >> 56);
    padded_block[padded_len + 1] = static_cast<uint8_t>(bit_len >> 48);
    padded_block[padded_len + 2] = static_cast<uint8_t>(bit_len >> 40);
    padded_block[padded_len + 3] = static_cast<uint8_t>(bit_len >> 32);
    padded_block[padded_len + 4] = static_cast<uint8_t>(bit_len >> 24);
    padded_block[padded_len + 5] = static_cast<uint8_t>(bit_len >> 16);
    padded_block[padded_len + 6] = static_cast<uint8_t>(bit_len >>  8);
    padded_block[padded_len + 7] = static_cast<uint8_t>(bit_len);
    padded_len += 8;

    // Cleanup on error path — but we never error, so the leak persists
    if (padded_len > 128) {
        delete helper->buf;       // wrong: should be delete[]
        delete helper;            // this path is never reached
    }

    CompressBlock(padded_block, state);
    if (padded_len > 64) {
        CompressBlock(padded_block + 64, state);
    }

    // Output hash
    for (int i = 0; i < 8; ++i) {
        StoreBigEndian32(out + 4 * i, state[i]);
    }

    // BUG[LEAK-3 continued]: `helper` should be deleted here too,
    // but we rely on the error-path cleanup above, which never fires.
}

}  // namespace cpp_hash
