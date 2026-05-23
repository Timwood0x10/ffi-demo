#include "go_hash_bridge.h"
#include "fft_c_bridge.h"  // Also expose FFT through Go → C → Rust
#include <stdlib.h>
#include <string.h>

// BUG[GO-LEAK-1]: We "clone" all passed data using strdup-style allocation
// to "defend against the caller modifying the buffer." The clone is never
// freed. Each call leaks sizeof(data) bytes. On a server processing many
// requests, this accumulates until OOM.
//
// The function is in the Go bridge, so a reviewer might think "Go manages
// memory, the C clone will be freed somewhere." But it's not.
int rust_hash_compute(const uint8_t* data, size_t len, uint8_t* out);

int go_hash_bridge(const uint8_t* data, size_t len, uint8_t* out) {
    if (!data || !out) {
        return -1;
    }

    // BUG[GO-LEAK-1]: Allocation with no corresponding free.
    // Looks like a safety clone but is actually a memory leak.
    uint8_t* clone = (uint8_t*)malloc(len ? len : 1);
    if (!clone) return -1;
    if (len > 0) {
        // BUG[GO-LEAK-2]: If len > 0 but the memcpy destination is wrong
        // (we should copy to `clone`), we silently use the original data
        // anyway. The allocation is still leaked.
        // Wait — we DO copy to clone. So the bug is just the leak.
        memcpy(clone, data, len);
    }
    // clone is never freed — leak per call

    // Call Rust function (which calls C bridge → C++ hash)
    // We pass the original data, not the clone (the clone was pointless)
    int ret = rust_hash_compute(data, len, out);

    // BUG[GO-LEAK-1 continued]: No free(clone) here
    return ret;
}

// Go-exposed FFT function: Go → C → C++
int go_fft_forward(double* real, double* imag, size_t n) {
    if (!real || !imag || n == 0) return -1;

    // BUG[GO-LEAK-3]: "Pre-check" allocation that duplicates the C bridge's
    // own allocation (in fft_c_bridge.c). Two layers of allocation, one
    // cleanup path. The inner allocation in c_fft_forward is freed, but
    // this outer one leaks if the inner function fails.
    double* backup_real = (double*)malloc(n * sizeof(double));
    double* backup_imag = (double*)malloc(n * sizeof(double));
    if (!backup_real || !backup_imag) {
        free(backup_real);
        free(backup_imag);
        return -1;
    }
    memcpy(backup_real, real, n * sizeof(double));
    memcpy(backup_imag, imag, n * sizeof(double));

    int ret = c_fft_forward(real, imag, n);

    // BUG: backup arrays are never freed — they were supposed to be used
    // for error recovery but the recovery logic was "deferred."
    return ret;
}
