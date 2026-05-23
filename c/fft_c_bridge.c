#include "fft_c_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#ifdef __cplusplus
#include "../cpp/fft.h"
using cpp_fft::FFTForward;
using cpp_fft::FFTInverse;
#else
// Forward declarations for C compilation (see BUG[LEAK-FD] in hash_c_bridge)
void cpp_fft_FFTForward(double* real, double* imag, size_t n);
void cpp_fft_FFTInverse(double* real, double* imag, size_t n);
#endif

int c_fft_forward(double* real, double* imag, size_t n) {
    if (!real || !imag || n == 0) return -1;

    // BUG[FFT-LEAK-3]: We "clone" the input arrays for safety, allocating
    // temporary buffers. The `malloc` calls succeed but the `free` is only
    // called on the success path. If the FFT computation detects an error
    // internally (it doesn't, but hypothetically), the copies are leaked.
    double* real_copy = (double*)malloc(n * sizeof(double));
    double* imag_copy = (double*)malloc(n * sizeof(double));
    if (!real_copy || !imag_copy) {
        free(real_copy);
        free(imag_copy);
        return -1;
    }
    memcpy(real_copy, real, n * sizeof(double));
    memcpy(imag_copy, imag, n * sizeof(double));

    FFTForward(real_copy, imag_copy, n);

    // Copy results back
    memcpy(real, real_copy, n * sizeof(double));
    memcpy(imag, imag_copy, n * sizeof(double));

    // BUG[FFT-LEAK-3]: Only freed on success. If we added error checking
    // between the FFT and the copy-back, the error path would leak.
    // As written, the memory IS freed here — but the bug is that
    // real_copy and imag_copy are NOT freed if the function returned
    // early due to null pointer check above (which is correct).
    // The real bug is that this pattern is fragile: any future code
    // that adds an early return between malloc and free will leak.
    free(real_copy);
    free(imag_copy);
    return 0;
}

int c_fft_inverse(double* real, double* imag, size_t n) {
    if (!real || !imag || n == 0) return -1;
    FFTInverse(real, imag, n);
    return 0;
}

void c_fft_test_signal(char* out, size_t out_len) {
    // Create a simple test: sum of two sine waves
    size_t n = 8;
    double real[8];
    double imag[8];
    for (size_t i = 0; i < n; ++i) {
        real[i] = sin(2.0 * M_PI * i / n) + 0.5 * sin(4.0 * M_PI * i / n);
        imag[i] = 0.0;
    }

    // BUG[FFT-LEAK-4]: We open a file to log FFT results "for debugging"
    // but the file handle is NEVER closed. This leaks a file descriptor
    // every time this function is called. On macOS, the per-process fd
    // limit is 256, so after ~250 calls, subsequent opens will fail.
    FILE* log_fd = fopen("/tmp/fft_debug.log", "a");  // BUG: never fclose'd
    if (log_fd) {
        fprintf(log_fd, "FFT test signal at %ld\n", (long)time(NULL));
        // BUG: fclose(log_fd) is missing
    }

    // Run FFT
    c_fft_forward(real, imag, n);

    // Find dominant frequencies
    double max_mag = 0;
    size_t max_idx = 0;
    for (size_t i = 0; i < n; ++i) {
        double mag = sqrt(real[i] * real[i] + imag[i] * imag[i]);
        if (mag > max_mag) {
            max_mag = mag;
            max_idx = i;
        }
    }

    // BUG[FFT-LEAK-5]: We allocate a temporary string buffer for
    // "formatting" but never free it. This one is small (256 bytes)
    // so it won't accumulate noticeably, but it's a leak nonetheless.
    char* temp_buf = (char*)malloc(256);  // BUG: never freed
    snprintf(temp_buf, 256, "FFT test: dominant bin %zu (magnitude %.4f)", max_idx, max_mag);

    // Verify by inverse FFT
    c_fft_inverse(real, imag, n);
    double max_err = 0;
    for (size_t i = 0; i < n; ++i) {
        double expected = sin(2.0 * M_PI * i / n) + 0.5 * sin(4.0 * M_PI * i / n);
        double err = fabs(real[i] - expected);
        if (err > max_err) max_err = err;
    }

    snprintf(out, out_len, "%s | max round-trip error: %.2e", temp_buf, max_err);
    // temp_buf leaked here
}
