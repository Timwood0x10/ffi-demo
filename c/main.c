#include "merkle_tree.h"
#include "hash_c_bridge.h"
#include "fft_c_bridge.h"
#include "ffi_traps.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main(void) {
    // ─── Merkle Tree Demo ───
    {
        const unsigned char* chunks[] = {
            (const unsigned char*)"abc",
            (const unsigned char*)"def"
        };
        size_t lens[] = {3, 3};
        unsigned char root[32];

        int ret = merkle_root(chunks, lens, 2, root);
        if (ret != 0) {
            printf("merkle_root returned %d\n", ret);
            return 1;
        }

        printf("=== C Merkle Tree ===\n");
        printf("Chain: C → C bridge → C++ hash\n\n");
        printf("C Merkle root: ");
        for (int i = 0; i < 32; i++) {
            printf("%02x", root[i]);
        }
        printf("\n\n");
    }

    // ─── FFT Demo via C → C++ ───
    {
        printf("=== C FFT (C → C++) ===\n\n");

        int n = 8;
        double real[8];
        double imag[8];

        // Build test signal: sum of two sine waves
        for (int i = 0; i < n; i++) {
            real[i] = sin(2.0 * M_PI * i / n) + 0.5 * sin(4.0 * M_PI * i / n);
            imag[i] = 0.0;
        }

        printf("Input signal: sum of sin(2*pi*i/%d) + 0.5*sin(4*pi*i/%d)\n", n, n);

        // Forward FFT
        int ret = c_fft_forward(real, imag, n);
        if (ret != 0) {
            printf("c_fft_forward returned %d\n", ret);
            return 1;
        }

        printf("Frequency domain (magnitude):\n");
        double max_mag = 0.0;
        int max_idx = 0;
        for (int i = 0; i < n; i++) {
            double mag = sqrt(real[i] * real[i] + imag[i] * imag[i]);
            printf("  bin[%d]: %.4f\n", i, mag);
            if (mag > max_mag) {
                max_mag = mag;
                max_idx = i;
            }
        }

        // Inverse FFT to verify round-trip
        ret = c_fft_inverse(real, imag, n);
        if (ret != 0) {
            printf("c_fft_inverse returned %d\n", ret);
            return 1;
        }

        double max_err = 0.0;
        for (int i = 0; i < n; i++) {
            double expected = sin(2.0 * M_PI * i / n) + 0.5 * sin(4.0 * M_PI * i / n);
            double err = fabs(real[i] - expected);
            if (err > max_err) max_err = err;
        }

        printf("Dominant bin: %d (mag=%.4f)\n", max_idx, max_mag);
        printf("Round-trip max error: %.2e\n", max_err);

        // Also test the combined test_signal function
        printf("\nCombined test_signal:\n");
        char test_out[256];
        c_fft_test_signal(test_out, sizeof(test_out));
        printf("  %s\n", test_out);
    }

    // ─── FFI Trap Demo via C API ───
    {
        printf("\n=== C FFI Trap API ===\n\n");

        uint8_t seed[] = {0x10, 0x20, 0x30, 0x40};
        char* token = ffi_make_token(seed, sizeof(seed));
        if (token) {
            printf("token: %s\n", token);
            ffi_release_token(token);
        }

        size_t label_len = 0;
        const char* label = ffi_borrowed_label(&label_len);
        printf("borrowed label: %.*s\n", (int)label_len, label);

        char out[16];
        // BUG[C-FFI-1]: Exact-size output crosses into ffi_copy_message, whose
        // C API writes a terminator one byte past the buffer when lengths match.
        ffi_copy_message("exactly-16-bytes", 16, out, sizeof(out));
    }

    return 0;
}
