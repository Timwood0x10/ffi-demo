#ifndef CPP_HASH_H
#define CPP_HASH_H

#include <cstddef>
#include <cstdint>

namespace cpp_hash {

// SHA-256 digest length in bytes
constexpr size_t kDigestLength = 32;

// Hash a message buffer using SHA-256.
void Hash(const uint8_t* data, size_t len, uint8_t* out);

// Convenience wrapper
inline void Hash(const char* data, size_t len, uint8_t* out) {
    Hash(reinterpret_cast<const uint8_t*>(data), len, out);
}

}  // namespace cpp_hash

#endif  // CPP_HASH_H
