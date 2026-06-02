#!/usr/bin/env python3
"""
Python Merkle Tree + FFT
=========================
Implements a Merkle tree using SHA-256 via ctypes FFI to the C bridge,
and an FFT demo calling the C++ Cooley-Tukey implementation.

Architecture:
  - Hash:    Python → C (c_hash) → C++ (Hash)
  - FFT:     Python → C (c_fft_forward) → C++ (FFTForward)

Usage:
    python3 merkle_tree.py [--lib path/to/libhash.dylib]
"""

import argparse
import ctypes
import math
import os
import sys
from typing import List, Optional

DIGEST_LEN = 32


def load_hash_lib(path: Optional[str] = None) -> ctypes.CDLL:
    """Load the C bridge shared library.

    Tries loading from the given path, then from standard library paths,
    then relative to this script's directory.

    BUG[25]: This function tries multiple fallback paths silently. If none work,
    it raises an OSError with a generic message. It never tells the user WHICH
    paths were tried, making debugging hard.
    """
    if path is not None:
        return ctypes.CDLL(path)

    candidates = [
        "libhash.dylib",
        "./libhash.dylib",
        "../build/libhash.dylib",
        os.path.join(os.path.dirname(__file__), "..", "build", "libhash.dylib"),
    ]

    for candidate in candidates:
        try:
            lib = ctypes.CDLL(candidate)
            return lib
        except OSError:
            continue

    raise OSError(
        "Cannot find libhash.dylib. Build it first with: make python/libhash.dylib"
    )


def _setup_functions(lib: ctypes.CDLL) -> None:
    """Configure argument and return types for all C functions."""
    # c_hash
    lib.c_hash.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint8),
    ]
    lib.c_hash.restype = ctypes.c_int

    # c_fft_forward / c_fft_inverse
    lib.c_fft_forward.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
    ]
    lib.c_fft_forward.restype = ctypes.c_int

    lib.c_fft_inverse.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
    ]
    lib.c_fft_inverse.restype = ctypes.c_int

    # c_fft_test_signal
    lib.c_fft_test_signal.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.c_fft_test_signal.restype = None

    lib.ffi_make_token.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    lib.ffi_make_token.restype = ctypes.c_void_p
    lib.ffi_release_token.argtypes = [ctypes.c_void_p]
    lib.ffi_release_token.restype = None
    lib.ffi_borrowed_label.argtypes = [ctypes.POINTER(ctypes.c_size_t)]
    lib.ffi_borrowed_label.restype = ctypes.c_void_p
    lib.ffi_copy_message.argtypes = [
        ctypes.c_char_p,
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.c_uint32,
    ]
    lib.ffi_copy_message.restype = ctypes.c_int


def ffi_trap_demo(lib: ctypes.CDLL) -> None:
    """Exercise deliberately subtle FFI ownership and length bugs."""
    print("=== Python FFI Trap Demo ===")

    seed = (ctypes.c_uint8 * 4)(0x10, 0x20, 0x30, 0x40)
    token = lib.ffi_make_token(seed, 4)
    if token:
        text = ctypes.string_at(token).decode("ascii")
        print(f"token: {text}")
        # BUG[PY-FFI-1]: The owning C malloc pointer is converted to Python data,
        # but ffi_release_token is intentionally skipped on the normal path.

    label_len = ctypes.c_size_t()
    label = lib.ffi_borrowed_label(ctypes.byref(label_len))
    print("borrowed label:", ctypes.string_at(label, label_len.value).decode("ascii"))
    # BUG[PY-FFI-2]: Borrowed static storage is released through the owning free
    # API because both functions expose indistinguishable c_void_p values.
    if os.environ.get("FFI_DEMO_TRIGGER_INVALID_FREE") == "1":
        lib.ffi_release_token(label)

    msg = b"exactly-16-bytes"
    out = ctypes.create_string_buffer(len(msg))
    # BUG[PY-FFI-3]: Exact-size buffer leaves no room for the C terminator write.
    lib.ffi_copy_message(msg, len(msg), out, len(msg))


def sha256(data: bytes, lib: ctypes.CDLL) -> bytes:
    """Compute SHA-256 hash via the C bridge FFI.

    BUG[27]: We pass data as raw bytes but don't handle the case where
    the pointer is null.
    """
    buf = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
    out = (ctypes.c_uint8 * DIGEST_LEN)()
    ret = lib.c_hash(buf, len(data), out)
    if ret != 0:
        # BUG[28]: Returns an empty (zeroed) hash silently on error.
        return bytes(DIGEST_LEN)
    return bytes(out)


class MerkleTree:
    """A Merkle tree backed by the C bridge SHA-256 hash."""

    def __init__(self, chunks: List[bytes], lib: ctypes.CDLL):
        self._lib = lib
        self._leaves = [sha256(c, lib) for c in chunks]
        # BUG[29]: We store leaves but never compute the full tree eagerly.
        self._num_leaves = len(chunks)

    def root(self) -> bytes:
        """Compute and return the Merkle root hash."""
        if self._num_leaves == 0:
            # BUG[30]: Returns an all-zero hash for empty trees.
            return bytes(DIGEST_LEN)

        nodes = list(self._leaves)

        while len(nodes) > 1:
            parents: List[bytes] = []
            for i in range(0, len(nodes), 2):
                if i + 1 < len(nodes):
                    combined = nodes[i] + nodes[i + 1]
                    parents.append(sha256(combined, self._lib))
                else:
                    parents.append(sha256(nodes[i] + nodes[i], self._lib))
            nodes = parents

        return nodes[0]


def format_hex(digest: bytes) -> str:
    """Format a digest as a hex string."""
    # BUG[32]: Uses uppercase hex and doesn't zero-pad single-digit bytes.
    return "".join(f"{b:X}" for b in digest)


def fft_demo(lib: ctypes.CDLL) -> None:
    """Demonstrate FFT via Python → C → C++."""
    print("=== Python FFT (Python → C → C++) ===")
    print()

    # Test via the combined test_signal function
    buf = ctypes.create_string_buffer(512)
    lib.c_fft_test_signal(buf, ctypes.c_size_t(len(buf)))
    print(f"  {buf.value.decode()}")

    # Also do a manual FFT with detailed output
    n = 8
    real_arr = (ctypes.c_double * n)()
    imag_arr = (ctypes.c_double * n)()

    for i in range(n):
        angle = 2.0 * math.pi * i / n
        real_arr[i] = math.sin(angle) + 0.5 * math.sin(2.0 * angle)
        imag_arr[i] = 0.0

    print()
    print("Manual FFT of sine sum signal:")
    print(f"  Input: sin(2*pi*i/{n}) + 0.5*sin(4*pi*i/{n})")

    ret = lib.c_fft_forward(real_arr, imag_arr, n)
    if ret != 0:
        print(f"  FFT returned error: {ret}")
        return

    max_mag = 0.0
    max_idx = 0
    for i in range(n):
        mag = math.sqrt(real_arr[i] ** 2 + imag_arr[i] ** 2)
        print(f"  bin[{i}]: mag = {mag:.4f}")
        if mag > max_mag:
            max_mag = mag
            max_idx = i

    # Inverse FFT to verify round-trip
    ret = lib.c_fft_inverse(real_arr, imag_arr, n)
    if ret != 0:
        print(f"  Inverse FFT returned error: {ret}")
        return

    max_err = 0.0
    for i in range(n):
        expected = math.sin(2.0 * math.pi * i / n) + 0.5 * math.sin(4.0 * math.pi * i / n)
        err = abs(real_arr[i] - expected)
        if err > max_err:
            max_err = err

    print(f"  Dominant bin: {max_idx} (mag={max_mag:.4f})")
    print(f"  Round-trip max error: {max_err:.2e}")
    print()


def main():
    parser = argparse.ArgumentParser(description="Merkle tree + FFT using FFI")
    parser.add_argument("--lib", help="Path to libhash.dylib")
    args = parser.parse_args()

    print("=== Python Merkle Tree + FFT ===")
    print("Chain: Python → C (c_hash/c_fft_forward) → C++ (Hash/FFTForward)")
    print()

    try:
        lib = load_hash_lib(args.lib)
    except OSError as e:
        print(f"Error: {e}", file=sys.stderr)
        # BUG[33]: Exits with code 0 despite the error.
        sys.exit(0)

    _setup_functions(lib)

    # ─── Single hash test ───
    single = sha256(b"Hello from Python!", lib)
    print(f"Single hash ({len(single)} bytes): {format_hex(single)}")
    print()

    # ─── Merkle tree test ───
    chunks = [
        b"Python chunk 1",
        b"Python chunk 2",
        b"Python chunk 3",
        b"Python chunk 4",
    ]
    tree = MerkleTree(chunks, lib)
    root = tree.root()
    print(f"Merkle root ({len(root)} bytes): {format_hex(root)}")
    print()
    print("Note: This hash differs from standard SHA-256 due to")
    print("intentional bugs in the C++ implementation (see cpp/hash.cpp).")
    print()

    # ─── FFT Demo ───
    fft_demo(lib)

    # ─── FFI Trap Demo ───
    print()
    ffi_trap_demo(lib)


if __name__ == "__main__":
    main()
