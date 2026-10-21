// The whole crate is a C boundary: every pointer argument arrives from
// the host and is dereferenced inside an unsafe block, so marking each
// export `unsafe` would only decorate.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

// copperline_ffi - the bridge, milestone 1 of the Copperline edition.
//
// A C ABI over the headless Copperline core, shaped exactly like the surface
// the wasm frontend uses (crates/copperline-web): construct, load a ROM, run
// up to the wall clock, read the presented RGBA frame, drain audio, feed
// keys/mouse/joysticks, swap floppies. The Flutter side talks to this the
// way it talks to Amiberry today - same jobs, different core.
//
// Threading contract: every cl_* call for one handle must come from ONE
// thread (the Dart side owns an emulator isolate); the handle is opaque and
// never shared.
//
// The same crate also exports the uae4arm_host_* surface (host.rs,
// framebuffer.rs): the ABI the Flutter host speaks to the Amiberry core,
// re-implemented over Copperline so the launcher can pick either library
// without knowing which.
mod audio_out;
mod framebuffer;
mod helpers;
mod host;

use std::cell::RefCell;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::PathBuf;
use std::rc::Rc;

use copperline::audio::AudioSink;
use copperline::config::{
    machine_profile_defaults, parse_machine_model, parse_video_standard, Config, Overscan, TvCentre,
};
use copperline::emulator::{build_machine, Emulator};
use copperline::video::deinterlace::Deinterlacer;
use copperline::video::{bitplane, present_common, FB_WIDTH, MAX_CANVAS_PIXELS};

use helpers::{port_index, take_integral_delta, w3c_code_to_amiga_rawkey};

const MAX_CATCHUP_SECONDS: f64 = 0.1;

struct BufferSink {
    buf: Rc<RefCell<Vec<f32>>>,
}

impl AudioSink for BufferSink {
    fn push(&mut self, left: f32, right: f32) {
        let mut buf = self.buf.borrow_mut();
        buf.push(left);
        buf.push(right);
    }
    fn flush(&mut self) {}
}

pub struct ClEmu {
    pub(crate) emu: Emulator,
    audio: Rc<RefCell<Vec<f32>>>,
    fb: Vec<u32>,
    deinterlacer: Deinterlacer,
    pub(crate) present: Vec<u32>,
    pub(crate) present_width: usize,
    pub(crate) present_rows: usize,
    pub(crate) last_rendered_frame: Option<u64>,
    anchor: Option<(f64, f64)>,
    mouse_remainder: (f64, f64),
    mouse_pending: (i32, i32),
    // Fixed presentation choices for the bridge: TV overscan, no drawn
    // bezel, centred glass, no phosphor. The GUI's Video tab can grow
    // setters later; the wasm frontend shows exactly where they plug in.
    presentation_latch: present_common::PresentationLatch,
    repeated_frame_detector: bitplane::RepeatedFrameDetector,
}

impl ClEmu {
    /// `model` = machine profile name ("A500", "A1200", "CD32", ...) as the
    /// desktop's --model flag takes it; empty = the default A500. `video` =
    /// "PAL"/"NTSC" or empty for the profile's own. `floppy_drives` 0-4, or
    /// a negative value to keep the profile default. These ARE the Core
    /// tab's options - the same knobs the desktop launcher exposes.
    fn new(model: &str, video: &str, floppy_drives: i32) -> anyhow::Result<ClEmu> {
        let mut cfg = if model.trim().is_empty() {
            Config::default()
        } else {
            machine_profile_defaults(parse_machine_model(model.trim()).map_err(anyhow::Error::msg)?)
        };
        if !video.trim().is_empty() {
            cfg.video_standard = parse_video_standard(video.trim()).map_err(anyhow::Error::msg)?;
        }
        if (0..=4).contains(&floppy_drives) {
            let count = floppy_drives as usize;
            cfg.floppy_connected = std::array::from_fn(|drive| drive < count);
        }
        let audio = Rc::new(RefCell::new(Vec::new()));
        let sink = BufferSink { buf: audio.clone() };
        // rom_optional: the GUI supplies the Kickstart through cl_load_rom.
        let emu = build_machine(&cfg, Box::new(sink), false, true)?;
        Ok(ClEmu::wrap_with_audio(emu, audio))
    }

    /// The presentation half of a machine the host built itself - the
    /// uae4arm_host run path constructs its own Emulator from a config file
    /// rather than the model/video/drives shorthand.
    pub(crate) fn wrap(emu: Emulator) -> ClEmu {
        ClEmu::wrap_with_audio(emu, Rc::new(RefCell::new(Vec::new())))
    }

    fn wrap_with_audio(emu: Emulator, audio: Rc<RefCell<Vec<f32>>>) -> ClEmu {
        ClEmu {
            emu,
            audio,
            fb: vec![0u32; MAX_CANVAS_PIXELS],
            // Progressive output is exact without history; LACE fields line-
            // double, as the wasm frontend defaults. No phosphor.
            deinterlacer: Deinterlacer::with_settings(false, 0.0),
            present: Vec::new(),
            present_width: FB_WIDTH,
            present_rows: 0,
            last_rendered_frame: None,
            anchor: None,
            mouse_remainder: (0.0, 0.0),
            mouse_pending: (0, 0),
            presentation_latch: present_common::PresentationLatch::default(),
            repeated_frame_detector: bitplane::RepeatedFrameDetector::default(),
        }
    }

    fn drain_pending_mouse(&mut self) {
        const MAX_COUNTS_PER_FRAME: i32 = 100;
        let dx = self
            .mouse_pending
            .0
            .clamp(-MAX_COUNTS_PER_FRAME, MAX_COUNTS_PER_FRAME);
        let dy = self
            .mouse_pending
            .1
            .clamp(-MAX_COUNTS_PER_FRAME, MAX_COUNTS_PER_FRAME);
        if dx != 0 || dy != 0 {
            self.mouse_pending.0 -= dx;
            self.mouse_pending.1 -= dy;
            self.emu.bus_mut().input.add_mouse_delta(0, dx, dy);
        }
    }

    fn run(&mut self, now_ms: f64, max_frames: u32) -> anyhow::Result<u32> {
        let (anchor_wall, anchor_emu) = *self
            .anchor
            .get_or_insert((now_ms, self.emu.bus().emulated_seconds()));
        let target = anchor_emu + (now_ms - anchor_wall) / 1000.0;
        let mut stepped = 0u32;
        while self.emu.bus().emulated_seconds() < target && stepped < max_frames {
            self.drain_pending_mouse();
            self.emu.step_frame()?;
            stepped += 1;
        }
        if stepped == 0 {
            self.drain_pending_mouse();
        }
        if target - self.emu.bus().emulated_seconds() > MAX_CATCHUP_SECONDS {
            self.anchor = Some((now_ms, self.emu.bus().emulated_seconds()));
        }
        if stepped > 0 {
            self.render_completed_frame(stepped.max(1));
        }
        Ok(stepped)
    }

    /// The wasm frontend's render path against the current core API, with
    /// the bridge's fixed choices: TV overscan, no drawn bezel, centred
    /// glass, no phosphor. elapsed_fields is always the fields just stepped.
    fn render_completed_frame(&mut self, elapsed_fields: u32) {
        if !self.emu.bus().frame_render_available() {
            return;
        }
        let emulated_frame = self.emu.bus().emulated_frames();
        if !present_common::should_render_emulated_frame(self.last_rendered_frame, emulated_frame) {
            return;
        }
        let visible_start_vpos = self.emu.bus().frame_visible_start_vpos();
        // A frame identical to the previous render needs no pipeline at all.
        match bitplane::render_reusing_previous(
            self.emu.bus_mut(),
            &mut self.fb,
            &mut self.repeated_frame_detector,
        ) {
            bitplane::ReuseRender::Reused => {
                self.last_rendered_frame = Some(emulated_frame);
                return;
            }
            bitplane::ReuseRender::Rendered(_) => {}
        }
        let geometry = self.emu.bus().frame_geometry();
        let canvas_scale = self.emu.bus().frame_canvas_scale();
        let base = self.emu.bus().frame_render_base();
        let h_shift = self
            .presentation_latch
            .presentation_h_shift(&base, Overscan::Tv);
        let placement = present_common::post_process_rendered_field(
            &mut self.fb,
            geometry,
            canvas_scale,
            self.emu.bus().frame_presentation_h_window(),
            self.emu.bus().frame_presentation_v_window(),
            visible_start_vpos,
            h_shift,
            Overscan::Tv,
        );
        let field_rows = placement.rows;
        let canvas_width = FB_WIDTH * canvas_scale;
        let lace = base.bplcon0 & 0x0004 != 0;
        let double_rows = !geometry.programmable;
        let woven_rows = if lace || double_rows {
            field_rows * 2
        } else {
            field_rows
        };
        let tv_aperture_rows = self.presentation_latch.resolve_tv_aperture(
            present_common::standard_tv_aperture_frame(geometry, woven_rows, &base),
        );
        if let Some(aperture_rows) = tv_aperture_rows {
            let (source_x_offset, source_y_offset) =
                present_common::tv_centre_source_offset(TvCentre::default());
            (self.present_rows, self.present_width) =
                self.deinterlacer.present_field_region_into_elapsed(
                    &self.fb,
                    field_rows,
                    canvas_width,
                    lace,
                    base.long_field,
                    double_rows,
                    present_common::TV_CAPTURED_SOURCE_X as i32 + source_x_offset,
                    present_common::TV_PRESENT_SOURCE_Y as i32 + source_y_offset,
                    aperture_rows,
                    present_common::TV_CAPTURED_WIDTH,
                    present_common::TV_GLASS_PRESENT_ROWS,
                    elapsed_fields,
                    &mut self.present,
                );
        } else {
            (self.present_rows, self.present_width) = self.deinterlacer.present_field_into_elapsed(
                &self.fb,
                field_rows,
                canvas_width,
                lace,
                base.long_field,
                double_rows,
                elapsed_fields,
                &mut self.present,
            );
        }
        self.last_rendered_frame = Some(emulated_frame);
    }
}

// ---------------------------------------------------------------- C surface

unsafe fn emu<'a>(h: *mut ClEmu) -> &'a mut ClEmu {
    unsafe { &mut *h }
}

unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(ptr, len) }
    }
}

/// `model`/`video` may be NULL or empty for defaults; `floppy_drives` < 0
/// keeps the profile default.
#[no_mangle]
pub extern "C" fn cl_new(
    model: *const c_char,
    video: *const c_char,
    floppy_drives: i32,
) -> *mut ClEmu {
    let cstr = |p: *const c_char| -> String {
        if p.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
        }
    };
    match ClEmu::new(&cstr(model), &cstr(video), floppy_drives) {
        Ok(e) => Box::into_raw(Box::new(e)),
        Err(err) => {
            eprintln!("copperline_ffi: cl_new failed: {err:#}");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn cl_free(h: *mut ClEmu) {
    if !h.is_null() {
        drop(unsafe { Box::from_raw(h) });
    }
}

/// The core's version string into `out` (truncated, always NUL-terminated);
/// returns the untruncated length.
#[no_mangle]
pub extern "C" fn cl_version(out: *mut c_char, cap: usize) -> usize {
    let v = format!("copperline {}", env!("CARGO_PKG_VERSION"));
    let src = v.as_bytes();
    if !out.is_null() && cap > 0 {
        let n = src.len().min(cap - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(src.as_ptr(), out as *mut u8, n);
            *out.add(n) = 0;
        }
    }
    src.len()
}

/// Fit a Kickstart (and optional extended ROM) and cold-reset. 0 = ok.
#[no_mangle]
pub extern "C" fn cl_load_rom(
    h: *mut ClEmu,
    rom: *const u8,
    rom_len: usize,
    ext: *const u8,
    ext_len: usize,
) -> i32 {
    let e = unsafe { emu(h) };
    let rom = unsafe { bytes(rom, rom_len) }.to_vec();
    let ext = if ext_len == 0 {
        None
    } else {
        Some(unsafe { bytes(ext, ext_len) }.to_vec())
    };
    match e.emu.reload_rom(rom, ext) {
        Ok(()) => {
            e.anchor = None;
            0
        }
        Err(err) => {
            eprintln!("copperline_ffi: load_rom: {err:#}");
            -1
        }
    }
}

/// Step emulated time up to `now_ms` (any monotonic millisecond clock), at
/// most `max_frames` PAL frames. Returns frames stepped, or -1 on error.
#[no_mangle]
pub extern "C" fn cl_run(h: *mut ClEmu, now_ms: f64, max_frames: u32) -> i32 {
    match unsafe { emu(h) }.run(now_ms, max_frames) {
        Ok(n) => n as i32,
        Err(err) => {
            eprintln!("copperline_ffi: run: {err:#}");
            -1
        }
    }
}

/// The presented frame: RGBA u32 pixels, `cl_present_width() x
/// cl_present_rows()`. Valid until the next cl_run on the same handle.
#[no_mangle]
pub extern "C" fn cl_present_ptr(h: *mut ClEmu) -> *const u32 {
    unsafe { emu(h) }.present.as_ptr()
}

#[no_mangle]
pub extern "C" fn cl_present_width(h: *mut ClEmu) -> u32 {
    unsafe { emu(h) }.present_width as u32
}

#[no_mangle]
pub extern "C" fn cl_present_rows(h: *mut ClEmu) -> u32 {
    unsafe { emu(h) }.present_rows as u32
}

/// Drain up to `cap` interleaved stereo f32 samples into `out`; returns the
/// number written. Call every tick or Paula's buffer grows without bound.
#[no_mangle]
pub extern "C" fn cl_take_audio(h: *mut ClEmu, out: *mut f32, cap: usize) -> usize {
    let e = unsafe { emu(h) };
    let mut buf = e.audio.borrow_mut();
    let n = buf.len().min(cap);
    if n > 0 && !out.is_null() {
        unsafe { std::ptr::copy_nonoverlapping(buf.as_ptr(), out, n) };
    }
    buf.drain(..n);
    n
}

/// W3C KeyboardEvent.code strings ("KeyA", "Enter"), exactly what the wasm
/// frontend speaks - and what Flutter's key events carry too. Returns true
/// if the code mapped to an Amiga rawkey.
#[no_mangle]
pub extern "C" fn cl_key_event(h: *mut ClEmu, code: *const c_char, pressed: bool) -> bool {
    if code.is_null() {
        return false;
    }
    let code = match unsafe { CStr::from_ptr(code) }.to_str() {
        Ok(c) => c,
        Err(_) => return false,
    };
    match w3c_code_to_amiga_rawkey(code) {
        Some(rawkey) => {
            unsafe { emu(h) }
                .emu
                .bus_mut()
                .enqueue_key_event(rawkey, pressed);
            true
        }
        None => false,
    }
}

#[no_mangle]
pub extern "C" fn cl_mouse_delta(h: *mut ClEmu, dx: f64, dy: f64) {
    if !dx.is_finite() || !dy.is_finite() {
        return;
    }
    let e = unsafe { emu(h) };
    e.mouse_remainder.0 += dx;
    e.mouse_remainder.1 += dy;
    let ix = take_integral_delta(&mut e.mouse_remainder.0);
    let iy = take_integral_delta(&mut e.mouse_remainder.1);
    e.mouse_pending.0 = e.mouse_pending.0.saturating_add(ix);
    e.mouse_pending.1 = e.mouse_pending.1.saturating_add(iy);
}

/// 0 = left, 1 = middle, 2 = right, as MouseEvent.button has them.
#[no_mangle]
pub extern "C" fn cl_mouse_button(h: *mut ClEmu, button: u8, pressed: bool) {
    let input = &mut unsafe { emu(h) }.emu.bus_mut().input;
    match button {
        0 => input.set_mouse_button(0, 0, pressed),
        1 => input.set_mouse_button(0, 2, pressed),
        2 => input.set_mouse_button(0, 1, pressed),
        _ => {}
    }
}

#[no_mangle]
pub extern "C" fn cl_set_joystick(
    h: *mut ClEmu,
    port: u8,
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    fire: bool,
    button2: bool,
) {
    unsafe { emu(h) }.emu.bus_mut().input.set_joystick(
        port_index(port),
        up,
        down,
        left,
        right,
        fire,
        button2,
    );
}

/// Insert a disk image from bytes (ADF and friends); `name` is only a label.
#[no_mangle]
pub extern "C" fn cl_insert_floppy(
    h: *mut ClEmu,
    drive: u8,
    data: *const u8,
    len: usize,
    name: *const c_char,
) -> i32 {
    let label = if name.is_null() {
        "disk.adf".to_string()
    } else {
        unsafe { CStr::from_ptr(name) }
            .to_string_lossy()
            .into_owned()
    };
    let data = unsafe { bytes(data, len) }.to_vec();
    match unsafe { emu(h) }
        .emu
        .bus_mut()
        .floppy
        .insert_disk_image_bytes(drive as usize, data, PathBuf::from(label), true)
    {
        Ok(()) => 0,
        Err(err) => {
            eprintln!("copperline_ffi: insert_floppy: {err:#}");
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn cl_eject_floppy(h: *mut ClEmu, drive: u8) -> i32 {
    match unsafe { emu(h) }
        .emu
        .bus_mut()
        .floppy
        .eject_disk_image(drive as usize)
    {
        Ok(()) => 0,
        Err(err) => {
            eprintln!("copperline_ffi: eject_floppy: {err:#}");
            -1
        }
    }
}
