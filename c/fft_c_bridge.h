#ifndef C_FFT_C_BRIDGE_H
#define C_FFT_C_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * c_fft_forward - Compute forward FFT via C++ implementation.
 * n must be a power of 2. Arrays real and imag are modified in-place.
 * Returns 0 on success.
 */
int c_fft_forward(double* real, double* imag, size_t n);

/**
 * c_fft_inverse - Compute inverse FFT via C++ implementation.
 * n must be a power of 2. Arrays real and imag are modified in-place.
 * Returns 0 on success.
 */
int c_fft_inverse(double* real, double* imag, size_t n);

/**
 * c_fft_test_signal - Create a simple test signal and run FFT round-trip.
 * Fills `out` with a human-readable string describing the result.
 * out_len is the buffer size.
 */
void c_fft_test_signal(char* out, size_t out_len);

#ifdef __cplusplus
}
#endif

#endif  // C_FFT_C_BRIDGE_H
