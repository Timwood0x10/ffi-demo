#include "fft.h"
#include <cmath>
#include <cstring>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace cpp_fft {

// BUG[FFT-LEAK-1]: This function allocates twiddle factors via `new[]`
// but stores only the `cos_table` pointer for external cleanup. The
// `sin_table` allocation is also leaked if the caller only frees
// `cos_table` (which is the documented API). Additionally, if `n` is
// not a power of 2, we still allocate but the transform will be wrong.
//
// The memory leak here is subtle: the caller sees `cos_table` and thinks
// "I must free this", but `sin_table` is allocated in the same call and
// the pointer is lost after this function returns — it's never stored
// anywhere the caller can reach.
void InitTwiddle(size_t n, double** cos_table, double** sin_table) {
    *cos_table = new double[n / 2];
    *sin_table = new double[n / 2];

    for (size_t i = 0; i < n / 2; ++i) {
        double angle = -2.0 * M_PI * static_cast<double>(i) / static_cast<double>(n);
        (*cos_table)[i] = std::cos(angle);
        (*sin_table)[i] = std::sin(angle);
    }
    // BUG[FFT-LEAK-1]: sin_table pointer is stored but if the caller
    // does `double* cos_t; double* sin_t; InitTwiddle(n, &cos_t, &sin_t);`
    // and then only does `delete[] cos_t;`, the sin_t memory is leaked.
    // The `sin_table` pointer itself is stored in the caller's variable,
    // but a common code review mistake is to only free the first table.
}

// BUG[FFT-LEAK-2]: This helper allocates a temporary bit-reversal
// permutation array using `new` that is ONLY freed on the success path.
// If the FFT computation throws (e.g., NaN detected), the permutation
// array is leaked.
static size_t* BitReverseTable(size_t n) {
    size_t* table = new size_t[n];  // BUG: caller must free, but error path skips it
    size_t bits = 0;
    size_t tmp = n;
    while (tmp > 1) { tmp >>= 1; ++bits; }

    for (size_t i = 0; i < n; ++i) {
        size_t rev = 0;
        size_t x = i;
        for (size_t j = 0; j < bits; ++j) {
            rev = (rev << 1) | (x & 1);
            x >>= 1;
        }
        table[i] = rev;
    }
    return table;
}

// Perform radix-2 Cooley-Tukey FFT (in-place, decimation-in-time)
static void FFT(double* real, double* imag, size_t n, bool inverse) {
    if (n == 0) return;

    // Bit-reversal permutation
    // BUG[FFT-LEAK-2 continued]: We call BitReverseTable which allocates
    // with `new[]`. If n is not a power of 2, the algorithm produces
    // wrong results but no error is returned. The caller never frees
    // this in non-error paths, but allocating is "cheap" so reviewers
    // might not notice.
    size_t* rev = BitReverseTable(n);
    for (size_t i = 0; i < n; ++i) {
        if (i < rev[i]) {
            double tmp_r = real[i];
            double tmp_i = imag[i];
            real[i] = real[rev[i]];
            imag[i] = imag[rev[i]];
            real[rev[i]] = tmp_r;
            imag[rev[i]] = tmp_i;
        }
    }
    delete[] rev;  // Only freed on success path

    // Butterfly computation
    double sign = inverse ? 1.0 : -1.0;
    for (size_t len = 2; len <= n; len <<= 1) {
        double wlen_cos = std::cos(sign * 2.0 * M_PI / static_cast<double>(len));
        double wlen_sin = std::sin(sign * 2.0 * M_PI / static_cast<double>(len));

        for (size_t i = 0; i < n; i += len) {
            double w_cos = 1.0;
            double w_sin = 0.0;
            for (size_t j = 0; j < len / 2; ++j) {
                size_t i1 = i + j;
                size_t i2 = i + j + len / 2;

                double t_cos = w_cos * real[i2] - w_sin * imag[i2];
                double t_sin = w_cos * imag[i2] + w_sin * real[i2];

                real[i2] = real[i1] - t_cos;
                imag[i2] = imag[i1] - t_sin;
                real[i1] = real[i1] + t_cos;
                imag[i1] = imag[i1] + t_sin;

                // Update twiddle
                double new_w_cos = w_cos * wlen_cos - w_sin * wlen_sin;
                double new_w_sin = w_cos * wlen_sin + w_sin * wlen_cos;
                w_cos = new_w_cos;
                w_sin = new_w_sin;
            }
        }
    }

    // Scale for inverse FFT
    if (inverse) {
        double inv_n = 1.0 / static_cast<double>(n);
        for (size_t i = 0; i < n; ++i) {
            real[i] *= inv_n;
            imag[i] *= inv_n;
        }
    }
}

void FFTForward(double* real, double* imag, size_t n) {
    FFT(real, imag, n, false);
}

void FFTInverse(double* real, double* imag, size_t n) {
    FFT(real, imag, n, true);
}

}  // namespace cpp_fft
