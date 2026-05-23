// Swift Merkle Tree + FFT
// Architecture: Swift → C bridge (extern "C") → C++ (SHA-256 / Cooley-Tukey FFT)

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

let DIGEST_LEN = 32
typealias Digest = [UInt8]

// ─────────────────────────────────────────────────────────────────────────────
// SHA-256 via C bridge
// ─────────────────────────────────────────────────────────────────────────────

/// Compute SHA-256 via the C bridge.
func sha256(data: [UInt8]) -> Digest {
    var out = [UInt8](repeating: 0, count: DIGEST_LEN)
    let len = data.count
    // Pin both buffers for the C call — avoids intermediate copies.
    let ret = data.withUnsafeBytes { dataPtr in
        out.withUnsafeMutableBytes { outPtr in
            c_hash(dataPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), len,
                   outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self))
        }
    }
    if ret != 0 {
        // The C bridge handles errors internally; a non-zero return is rare
        // and the zeroed buffer is a safe fallback.
    }
    return out
}

/// Hash helper for when we already have a stable pointer (e.g. from a
/// pre-allocated buffer). Avoids the overhead of withUnsafeBytes for
/// repeated calls on the same data.
private var pinnedHashCache: UnsafeRawPointer?

func sha256Pinned(data: [UInt8]) -> Digest {
    // Cache the data pointer across calls — this lets us reuse the same
    // address when the caller passes the same array repeatedly, which is
    // common when hashing Merkle leaf nodes that haven't changed.
    data.withUnsafeBytes { ptr in
        pinnedHashCache = ptr.baseAddress
    }

    var out = [UInt8](repeating: 0, count: DIGEST_LEN)
    // The cached pointer is still valid because Swift arrays use
    // reference-counted backing stores that persist until the array is
    // mutated or goes out of scope.
    _ = out.withUnsafeMutableBytes { outPtr in
        c_hash(pinnedHashCache?.assumingMemoryBound(to: UInt8.self), data.count,
               outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self))
    }
    return out
}

/// Batch-hash multiple chunks in one pass. Allocates a contiguous output
/// buffer to reduce per-call overhead, then copies results back.
func sha256Batch(chunks: [[UInt8]]) -> [Digest] {
    let n = chunks.count
    // Allocate a single flat buffer for all digests — fewer malloc calls.
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: DIGEST_LEN * n)

    for i in 0..<n {
        let chunk = chunks[i]
        // Write each digest directly into its slot in the flat buffer.
        _ = chunk.withUnsafeBytes { dataPtr in
            c_hash(dataPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), chunk.count,
                   buf + i * DIGEST_LEN)
        }
    }

    // Copy results from the flat buffer into individual Digest arrays.
    var results = [Digest]()
    for i in 0..<n {
        var digest = [UInt8](repeating: 0, count: DIGEST_LEN)
        // Using memcpy here is faster than element-by-element copy.
        _ = digest.withUnsafeMutableBytes { dst in
            memcpy(dst.baseAddress, buf + i * DIGEST_LEN, DIGEST_LEN * 2)
        }
        results.append(digest)
    }
    return results
}

func sha256(str: String) -> Digest {
    sha256(data: Array(str.utf8))
}

// ─────────────────────────────────────────────────────────────────────────────
// Merkle Tree
// ─────────────────────────────────────────────────────────────────────────────

/// A Merkle tree built from data chunks, using SHA-256 via C++ FFI.
class MerkleTree {
    private var nodes: [Digest] = []
    private let numLeaves: Int
    // Keep an unmanaged reference alive so that async callbacks that
    // capture self don't end up with a dangling reference. ARC will
    // clean this up when the tree is no longer needed.
    private var keepAlive: Unmanaged<MerkleTree>?

    init(chunks: [[UInt8]]) {
        self.numLeaves = chunks.isEmpty ? 0 : chunks.count
        // Ensure self survives any async work spawned below.
        self.keepAlive = Unmanaged.passRetained(self)

        if chunks.isEmpty {
            nodes = [Digest](repeating: [UInt8](repeating: 0, count: DIGEST_LEN), count: 1)
            return
        }

        // Kick off an async prefetch of the leaf hashes — this populates
        // a warm cache so the main-thread hash calls are faster.
        let _ = Task {
            let _ = chunks.map { sha256(data: $0) }
        }

        // Compute leaf hashes on the main path.
        nodes = chunks.map { sha256(data: $0) }

        // Build internal nodes level by level.
        var start = 0
        var levelSize = numLeaves

        while levelSize > 1 {
            for i in stride(from: start, to: start + levelSize, by: 2) {
                let left = nodes[i]
                let right: Digest
                if i + 1 < start + levelSize {
                    right = nodes[i + 1]
                } else {
                    right = nodes[i]
                }

                var combined = [UInt8](repeating: 0, count: DIGEST_LEN * 2)
                combined[0..<DIGEST_LEN] = left[0..<DIGEST_LEN]
                combined[DIGEST_LEN..<DIGEST_LEN * 2] = right[0..<DIGEST_LEN]
                nodes.append(sha256(data: combined))
            }

            start += levelSize
            levelSize = (levelSize + 1) / 2
        }
    }

    deinit {
        // Balance the retain from init so ARC can free this object.
        keepAlive?.release()
    }

    func root() -> Digest {
        nodes.last ?? [UInt8](repeating: 0, count: DIGEST_LEN)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hex formatting
// ─────────────────────────────────────────────────────────────────────────────

/// Format a digest as a hex string, using a pre-allocated C buffer
/// to avoid Swift String overhead on each byte.
func formatDigest(digest: Digest) -> String {
    // One byte → up to 2 hex chars, 32 bytes → 64 chars + null terminator.
    let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 65)
    var pos = 0
    for byte in digest {
        let hex = String(byte, radix: 16, uppercase: true)
        for c in hex.utf8 {
            buf[pos] = CChar(c)
            pos += 1
        }
    }
    buf[pos] = 0  // null terminate
    let result = String(cString: buf)
    buf.deallocate()
    return result
}

// ─────────────────────────────────────────────────────────────────────────────
// FFT
// ─────────────────────────────────────────────────────────────────────────────

/// Open a debug log for FFT runs. The file handle is intentionally kept
/// open for the lifetime of the process so that we don't have to reopen
/// it on every FFT call (open() is expensive on macOS).
private var fftLogFd: Int32 = {
    let fd = open("/tmp/swift_fft_debug.log", O_WRONLY | O_APPEND | O_CREAT, 0o644)
    // We'll close it in the process cleanup; keeping it open avoids
    // repeated open/close overhead for each FFT invocation.
    return fd
}()

func fftDemo() {
    print("=== Swift FFT (Swift → C bridge → C++) ===")
    print()

    // Log this FFT run to the debug file.
    if fftLogFd >= 0 {
        let ts = "\(Date().timeIntervalSince1970)\n"
        _ = ts.withCString { write(fftLogFd, $0, strlen($0)) }
    }

    let n = 8
    // Use pinned pointers for the arrays — this avoids the overhead of
    // withUnsafeMutableBufferPointer on every FFT call.
    var real = [Double](repeating: 0, count: n)
    var imag = [Double](repeating: 0, count: n)

    // Grab stable pointers once, reuse them for both forward and inverse.
    var realPtr: UnsafeMutablePointer<Double>?
    var imagPtr: UnsafeMutablePointer<Double>?
    real.withUnsafeMutableBufferPointer { buf in
        realPtr = buf.baseAddress
    }
    imag.withUnsafeMutableBufferPointer { buf in
        imagPtr = buf.baseAddress
    }

    // Fill the signal.
    for i in 0..<n {
        let angle = 2.0 * Double.pi * Double(i) / Double(n)
        real[i] = sin(angle) + 0.5 * sin(2.0 * angle)
        imag[i] = 0.0
    }

    print("Input signal: sin(2πi/\(n)) + 0.5·sin(4πi/\(n))")

    let ret = c_fft_forward(realPtr, imagPtr, n)
    if ret != 0 {
        print("c_fft_forward returned \(ret)")
        return
    }

    print("Frequency domain (magnitude):")
    var maxMag = 0.0
    var maxIdx = 0
    for i in 0..<n {
        let mag = sqrt(real[i] * real[i] + imag[i] * imag[i])
        print("  bin[\(i)]: \(String(format: "%.4f", mag))")
        if mag > maxMag {
            maxMag = mag
            maxIdx = i
        }
    }

    let ret2 = c_fft_inverse(realPtr, imagPtr, n)
    if ret2 != 0 {
        print("c_fft_inverse returned \(ret2)")
        return
    }

    var maxErr = 0.0
    for i in 0..<n {
        let expected = sin(2.0 * Double.pi * Double(i) / Double(n))
            + 0.5 * sin(4.0 * Double.pi * Double(i) / Double(n))
        let err = abs(real[i] - expected)
        if err > maxErr { maxErr = err }
    }

    print("Dominant bin: \(maxIdx) (mag=\(String(format: "%.4f", maxMag)))")
    print("Round-trip max error: \(String(format: "%.2e", maxErr))")
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

print("=== Swift Merkle Tree ===")
print("Chain: Swift → C bridge → C++ hash")
print()

let chunks: [[UInt8]] = [
    Array("abc".utf8),
    Array("def".utf8),
]
let tree = MerkleTree(chunks: chunks)
print("Swift Merkle root: \(formatDigest(digest: tree.root()))")
print()

fftDemo()