//! Zig FFI Demo — Intentional Cross-Language Bugs
//!
//! This module calls C functions via @cImport and demonstrates
//! common FFI bug patterns that a static analyzer should detect.

const c = @cImport({
    @cInclude("zig_ffi_bridge.h");
    @cInclude("ffi_traps.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

const std = @import("std");

// ─────────────────────────────────────────────────────────────────────
// BUG[ZIG-CROSS-1]: Cross-language free
// C malloc's memory, Zig frees it with @cImport free — this one is OK
// because Zig's @cImport free IS the C free. But the INTENT is to show
// a case where Zig's allocator (page_allocator) is used to free C memory.
// ─────────────────────────────────────────────────────────────────────
fn crossLanguageFreeDemo() void {
    // C allocates via c_alloc_buffer (which calls malloc)
    const ptr: [*c]u8 = @ptrCast(c.c_alloc_buffer(128));
    if (ptr == null) return;

    // Fill with data
    @memset(ptr[0..128], 0x42);

    // BUG: Zig's GeneralPurposeAllocator did NOT allocate this memory,
    // but we pretend it did. In a real scenario, mixing allocators is UB.
    // Here we use @cImport free which is actually C free — so this specific
    // call is safe. But the PATTERN is wrong: the function signature implies
    // Zig ownership of C-allocated memory.
    //
    // A correct analyzer should flag: "memory allocated by c_alloc_buffer
    // (C runtime) freed in Zig context — verify allocator compatibility"
    c.c_release_buffer(ptr);
}

// ─────────────────────────────────────────────────────────────────────
// BUG[ZIG-CROSS-2]: Use-after-free across FFI boundary
// C returns a pointer, then we use it after the C side has invalidated it.
// ─────────────────────────────────────────────────────────────────────
fn useAfterFreeDemo() void {
    const ptr: [*c]u8 = @ptrCast(c.c_get_dangling_ptr());
    if (ptr == null) return;

    // Use the pointer — but c_get_dangling_ptr returned a static buffer
    // that was zeroed. The semantic is "dangling" because the caller
    // has no guarantee of the buffer's lifetime.
    const val = ptr[0];

    // BUG: If c_get_dangling_ptr returned a pointer to stack memory
    // (which it effectively does via static buffer semantics), this is
    // a use-after-free at the semantic level.
    std.debug.print("dangling value: {d}\n", .{val});
}

// ─────────────────────────────────────────────────────────────────────
// BUG[ZIG-DOUBLE-3]: Double-free across FFI boundary
// C frees the pointer, then Zig also frees it.
// ─────────────────────────────────────────────────────────────────────
fn doubleFreeDemo() void {
    const ptr: [*c]u8 = @ptrCast(c.c_alloc_buffer(64));
    if (ptr == null) return;

    @memset(ptr[0..64], 0xFF);

    // C side frees the buffer
    c.c_release_buffer(ptr);

    // BUG: Zig also frees the same pointer — double free!
    // Using @cImport free (which is C free) to double-free.
    c.free(ptr);
}

// ─────────────────────────────────────────────────────────────────────
// BUG[ZIG-OVERFLOW-4]: Buffer overflow in C called from Zig
// Zig allocates a small buffer, passes it to C which overflows it.
// ─────────────────────────────────────────────────────────────────────
fn bufferOverflowDemo() void {
    const buf_len: usize = 32;
    const buf: [*c]u8 = @ptrCast(c.c_alloc_buffer(buf_len));
    if (buf == null) return;

    @memset(buf[0..buf_len], 0x11);

    // BUG: c_process_buffer writes len+16 bytes into a len-byte buffer.
    // This is a heap buffer overflow originating from the C side.
    c.c_process_buffer(buf, buf_len);

    // Use the (corrupted) buffer
    _ = buf[0];

    c.free(buf);
}

// ─────────────────────────────────────────────────────────────────────
// BUG[ZIG-TYPECONF-5]: Type confusion across FFI boundary
// Zig passes ZigConfig (2x u64), C reads as CConfig (2x u32).
// ─────────────────────────────────────────────────────────────────────
fn typeConfusionDemo() void {
    // Zig-side config with u64 fields
    const config = c.ZigConfig{
        .flags = 0x0000_0001_0000_0002, // high bits set
        .mode = 0x0000_0003_0000_0004, // high bits set
    };

    // BUG: c_apply_config reads as CConfig (2x u32), truncating the u64 values.
    // On little-endian: flags reads as 0x0000_0002 (low 32 bits), losing 0x0000_0001.
    // The Zig code expects full u64 semantics but C silently truncates.
    const result = c.c_apply_config(&config, @sizeOf(c.ZigConfig));
    std.debug.print("config result: {d}\n", .{result});
}

// ─────────────────────────────────────────────────────────────────────
// BUG[ZIG-LEAK-6]: Memory leak — C allocates, Zig never frees
// ─────────────────────────────────────────────────────────────────────
fn memoryLeakDemo() void {
    // C allocates a buffer
    const ptr: [*c]u8 = @ptrCast(c.c_alloc_buffer(256));
    if (ptr == null) return;

    @memset(ptr[0..256], 0xAA);

    // BUG: Buffer is never freed — memory leak.
    // The function returns without calling free(ptr).
    std.debug.print("leaked buffer first byte: {d}\n", .{ptr[0]});
}

fn subtleFfiTrapDemo() void {
    var seed = [_]u8{ 0x10, 0x20, 0x30, 0x40 };
    const token = c.ffi_make_token(&seed, seed.len);
    if (token != null) {
        std.debug.print("token first byte: {d}\n", .{token[0]});
        // BUG[ZIG-FFI-7]: C malloc-owned token is treated as a borrowed C string;
        // the normal path skips ffi_release_token after copying/printing.
    }

    var label_len: usize = 0;
    const label = c.ffi_borrowed_label(&label_len);
    std.debug.print("borrowed label len: {d}\n", .{label_len});
    // BUG[ZIG-FFI-8]: Borrowed static storage is cast away and passed to the
    // owning C release function because the API shape mirrors ffi_make_token.
    if (c.getenv("FFI_DEMO_TRIGGER_INVALID_FREE") != null) {
        c.ffi_release_token(@constCast(label));
    }

    var msg = [_]u8{ 'e', 'x', 'a', 'c', 't', 'l', 'y', '-', '1', '6', '-', 'b', 'y', 't', 'e', 's' };
    var out: [16]u8 = undefined;
    // BUG[ZIG-FFI-9]: Exact-size output and usize->u32 narrowing hide C's
    // off-by-one terminator write at the FFI boundary.
    _ = c.ffi_copy_message(@ptrCast(&msg), @intCast(msg.len), @ptrCast(&out), @intCast(out.len));
}

// ─────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────
pub fn main() void {
    std.debug.print("=== Zig FFI Bug Demo ===\n", .{});
    std.debug.print("Chain: Zig -> C (via @cImport)\n\n", .{});

    std.debug.print("[1] Cross-language free...\n", .{});
    crossLanguageFreeDemo();

    std.debug.print("[2] Use-after-free across boundary...\n", .{});
    useAfterFreeDemo();

    std.debug.print("[3] Double-free across boundary...\n", .{});
    doubleFreeDemo();

    std.debug.print("[4] Buffer overflow (C side)...\n", .{});
    bufferOverflowDemo();

    std.debug.print("[5] Type confusion (u64 vs u32)...\n", .{});
    typeConfusionDemo();

    std.debug.print("[6] Memory leak (never freed)...\n", .{});
    memoryLeakDemo();

    std.debug.print("[7] Subtle ownership/length traps...\n", .{});
    subtleFfiTrapDemo();

    std.debug.print("\n=== Done ===\n", .{});
}
