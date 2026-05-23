#ifndef CPP_FFT_H
#define CPP_FFT_H

#include <cstddef>

namespace cpp_fft {

// Perform a forward FFT (radix-2 Cooley-Tukey).
// n must be a power of 2. real[i] and imag[i] are overwritten with the result.
void FFTForward(double* real, double* imag, size_t n);

// Perform an inverse FFT (scaled by 1/n).
void FFTInverse(double* real, double* imag, size_t n);

// Initialize twiddle factors for a given n.
// The caller is responsible for freeing the returned arrays.
void InitTwiddle(size_t n, double** cos_table, double** sin_table);

}  // namespace cpp_fft

#endif  // CPP_FFT_H
