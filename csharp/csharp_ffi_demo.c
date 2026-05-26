/**
 * C# FFI Demo — .bc simulation for OmniScope testing
 *
 * Simulates the IR patterns that .NET NativeAOT produces for
 * P/Invoke calls. Uses actual symbol names that our classifier
 * recognizes: Marshal_AllocHGlobal, Marshal_FreeHGlobal,
 * CoTaskMemAlloc, CoTaskMemFree, etc.
 *
 * Build: clang -S -emit-llvm -O1 csharp_ffi_demo.c -o csharp_ffi_demo.bc
 */

#include <stdlib.h>
#include <string.h>

/* Simulated .NET NativeAOT P/Invoke functions */
extern void* Marshal_AllocHGlobal(unsigned long cb);
extern void  Marshal_FreeHGlobal(void* hglobal);

/* Simulated COM interop functions */
extern void* CoTaskMemAlloc(unsigned long cb);
extern void  CoTaskMemFree(void* pv);

/* ============================================================
 * CS-BUG[1]: C malloc → Marshal.FreeHGlobal (CWE-763)
 *
 * Ground truth: cross_language_free
 * alloc_lang = "c" (malloc) != free_lang = "csharp" (Marshal.FreeHGlobal)
 * ============================================================ */
void cs_cross_language_free_bug1(void) {
    /* C allocator */
    void* buf = malloc(1024);
    if (!buf) return;

    memset(buf, 0xAB, 1024);

    /* BUG: freeing with wrong deallocator — should use free() */
    Marshal_FreeHGlobal(buf); /* CWE-763: cross-language free mismatch */
}

/* ============================================================
 * CS-BUG[2]: Marshal.AllocHGlobal leak (CWE-401)
 *
 * Ground truth: memory_leak
 * alloc_lang = "csharp", never freed
 * ============================================================ */
void cs_memory_leak_bug2(void) {
    /* .NET P/Invoke unmanaged allocation */
    void* data = Marshal_AllocHGlobal(2048);
    if (!data) return;

    memset(data, 0xFF, 2048);

    /* BUG: forgot Marshal_FreeHGlobal(data) — leaked 2KB */
}

/* ============================================================
 * CS-BUG[3]: CoTaskMemAlloc → free() (CWE-763)
 *
 * Ground truth: cross_language_free
 * alloc_lang = "csharp" (CoTaskMemAlloc) != free_lang = "c" (free)
 * ============================================================ */
void cs_com_free_mismatch_bug3(void) {
    /* COM interop allocation */
    void* com_buf = CoTaskMemAlloc(512);
    if (!com_buf) return;

    memset(com_buf, 0x42, 512);

    /* BUG: CRT free() on COM-allocated memory — should use CoTaskMemFree */
    free(com_buf); /* CWE-763 */
}

/* ============================================================
 * CS-BUG[4]: Double FreeHGlobal (CWE-415 / CWE-416)
 *
 * Ground truth: double_free or invalid_free
 * ============================================================ */
void cs_double_free_bug4(void) {
    void* buf = Marshal_AllocHGlobal(256);
    if (!buf) return;

    strcpy((char*)buf, "sensitive_data");

    /* First free — correct */
    Marshal_FreeHGlobal(buf);

    /* BUG: double free — UAF risk if reused */
    Marshal_FreeHGlobal(buf); /* CWE-415 */
}

/* ============================================================
 * SAFE: Correct AllocHGlobal / FreeHGlobal pair
 *
 * Expected: no issue (correct pattern, suppressed or no finding)
 * ============================================================ */
void cs_safe_correct_pair(void) {
    void* buf = Marshal_AllocHGlobal(320);
    if (!buf) return;

    memset(buf, 0, 320);

    /* Correct: matching pair */
    Marshal_FreeHGlobal(buf);
}
