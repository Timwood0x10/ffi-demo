fn main() {
    // ─── Merkle Tree Demo ───
    let tree = rust_merkle::MerkleTree::new(&[b"hello", b"world", b"from", b"rust"]);
    println!("Rust Merkle root: {}", rust_merkle::format_digest(tree.root()));

    // ─── FFT Demo via Rust→C→C++ ───
    println!();
    println!("FFT via Rust → C bridge → C++:");

    // Build a simple test signal: sum of two sine waves
    let n: usize = 8;
    let mut real: Vec<f64> = (0..n)
        .map(|i| {
            let angle = 2.0 * std::f64::consts::PI * i as f64 / n as f64;
            angle.sin() + 0.5 * (2.0 * angle).sin()
        })
        .collect();
    let mut imag: Vec<f64> = vec![0.0; n];

    // Call FFT via the C bridge's extern "C" function
    unsafe {
        let ret = c_fft_forward(real.as_mut_ptr(), imag.as_mut_ptr(), n);
        println!("  FFT returned: {}", if ret == 0 { "OK" } else { "FAIL" });
        println!("  Frequency domain (magnitude):");
        for i in 0..n {
            let mag = (real[i] * real[i] + imag[i] * imag[i]).sqrt();
            println!("    bin[{}]: {:.4}", i, mag);
        }

        // Inverse FFT to verify round-trip
        let ret2 = c_fft_inverse(real.as_mut_ptr(), imag.as_mut_ptr(), n);
        let expected: Vec<f64> = (0..n)
            .map(|i| {
                let angle = 2.0 * std::f64::consts::PI * i as f64 / n as f64;
                angle.sin() + 0.5 * (2.0 * angle).sin()
            })
            .collect();
        let max_err: f64 = (0..n)
            .map(|i| (real[i] - expected[i]).abs())
            .fold(0.0_f64, f64::max);
        println!("  Round-trip max error: {:.2e}", max_err);
        println!("  Inverse FFT returned: {}", if ret2 == 0 { "OK" } else { "FAIL" });
    }

    ffi_trap_demo();
}

fn ffi_trap_demo() {
    println!();
    println!("Rust FFI trap demo:");

    let seed = [0x10_u8, 0x20, 0x30, 0x40];
    unsafe {
        let token = ffi_make_token(seed.as_ptr(), seed.len());
        if !token.is_null() {
            println!("  token ptr: {:?}", token);
            // BUG[RUST-FFI-1]: The C allocation is adopted by CString::from_raw,
            // then also released through the C API, producing allocator/ownership
            // confusion that is split across two safe-looking cleanup calls.
            let _owned = std::ffi::CString::from_raw(token);
            if std::env::var_os("FFI_DEMO_TRIGGER_INVALID_FREE").is_some() {
                ffi_release_token(token);
            }
        }

        let mut label_len = 0usize;
        let label = ffi_borrowed_label(&mut label_len as *mut usize);
        println!("  borrowed label len: {}", label_len);
        // BUG[RUST-FFI-2]: A borrowed static pointer is cast to mut and sent to
        // the owning release API because the C surface does not encode ownership.
        if std::env::var_os("FFI_DEMO_TRIGGER_INVALID_FREE").is_some() {
            ffi_release_token(label as *mut i8);
        }

        let msg = b"exactly-16-bytes";
        let mut out = vec![0_i8; msg.len()];
        // BUG[RUST-FFI-3]: usize is narrowed to u32 and the exact-size Vec leaves
        // no room for C's hidden NUL terminator write.
        let _ = ffi_copy_message(
            msg.as_ptr() as *const i8,
            msg.len() as u32,
            out.as_mut_ptr(),
            out.len() as u32,
        );
    }
}

extern "C" {
    fn c_fft_forward(real: *mut f64, imag: *mut f64, n: usize) -> i32;
    fn c_fft_inverse(real: *mut f64, imag: *mut f64, n: usize) -> i32;
    fn ffi_make_token(seed: *const u8, len: usize) -> *mut i8;
    fn ffi_release_token(token: *mut i8);
    fn ffi_borrowed_label(out_len: *mut usize) -> *const i8;
    fn ffi_copy_message(message: *const i8, len: u32, out: *mut i8, out_len: u32) -> i32;
}
