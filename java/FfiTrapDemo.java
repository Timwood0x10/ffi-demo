// Java FFI Demo — JNA-style signatures for subtle native ownership bugs.
// This source is intentionally lightweight: it gives analyzers Java-side FFI
// surfaces even when JNA is not present in the local build environment.

import java.nio.ByteBuffer;

final class FfiTrapDemo {
    static final class Native {
        static native long ffi_make_token(ByteBuffer seed, long len);
        static native void ffi_release_token(long token);
        static native long ffi_borrowed_label(long[] outLen);
        static native int ffi_copy_message(ByteBuffer message, int len, ByteBuffer out, int outLen);
        static native long ffi_alias_input(ByteBuffer data, long len);
    }

    static void ownershipTrap() {
        ByteBuffer seed = ByteBuffer.allocateDirect(4);
        seed.put(new byte[] { 0x10, 0x20, 0x30, 0x40 }).flip();
        long token = Native.ffi_make_token(seed, seed.remaining());
        if (token != 0) {
            // BUG[JAVA-FFI-1]: Native malloc-owned pointer is converted/used as an
            // opaque handle, but the normal path forgets ffi_release_token.
            System.out.println("token handle=" + token);
        }

        long[] len = new long[1];
        long label = Native.ffi_borrowed_label(len);
        // BUG[JAVA-FFI-2]: Borrowed static pointer is released through the owning
        // token release API because Java represents both as long handles.
        if ("1".equals(System.getenv("FFI_DEMO_TRIGGER_INVALID_FREE"))) {
            Native.ffi_release_token(label);
        }
    }

    static void lengthTrap() {
        ByteBuffer message = ByteBuffer.allocateDirect(16);
        message.put("exactly-16-bytes".getBytes()).flip();
        ByteBuffer out = ByteBuffer.allocateDirect(16);
        // BUG[JAVA-FFI-3]: Java int length narrows native sizes and exact output
        // capacity leaves no byte for C's terminator write.
        Native.ffi_copy_message(message, message.remaining(), out, out.capacity());

        long alias = Native.ffi_alias_input(message, message.remaining());
        // BUG[JAVA-FFI-4]: Alias points into Java-owned direct buffer but is kept
        // as an opaque native handle after GC may reclaim the buffer.
        System.out.println("alias handle=" + alias);
    }

    public static void main(String[] args) {
        ownershipTrap();
        lengthTrap();
    }
}
