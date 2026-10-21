// framebuffer.rs - the published frame, the same contract the Amiberry
// core's host_framebuffer.cpp + host_texture.cpp give the launcher.
//
// Two buffers, swapped under a mutex: the emulation thread writes the back
// one while the UI may still be reading the front. The platform texture
// path is pull-based exactly like the original: the host installs a sink
// and calls texture_present() once per vsync; the sink copies the front
// frame into the compositor's buffer through copy_framebuffer_strided.

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;

struct Frame {
    pixels: Vec<u32>,
    width: usize,
    height: usize,
}

struct Buffers {
    frames: [Frame; 2],
    front: usize,
}

static BUFFERS: Mutex<Option<Buffers>> = Mutex::new(None);
static SERIAL: AtomicU64 = AtomicU64::new(0);
static ENABLED: AtomicBool = AtomicBool::new(false);

type Sink = unsafe extern "C" fn(*mut c_void) -> bool;
/// The platform's context pointer. It is only ever called from the thread
/// that calls texture_present, so carrying it across is safe.
struct SinkCtx(*mut c_void);
unsafe impl Send for SinkCtx {}
static SINK: Mutex<Option<(Sink, SinkCtx)>> = Mutex::new(None);
static POSTED: AtomicU64 = AtomicU64::new(0);

/// Clears the published frames and counters. Called by the run loop on
/// entry, so a second session never inherits a stale frame or serial --
/// and deliberately NOT the enable flag or the sink: those are the host's
/// choices, made before run starts, and wiping them here is how the first
/// version of this silently published nothing.
pub fn reset() {
    let mut guard = BUFFERS.lock().unwrap();
    *guard = Some(Buffers {
        frames: [
            Frame {
                pixels: Vec::new(),
                width: 0,
                height: 0,
            },
            Frame {
                pixels: Vec::new(),
                width: 0,
                height: 0,
            },
        ],
        front: 0,
    });
    SERIAL.store(0, Ordering::Release);
    POSTED.store(0, Ordering::Release);
}

/// Publishes one finished frame. Emulation thread only.
pub fn publish(pixels: &[u32], width: usize, height: usize) {
    if !ENABLED.load(Ordering::Acquire) || width == 0 || height == 0 {
        return;
    }
    let mut guard = BUFFERS.lock().unwrap();
    let Some(buffers) = guard.as_mut() else {
        return;
    };
    let back = 1 - buffers.front;
    let frame = &mut buffers.frames[back];
    if frame.pixels.len() != pixels.len() {
        frame.pixels.resize(pixels.len(), 0);
    }
    frame.pixels.copy_from_slice(pixels);
    frame.width = width;
    frame.height = height;
    buffers.front = back;
    drop(guard);
    SERIAL.fetch_add(1, Ordering::AcqRel);
}

// ---------------------------------------------------------------- C surface

#[no_mangle]
pub extern "C" fn uae4arm_host_set_framebuffer_output(enabled: bool) {
    if enabled {
        // Enabling a new session clears the last one's picture, the same
        // as the original: a stale frame would otherwise be the first
        // thing the panel draws.
        reset();
    }
    ENABLED.store(enabled, Ordering::Release);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_framebuffer_output() -> bool {
    ENABLED.load(Ordering::Acquire)
}

#[no_mangle]
pub extern "C" fn uae4arm_host_framebuffer_serial() -> u64 {
    SERIAL.load(Ordering::Acquire)
}

/// The front frame's pixel dimensions through the out pointers.
///
/// NOT exported: the exports below call each other, and a call that goes
/// through an exported name is an ELF-preemptible reference -- with a
/// second uae4arm_host_* library in the global scope (the Linux host
/// dlopens libuae4arm RTLD_GLOBAL for music) it binds to THAT library's
/// copy, which knows nothing of this core's frames. Internal callers use
/// these plain functions, which always resolve locally.
unsafe fn front_size(out_width: *mut i32, out_height: *mut i32) {
    let guard = BUFFERS.lock().unwrap();
    let (w, h) = match guard.as_ref() {
        Some(b) => (b.frames[b.front].width, b.frames[b.front].height),
        None => (0, 0),
    };
    unsafe {
        if !out_width.is_null() {
            *out_width = w as i32;
        }
        if !out_height.is_null() {
            *out_height = h as i32;
        }
    }
}

/// Copies the front frame into `dst`, `dst_stride` pixels apart, at most
/// `dst_rows` rows. Returns pixels written, or 0 with the needed size in
/// out_width/out_height. Atomically consistent: width, height and pixels
/// all describe the same frame.
unsafe fn copy_strided(
    dst: *mut u32,
    dst_stride: i32,
    dst_rows: i32,
    out_width: *mut i32,
    out_height: *mut i32,
    out_serial: *mut u64,
) -> i32 {
    let guard = BUFFERS.lock().unwrap();
    let (w, h, src) = match guard.as_ref() {
        Some(b) => {
            let f = &b.frames[b.front];
            (f.width, f.height, f.pixels.as_slice())
        }
        None => (0, 0, &[][..]),
    };
    unsafe {
        if !out_width.is_null() {
            *out_width = w as i32;
        }
        if !out_height.is_null() {
            *out_height = h as i32;
        }
        if !out_serial.is_null() {
            *out_serial = SERIAL.load(Ordering::Acquire);
        }
    }
    if w == 0 || h == 0 {
        return 0;
    }
    if dst.is_null() || dst_stride < w as i32 || dst_rows < h as i32 {
        return 0;
    }
    let stride = dst_stride as usize;
    let dst = unsafe { std::slice::from_raw_parts_mut(dst, stride * h) };
    for row in 0..h {
        dst[row * stride..row * stride + w].copy_from_slice(&src[row * w..row * w + w]);
    }
    (w * h) as i32
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_copy_framebuffer_strided(
    dst: *mut u32,
    dst_stride: i32,
    dst_rows: i32,
    out_width: *mut i32,
    out_height: *mut i32,
    out_serial: *mut u64,
) -> i32 {
    unsafe { copy_strided(dst, dst_stride, dst_rows, out_width, out_height, out_serial) }
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_copy_framebuffer(
    dst: *mut u32,
    dst_capacity: i32,
    out_width: *mut i32,
    out_height: *mut i32,
    out_serial: *mut u64,
) -> i32 {
    // Tightly packed: capacity in pixels doubles as the stride limit.
    let mut w: i32 = 0;
    let mut h: i32 = 0;
    unsafe {
        front_size(&mut w, &mut h);
    }
    if w > 0 && h > 0 && (w * h) as i64 > dst_capacity as i64 {
        unsafe {
            if !out_width.is_null() {
                *out_width = w;
            }
            if !out_height.is_null() {
                *out_height = h;
            }
            if !out_serial.is_null() {
                *out_serial = SERIAL.load(Ordering::Acquire);
            }
        }
        return 0;
    }
    unsafe { copy_strided(dst, w, h, out_width, out_height, out_serial) }
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_framebuffer_size(out_width: *mut i32, out_height: *mut i32) {
    unsafe { front_size(out_width, out_height) }
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_get_framebuffer(
    out_width: *mut i32,
    out_height: *mut i32,
    out_serial: *mut u64,
) -> *const u32 {
    let guard = BUFFERS.lock().unwrap();
    match guard.as_ref() {
        Some(b) => {
            let f = &b.frames[b.front];
            unsafe {
                if !out_width.is_null() {
                    *out_width = f.width as i32;
                }
                if !out_height.is_null() {
                    *out_height = f.height as i32;
                }
                if !out_serial.is_null() {
                    *out_serial = SERIAL.load(Ordering::Acquire);
                }
            }
            if f.width == 0 {
                std::ptr::null()
            } else {
                f.pixels.as_ptr()
            }
        }
        None => std::ptr::null(),
    }
}

// ---- texture sink ---------------------------------------------------------

/// Installs the platform's sink. Passing NULL detaches.
#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_texture_set_sink(sink: Option<Sink>, context: *mut c_void) {
    *SINK.lock().unwrap() = sink.map(|s| (s, SinkCtx(context)));
    if sink.is_none() {
        POSTED.store(0, Ordering::Release);
    }
}

#[no_mangle]
pub extern "C" fn uae4arm_host_texture_attached() -> bool {
    SINK.lock().unwrap().is_some()
}

/// Posts the current frame if it is newer than the one already posted.
/// Called once per vsync by the platform's frame loop.
#[no_mangle]
pub extern "C" fn uae4arm_host_texture_present() -> bool {
    let serial = SERIAL.load(Ordering::Acquire);
    if serial == 0 || serial == POSTED.load(Ordering::Acquire) {
        return false;
    }
    let sink = SINK.lock().unwrap().as_ref().map(|(f, ctx)| (*f, ctx.0));
    let Some((f, ctx)) = sink else { return false };
    if unsafe { f(ctx) } {
        POSTED.store(serial, Ordering::Release);
        return true;
    }
    false
}

/// The serial of the last frame the platform accepted, or 0.
#[no_mangle]
pub extern "C" fn uae4arm_host_texture_posted() -> u64 {
    POSTED.load(Ordering::Acquire)
}
