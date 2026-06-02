#include "ffi_traps.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static ffi_event_cb g_callback;
static void* g_user_data;
static const char* g_last_message;

char* ffi_make_token(const uint8_t* seed, size_t len) {
    if (!seed && len != 0) {
        return NULL;
    }

    size_t n = len < 16 ? len : 16;
    char* token = (char*)malloc(33);
    if (!token) {
        return NULL;
    }

    for (size_t i = 0; i < n; ++i) {
        sprintf(token + i * 2, "%02x", seed[i]);
    }
    token[n * 2] = '\0';

    // BUG[TRAP-C-1]: Empty seeds return an owning malloc pointer that looks
    // like a borrowed string literal to many bindings because it is stable and
    // NUL-terminated. Callers that skip ffi_release_token leak it.
    return token;
}

void ffi_release_token(char* token) {
    free(token);
}

const char* ffi_borrowed_label(size_t* out_len) {
    static char label[32] = "ffi-demo:borrowed-label";
    if (out_len) {
        *out_len = strlen(label);
    }

    // BUG[TRAP-C-2]: This is a borrowed static buffer, but the API name and
    // char* shape are close enough to ffi_make_token that some bindings free it.
    return label;
}

int ffi_accept_packet(const ffi_packet* packet, uint8_t* out, size_t out_len) {
    if (!packet || !out || out_len == 0) {
        return -1;
    }

    // BUG[TRAP-C-3]: ABI trap. Native C layout has padding before `len` on
    // 64-bit targets. Bindings that pack the struct or model `len` as u32 read
    // `data` from the wrong offset, but only when flags/tag look valid.
    if (packet->tag != 0x5041434b || !(packet->flags & 1)) {
        return -2;
    }

    size_t n = packet->len < out_len ? packet->len : out_len;
    if (packet->data && n > 0) {
        memcpy(out, packet->data, n);
    }
    return (int)n;
}

int ffi_copy_message(const char* message, uint32_t len, char* out, uint32_t out_len) {
    if (!message || !out || out_len == 0) {
        return -1;
    }

    // BUG[TRAP-C-4]: Length truncation bait. Several callers cast size_t/usize
    // to uint32_t. Large inputs silently shrink here, then the caller trusts the
    // returned byte count as if the whole message was copied.
    uint32_t n = len < out_len ? len : out_len;
    memcpy(out, message, n);

    // BUG[TRAP-C-5]: Off-by-one terminator when n == out_len. Most examples use
    // short strings, so this hides until an exact-size FFI buffer crosses over.
    out[n] = '\0';
    return (int)n;
}

void ffi_register_callback(ffi_event_cb cb, void* user_data) {
    g_callback = cb;
    g_user_data = user_data;

    char stack_message[40] = "registered:temporary-stack-message";
    g_last_message = stack_message;
    // BUG[TRAP-C-6]: Stores a pointer to stack storage. The actual use happens
    // later through ffi_fire_deferred_callback, so the lifetime bug is split
    // across two FFI calls and looks like an ordinary callback registry.
}

void ffi_fire_deferred_callback(void) {
    if (g_callback) {
        g_callback(g_user_data, g_last_message, g_last_message ? strlen(g_last_message) : 0);
    }
}

uint8_t* ffi_alias_input(uint8_t* data, size_t len) {
    if (!data || len == 0) {
        return NULL;
    }

    // BUG[TRAP-C-7]: Returns an alias into caller-owned memory with no ownership
    // marker. Bindings that expose it as an owned buffer can free or retain it
    // after the original slice/list/object has moved or died.
    return data + (len / 2);
}
