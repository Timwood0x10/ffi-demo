// C# / .NET FFI Demo — P/Invoke Memory Safety Bugs
//
// Architecture: C# (NativeAOT) → C bridge → C++ (SHA-256 / FFT)
//
// BUG annotations follow the same convention as other ffi-demo modules.
// Each bug is prefixed with BUG[N] and classified by CWE.
//
// Build: dotnet publish -r <rid> -p:PublishAot=true
//       or: clang -S -emit-llvm (for .c simulation)

using System;
using System.Runtime.InteropServices;

// ─────────────────────────────────────────────────────────────────────────────
// P/Invoke declarations — unmanaged memory interop
// ─────────────────────────────────────────────────────────────────────────────

public static class NativeMethods {
    // C library functions
    [DllImport("libc", EntryPoint = "malloc")]
    public static extern IntPtr Malloc(ulong size);

    [DllImport("libc", EntryPoint = "free")]
    public static extern void Free(IntPtr ptr);

    // C bridge functions
    [DllImport("libhash_bridge", CallingConvention = CallingConvention.Cdecl)]
    public static extern int c_hash(IntPtr data, ulong len, IntPtr out_buf);

    // C++ functions
    [DllImport("libcpp_fft", CallingConvention = CallingConvention.Cdecl)]
    public static extern int c_fft_forward(IntPtr real, IntPtr imag, int n);
}

// ─────────────────────────────────────────────────────────────────────────────
// CS-BUG[1]: C malloc → Marshal.FreeHGlobal (CWE-763)
//   C allocates via malloc(), C# frees with wrong deallocator.
//   Expected: cross_language_free
// ─────────────────────────────────────────────────────────────────────────────

public class CrossLanguageFreeDemo {
    // Simulated C alloc — in real NativeAOT this comes from a DllImport
    private static IntPtr CAlloc() => NativeMethods.Malloc(1024);

    public static unsafe void Run() {
        IntPtr buf = CAlloc();
        if (buf == IntPtr.Zero) return;

        // Use the buffer
        byte* p = (byte*)buf;
        for (int i = 0; i < 1024; i++) p[i] = 0xAB;

        // BUG[1]: freeing C malloc'd memory with Marshal.FreeHGlobal
        // Should use NativeMethods.Free(buf) instead
        Marshal.FreeHGlobal(buf); // CWE-763: mismatched allocator
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CS-BUG[2]: Marshal.AllocHGlobal leak (CWE-401)
//   P/Invoke allocated memory never freed.
//   Expected: memory_leak
// ─────────────────────────────────────────────────────────────────────────────

public class MemoryLeakDemo {
    public static unsafe void Run() {
        // Allocate unmanaged memory via P/Invoke
        IntPtr data = Marshal.AllocHGlobal(2048);
        if (data == IntPtr.Zero) return;

        // Use it
        byte* p = (byte*)data;
        for (int i = 0; i < 2048; i++) p[i] = (byte)(i & 0xFF);

        // BUG[2]: forgot Marshal.FreeHGlobal(data) — leaked 2KB
        // Function returns without freeing
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CS-BUG[3]: CoTaskMemAlloc → free() (CWE-763)
//   COM interop allocator freed with CRT free().
//   Expected: cross_language_free
// ─────────────────────────────────────────────────────────────────────────────

public class ComInteropBugDemo {
    public static unsafe void Run() {
        // COM interop allocation
        IntPtr comBuf = CoTaskMemAlloc(512);
        if (comBuf == IntPtr.Zero) return;

        byte* p = (byte*)comBuf;
        for (int i = 0; i < 512; i++) p[i] = 0x42;

        // BUG[3]: using CRT free() on COM-allocated memory
        // Should use CoTaskMemFree(comBuf)
        NativeMethods.Free(comBuf); // CWE-763
    }

    [DllImport("ole32", EntryPoint = "CoTaskMemAlloc")]
    private static extern IntPtr CoTaskMemAlloc(ulong cb);
}

// ─────────────────────────────────────────────────────────────────────────────
// CS-BUG[4]: Double FreeHGlobal (CWE-415 / CWE-416)
//   Same buffer freed twice via P/Invoke.
//   Expected: double_free or invalid_free
// ─────────────────────────────────────────────────────────────────────────────

public class DoubleFreeDemo {
    public static unsafe void Run() {
        IntPtr buf = Marshal.AllocHGlobal(256);
        if (buf == IntPtr.Zero) return;

        byte* p = (byte*)buf;
        // Write sensitive data
        string s = "password123";
        for (int i = 0; i < s.Length && i < 256; i++)
            p[i] = (byte)s[i];

        // First free — correct
        Marshal.FreeHGlobal(buf);

        // BUG[4]: double free — UAF if memory reused
        Marshal.FreeHGlobal(buf); // CWE-415
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAFE: Correct AllocHGlobal/FreeHGlobal pair
//   Expected: no issue (or suppressed as safe pattern)
// ─────────────────────────────────────────────────────────────────────────────

public class SafeCorrectPairDemo {
    public static unsafe void Run() {
        IntPtr buf = Marshal.AllocHGlobal(320);
        if (buf == IntPtr.Zero) return;

        byte* p = (byte*)buf;
        for (int i = 0; i < 320; i++) p[i] = 0;

        // Correct: matching allocator/deallocator pair
        Marshal.FreeHGlobal(buf);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main entry point
// ─────────────────────────────────────────────────────────────────────────────

class Program {
    static int Main(string[] args) {
        Console.WriteLine("=== C# FFI Memory Safety Demo ===");
        Console.WriteLine("Chain: C# (NativeAOT) → C bridge → C++");
        Console.WriteLine();

        Console.WriteLine("--- CS-BUG[1] Cross-language free ---");
        CrossLanguageFreeDemo.Run();

        Console.WriteLine("--- CS-BUG[2] Memory leak ---");
        MemoryLeakDemo.Run();

        Console.WriteLine("--- CS-BUG[3] COM interop mismatch ---");
        ComInteropBugDemo.Run();

        Console.WriteLine("--- CS-BUG[4] Double FreeHGlobal ---");
        DoubleFreeDemo.Run();

        Console.WriteLine("--- SAFE: Correct pair ---");
        SafeCorrectPairDemo.Run();

        Console.WriteLine("Done.");
        return 0;
    }
}
