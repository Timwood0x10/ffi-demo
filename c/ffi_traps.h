#ifndef FFI_TRAPS_H
#define FFI_TRAPS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ffi_packet {
    uint32_t tag;
    uint8_t flags;
    size_t len;
    const uint8_t* data;
} ffi_packet;

typedef void (*ffi_event_cb)(void* user_data, const char* message, size_t len);

char* ffi_make_token(const uint8_t* seed, size_t len);
void ffi_release_token(char* token);
const char* ffi_borrowed_label(size_t* out_len);
int ffi_accept_packet(const ffi_packet* packet, uint8_t* out, size_t out_len);
int ffi_copy_message(const char* message, uint32_t len, char* out, uint32_t out_len);
void ffi_register_callback(ffi_event_cb cb, void* user_data);
void ffi_fire_deferred_callback(void);
uint8_t* ffi_alias_input(uint8_t* data, size_t len);


// ── Additional bug scenarios for cross-family / UAF / double-free detection ──

/// BUG[TRAP-C-8]: Cross-family free. Allocates with malloc (C_HEAP)
/// but the caller is expected to release with operator delete (CPP_NEW_SCALAR).
void* cross_family_alloc(void);

/// BUG[TRAP-C-9]: Use-after-free through FFI. Frees a buffer then
/// passes the dangling pointer to an FFI callback that reads it.
void uaf_through_ffi(void);

/// BUG[TRAP-C-11]: Leaked callback userdata. Heap-allocated userdata
/// passed to a callback registration that never frees it.
void leaked_callback_userdata(void);

#ifdef __cplusplus
}
#endif

#endif
