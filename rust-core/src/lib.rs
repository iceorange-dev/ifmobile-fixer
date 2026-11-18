//! Airlift FFI — C-callable surface for the iOS on-device exploit.
//!
//! Exports:
//!   al_log_init            — install the tracing subscriber
//!   al_pairing_run_host    — RPPairing host (blocks until paired)
//!   al_pairing_result_free — free the ALPairResult heap strings
//!   im_carrier_run         — inspect / apply / restore / recover the carrier binding
//!   al_string_free         — free any char* returned by this library

use std::ffi::{c_char, c_void};

pub mod exploit;
pub mod ffi_util;
pub mod grappa;
pub mod logging;
pub mod pairing;

// Re-export idevice-ffi's symbols into our staticlib (tunnel_create_rppairing,
// afc_*, rsd_*, adapter_*, etc.) so Swift can call them directly.
#[allow(unused_imports)]
extern crate idevice_ffi;

pub use pairing::{ALPairPinCb, ALPairReadyCb, ALPairResult};

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

/// Install the global tracing subscriber. Returns 0 on success, 1 if already
/// initialised. Call once at launch.
#[no_mangle]
pub extern "C" fn al_log_init(cb: logging::LogCallback, ctx: *mut c_void) -> i32 {
    logging::init(cb, ctx)
}

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------

/// Run the RPPairing host. Blocks until a device pairs or an error occurs.
/// Returns 0 on success. `port` 0 lets the OS pick a free port.
///
/// # Safety
/// All `*const c_char` args must be null or valid C strings.
/// `out` must point to a writable `ALPairResult`.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn al_pairing_run_host(
    bind_addr: *const c_char,
    port: u16,
    name: *const c_char,
    model: *const c_char,
    out_path: *const c_char,
    host_alt_irk_hex: *const c_char,
    ready_cb: ALPairReadyCb,
    pin_cb: ALPairPinCb,
    ctx: *mut c_void,
    out: *mut ALPairResult,
) -> i32 {
    pairing::run_host(
        bind_addr, port, name, model, out_path, host_alt_irk_hex,
        ready_cb, pin_cb, ctx, out,
    )
}

/// Free the heap strings inside an `ALPairResult`.
///
/// # Safety
/// `r` must be null or a `ALPairResult` populated by `al_pairing_run_host`.
#[no_mangle]
pub unsafe extern "C" fn al_pairing_result_free(r: *mut ALPairResult) {
    pairing::result_free(r)
}

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------

/// Free any `*mut c_char` returned by this library.
///
/// # Safety
/// `p` must be null or a pointer returned by one of this library's functions.
#[no_mangle]
pub unsafe extern "C" fn al_string_free(p: *mut c_char) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        ffi_util::string_free(p);
    }));
}

// ---------------------------------------------------------------------------
// Target Host Configuration
// ---------------------------------------------------------------------------

/// Set the primary target host/IP (e.g. "10.7.0.1") to dial first for RSD and tunnel operations.
/// Passing NULL or empty string resets to None.
/// Returns 0 on success.
#[no_mangle]
pub unsafe extern "C" fn al_set_target_host(host: *const c_char) -> i32 {
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let host_str = if host.is_null() {
            None
        } else {
            let s = ffi_util::opt_str(host, "").trim().to_string();
            if s.is_empty() { None } else { Some(s) }
        };
        exploit::set_target_host(host_str);
        0
    }));
    res.unwrap_or(1)
}

/// Set additional candidate target hosts (e.g. from local interface discovery).
/// `hosts` is an array of C-strings of length `count`.
/// Returns 0 on success.
#[no_mangle]
pub unsafe extern "C" fn al_set_target_hosts(hosts: *const *const c_char, count: usize) -> i32 {
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut list = Vec::new();
        if !hosts.is_null() {
            for i in 0..count {
                let p = *hosts.add(i);
                if !p.is_null() {
                    let s = ffi_util::opt_str(p, "").trim().to_string();
                    if !s.is_empty() && !list.contains(&s) {
                        list.push(s);
                    }
                }
            }
        }
        exploit::set_target_hosts(list);
        0
    }));
    res.unwrap_or(1)
}

/// Clear custom target host settings, reverting to default tunnel IP fallbacks.
#[no_mangle]
pub extern "C" fn al_clear_target_hosts() {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        exploit::clear_target_hosts();
    }));
}

