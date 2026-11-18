// Airlift Rust core — C FFI surface.
//
// All fallible calls return an int32 code (0 == OK). Heap strings must be
// released with al_string_free().
#ifndef AIRLIFT_H
#define AIRLIFT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

// Receives every formatted log line. `msg` is only valid for the duration of
// the call — copy it. May be called from arbitrary Rust threads.
typedef void (*ALLogCallback)(void *ctx, const char *msg);
int32_t im_carrier_run(const char *pair, const char *root, const char *trigger, const char *action, ALLogCallback cb, void *ctx, char **out, char **err);

// Install the global tracing subscriber. Returns 0 on success, 1 if already
// initialised. Call once at launch.
int32_t al_log_init(ALLogCallback cb, void *ctx);

// Free any char* returned by this library.
void al_string_free(char *p);

// ---------------------------------------------------------------------------
// Pairing — RPPairing host
// ---------------------------------------------------------------------------

// Fires once the host is bound. The Swift side publishes `service_id` over
// Bonjour (NetService). All pointers are only valid during the call.
typedef void (*ALPairReadyCb)(void *ctx,
                               const char *service_id,
                               uint16_t port,
                               const char *const *txt_keys,
                               const char *const *txt_vals,
                               size_t txt_count);

// Fires with the PIN the user must confirm in Settings → Developer Mode.
typedef void (*ALPairPinCb)(const char *pin, void *ctx);

// Heap-allocated result of one pairing run. Free with al_pairing_result_free().
typedef struct {
    char *error;
    char *device_name;
    char *device_model;
    char *device_udid;
    char *pairing_file_path;
    char *host_alt_irk_hex;
} ALPairResult;

// Run the RPPairing host. BLOCKS until paired or errored — run off main thread.
// `port` 0 lets the OS pick a free port.
// `host_alt_irk_hex` is the value a previous run returned, or NULL/"" first time.
// Returns 0 on success, non-zero on error (with out->error set).
int32_t al_pairing_run_host(const char *bind_addr,
                             uint16_t port,
                             const char *name,
                             const char *model,
                             const char *out_path,
                             const char *host_alt_irk_hex,
                             ALPairReadyCb ready_cb,
                             ALPairPinCb pin_cb,
                             void *ctx,
                             ALPairResult *out);

// Free the heap strings inside an ALPairResult.
void al_pairing_result_free(ALPairResult *r);

// ---------------------------------------------------------------------------
// Target Host Configuration
// ---------------------------------------------------------------------------

// Set the primary target host/IP (e.g. "10.7.0.1") to dial first for RSD and tunnel operations.
// Passing NULL or "" resets to None.
// Returns 0 on success.
int32_t al_set_target_host(const char *host);

// Set additional candidate target hosts (e.g. from local interface discovery).
// `hosts` is an array of C-strings of length `count`.
// Returns 0 on success.
int32_t al_set_target_hosts(const char *const *hosts, size_t count);

// Clear custom target host settings, reverting to default tunnel IP fallbacks.
void al_clear_target_hosts(void);


#ifdef __cplusplus
}
#endif

#endif /* AIRLIFT_H */

