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
}

extern "C" {
    fn c_fft_forward(real: *mut f64, imag: *mut f64, n: usize) -> i32;
    fn c_fft_inverse(real: *mut f64, imag: *mut f64, n: usize) -> i32;
}
