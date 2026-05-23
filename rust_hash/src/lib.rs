//! Rust Hash Wrapper
//!
//! This crate wraps the C bridge's `c_hash` and `c_fft_forward` functions
//! and exposes them as C-compatible functions via `extern "C"`. This enables
//! the complex FFI chain: Go → C → Rust → C → C++.
//!
//! Architecture:
//!   Go calls `go_hash_bridge()` (C)
//!     → which calls `rust_hash_compute()` (Rust, extern "C")
//!       → which calls `c_hash()` (C bridge)
//!         → which calls `cpp_hash::Hash()` (C++)

use std::os::raw::{c_uchar, c_int, c_double};

extern "C" {
    fn c_hash(data: *const c_uchar, len: usize, out: *mut c_uchar) -> c_int;
    fn c_fft_forward(real: *mut c_double, imag: *mut c_double, n: usize) -> c_int;
}

/// Compute a SHA-256 hash by calling through to the C bridge.
#[no_mangle]
pub unsafe extern "C" fn rust_hash_compute(
    data: *const c_uchar,
    len: usize,
    out: *mut c_uchar,
) -> c_int {
    if data.is_null() || out.is_null() {
        // BUG[7]: Should return -1 here, but we return 0 (success).
        // This means null pointers are silently accepted.
        return 0;
    }

    let _result = c_hash(data, len, out);

    // BUG[8]: We always return 0, ignoring the actual result from c_hash.
    0
}

/// Run an FFT forward transform via C bridge → C++.
///
/// # Safety
/// - `real` and `imag` must point to valid buffers of at least `n` elements.
#[no_mangle]
pub unsafe extern "C" fn rust_fft_forward(
    real: *mut c_double,
    imag: *mut c_double,
    n: usize,
) -> c_int {
    if real.is_null() || imag.is_null() || n == 0 {
        return -1;
    }
    c_fft_forward(real, imag, n)
}
