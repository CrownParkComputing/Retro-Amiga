// host.rs - the uae4arm_host_* surface, re-implemented over Copperline.
//
// The Flutter host speaks exactly one ABI (src/osdep/uae4arm_host.h) and it
// must not care which core is behind it, so every function here mirrors the
// Amiberry implementation's semantics: inbound calls are commands queued
// for the emulation thread, uae4arm_host_run owns that thread until Quit,
// and the session snapshot goes to states/recent.txt in the same
// ts\ttitle\tstate\tconfig format capped at five.
//
// What the original had and this does not need: an SDL window, a menu, a
// physical-controller table. Those entry points are kept for ABI parity
// and do the closest meaningful thing (or nothing, when there is nothing
// meaningful - the music player, for instance, lives in the Amiberry core
// and these names exist so an accidental binding fails benignly).

use std::collections::VecDeque;
use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::Instant;

use copperline::audio::AudioSink;
use copperline::bus::PortDevice;
use copperline::config::{Config, ConfigOverrides};
use copperline::{paths, whdload};

use crate::audio_out::LiveAudio;
use crate::framebuffer;
use crate::ClEmu;

// ------------------------------------------------------------------ state

/// Which Amiga port the host's pad drives: 1 by default, 0 after swaps.
/// Same numbering on both sides of the API - UAE jport and Copperline
/// port indexes both put the mouse port at 0.
static PAD_PORT: AtomicI32 = AtomicI32::new(1);
static FLOPPY_COUNT: AtomicI32 = AtomicI32::new(1);
static CORRECT_ASPECT: AtomicBool = AtomicBool::new(false);
static PAUSED: AtomicBool = AtomicBool::new(false);
static RUNNING: AtomicBool = AtomicBool::new(false);
/// Set alongside the queued Quit so a paused loop still sees it at once.
static QUIT: AtomicBool = AtomicBool::new(false);

/// The pause flag the audio sink reads: suspended, not stopped, so the
/// stream does not have to be reopened on resume.
static AUDIO_SUSPENDED: LazyLock<std::sync::Arc<AtomicBool>> =
    LazyLock::new(|| std::sync::Arc::new(AtomicBool::new(false)));

/// One virtual pad: kind set by pad_attach / set_onscreen_controller
/// (1 joystick, 2 CD32 pad, 0 detached), driven on PAD_PORT.
#[derive(Default)]
struct Pad {
    attached: bool,
    cd32: bool,
    left: bool,
    right: bool,
    up: bool,
    down: bool,
    axis: [i32; 2],
    fire: bool,
    button2: bool,
    play: bool,
    rwd: bool,
    ffw: bool,
    green: bool,
    yellow: bool,
}

impl Pad {
    fn merged(&self) -> (bool, bool, bool, bool) {
        const THRESH: i32 = 16_000;
        (
            self.up || self.axis[1] < -THRESH,
            self.down || self.axis[1] > THRESH,
            self.left || self.axis[0] < -THRESH,
            self.right || self.axis[0] > THRESH,
        )
    }
    fn release_all(&mut self) {
        *self = Pad {
            attached: self.attached,
            cd32: self.cd32,
            ..Pad::default()
        };
    }
}

struct Shared {
    session_state: String,
    session_config: String,
    session_title: String,
    pads: [Pad; 3], // indexed by the pad id the host passes (1,2); 0 unused
    onscreen_mode: i32,
    external_mode: i32,
    port0_joystick: bool,
    log_path: Option<PathBuf>,
}

static SHARED: LazyLock<Mutex<Shared>> = LazyLock::new(|| {
    Mutex::new(Shared {
        session_state: String::new(),
        session_config: String::new(),
        session_title: String::new(),
        pads: [Pad::default(), Pad::default(), Pad::default()],
        onscreen_mode: 0,
        external_mode: -1,
        port0_joystick: false,
        log_path: None,
    })
});

// ------------------------------------------------------------- commands

enum Command {
    Key(i32, bool),
    Pause(bool),
    Restart,
    InsertFloppy(usize, PathBuf),
    EjectFloppy(usize),
    Port0Joystick(bool),
    SwapPadPort,
    CorrectAspect(bool),
    MouseMove(i32, i32),
    MouseButton(i32, bool),
    SaveSession {
        state: PathBuf,
        config: PathBuf,
        title: String,
    },
    SaveState(PathBuf),
    Launch {
        config: Option<PathBuf>,
        whdload: Option<PathBuf>,
    },
    /// Re-push the virtual pad's whole state (attach, mode, axis, button
    /// changes all land here; the device has no partial writes).
    PadSync,
    Quit,
}

/// The switches where only the newest value matters, so a stale queued
/// copy may be replaced. Never keys or buttons - losing a release leaves
/// a control permanently held.
fn coalescable(c: &Command) -> bool {
    matches!(
        c,
        Command::MouseMove(..)
            | Command::Pause(..)
            | Command::CorrectAspect(..)
            | Command::Port0Joystick(..)
            | Command::PadSync
    )
}

static QUEUE: Mutex<VecDeque<Command>> = Mutex::new(VecDeque::new());
const SOFT_MAX: usize = 512;

fn enqueue(command: Command) {
    let mut q = QUEUE.lock().unwrap();

    // Pointer motion is a delta: consecutive reports combine, which keeps
    // a busy touch gesture from filling the queue without losing distance.
    if let (Command::MouseMove(dx, dy), Some(Command::MouseMove(px, py))) = (&command, q.back_mut())
    {
        *px = (*px + dx).clamp(-32767, 32767);
        *py = (*py + dy).clamp(-32767, 32767);
        return;
    }
    if coalescable(&command) {
        for slot in q.iter_mut().rev() {
            if std::mem::discriminant(slot) == std::mem::discriminant(&command) {
                *slot = command;
                return;
            }
        }
    }
    if q.len() >= SOFT_MAX {
        if let Some(pos) = q.iter().position(coalescable) {
            q.remove(pos);
        } else if coalescable(&command) {
            return;
        }
        // Critical commands may exceed the cap briefly; a key-up, save or
        // quit is safer than a stuck key or a session silently not saved.
    }
    q.push_back(command);
}

fn drain_queue() -> VecDeque<Command> {
    let mut q = QUEUE.lock().unwrap();
    std::mem::take(&mut *q)
}

// ------------------------------------------------------------- logging

/// Logger writing both to stderr and, when enabled, the session logfile
/// the app's Logs page reads. One per process; the file can be retargeted
/// between runs.
struct BridgeLog {
    file: Mutex<Option<std::fs::File>>,
}

impl log::Log for BridgeLog {
    fn enabled(&self, meta: &log::Metadata) -> bool {
        meta.level() <= log::Level::Info
    }
    fn log(&self, rec: &log::Record) {
        if !self.enabled(rec.metadata()) {
            return;
        }
        let line = format!("{}\n", rec.args());
        eprint!("{line}");
        if let Ok(mut guard) = self.file.lock() {
            if let Some(f) = guard.as_mut() {
                use std::io::Write;
                let _ = f.write_all(line.as_bytes());
            }
        }
    }
    fn flush(&self) {}
}

static LOGGER: BridgeLog = BridgeLog {
    file: Mutex::new(None),
};

fn ensure_logger() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let _ = log::set_logger(&LOGGER);
        log::set_max_level(log::LevelFilter::Info);
    });
}

static LOG_ENABLED: AtomicBool = AtomicBool::new(false);
/// Buffer for logfile_path's return; valid until the next call.
static LOG_PATH_C: LazyLock<Mutex<CString>> =
    LazyLock::new(|| Mutex::new(CString::new("").unwrap()));

#[no_mangle]
pub extern "C" fn uae4arm_host_set_logfile_enabled(enabled: bool) {
    ensure_logger();
    LOG_ENABLED.store(enabled, Ordering::Release);
    if enabled {
        reopen_logfile();
    } else {
        *LOGGER.file.lock().unwrap() = None;
    }
}

/// (Re)opens the file at the path last set by --logfile, or the default
/// beside the working directory when the host never named one.
fn reopen_logfile() {
    let path = SHARED
        .lock()
        .unwrap()
        .log_path
        .clone()
        .unwrap_or_else(|| PathBuf::from("copperline_log.txt"));
    let file = std::fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .open(&path)
        .ok();
    *LOGGER.file.lock().unwrap() = file;
    *LOG_PATH_C.lock().unwrap() =
        CString::new(path.to_string_lossy().as_bytes()).unwrap_or_default();
}

#[no_mangle]
pub extern "C" fn uae4arm_host_logfile_path() -> *const c_char {
    if !LOG_ENABLED.load(Ordering::Acquire) {
        return c"".as_ptr();
    }
    let guard = LOG_PATH_C.lock().unwrap();
    guard.as_ptr()
}

// -------------------------------------------------------- callbacks

#[repr(C)]
pub struct HostCallbacks {
    pub show_menu: Option<unsafe extern "C" fn(i32)>,
    pub toggle_virtual_keyboard: Option<unsafe extern "C" fn()>,
    pub hide_virtual_keyboard: Option<unsafe extern "C" fn()>,
}

static CALLBACKS: Mutex<HostCallbacks> = Mutex::new(HostCallbacks {
    show_menu: None,
    toggle_virtual_keyboard: None,
    hide_virtual_keyboard: None,
});

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_set_callbacks(cb: *const HostCallbacks) {
    let mut guard = CALLBACKS.lock().unwrap();
    *guard = if cb.is_null() {
        HostCallbacks {
            show_menu: None,
            toggle_virtual_keyboard: None,
            hide_virtual_keyboard: None,
        }
    } else {
        unsafe { std::ptr::read(cb) }
    };
}

#[no_mangle]
pub extern "C" fn uae4arm_host_show_menu(shortcut: i32) {
    if let Some(f) = CALLBACKS.lock().unwrap().show_menu {
        unsafe { f(shortcut) };
    }
}

#[no_mangle]
pub extern "C" fn uae4arm_host_toggle_virtual_keyboard() {
    if let Some(f) = CALLBACKS.lock().unwrap().toggle_virtual_keyboard {
        unsafe { f() };
    }
}

#[no_mangle]
pub extern "C" fn uae4arm_host_hide_virtual_keyboard() {
    if let Some(f) = CALLBACKS.lock().unwrap().hide_virtual_keyboard {
        unsafe { f() };
    }
}

// --------------------------------------------------------- run loop

struct LaunchArgs {
    config: Option<PathBuf>,
    whdload: Option<PathBuf>,
    statefile: Option<PathBuf>,
    logfile: Option<PathBuf>,
}

/// Parses the argv the launcher hands over. Only the options the host
/// knows are taken; anything else is logged and ignored so new flags from
/// either side do not break the other.
fn parse_args(args: &[String]) -> LaunchArgs {
    let mut out = LaunchArgs {
        config: None,
        whdload: None,
        statefile: None,
        logfile: None,
    };
    let mut it = args.iter().peekable();
    while let Some(arg) = it.next() {
        let take =
            |it: &mut std::iter::Peekable<std::slice::Iter<String>>| it.next().map(PathBuf::from);
        match arg.as_str() {
            "--config" | "-f" => out.config = take(&mut it),
            "--whdload" | "--autoload" => out.whdload = take(&mut it),
            "--statefile" => out.statefile = take(&mut it),
            "--logfile" => out.logfile = take(&mut it),
            other => {
                if let Some(rest) = other.strip_prefix("--config=") {
                    out.config = Some(PathBuf::from(rest));
                } else if let Some(rest) = other.strip_prefix("--whdload=") {
                    out.whdload = Some(PathBuf::from(rest));
                } else if let Some(rest) = other.strip_prefix("--statefile=") {
                    out.statefile = Some(PathBuf::from(rest));
                } else if let Some(rest) = other.strip_prefix("--logfile=") {
                    out.logfile = Some(PathBuf::from(rest));
                } else {
                    log::info!("startup: ignoring argument {other}");
                }
            }
        }
    }
    out
}

/// Builds a machine for `args`. The TOML is the whole contract: profile,
/// ROM, media, WHDLoad. WHDLoad preparation mirrors the desktop frontend:
/// the game's own [whdload] options plus an archive passed on the command
/// line win over TOML `game=`.
fn build(args: &LaunchArgs, restore_state: bool) -> anyhow::Result<ClEmu> {
    log::info!(
        "startup: config={:?} whdload={:?}",
        args.config,
        args.whdload
    );
    let raw = Config::load_raw(args.config.as_deref(), &ConfigOverrides::default())?;
    paths::adopt(raw.paths());
    let (cfg_game, opts) = whdload::game_and_options(&raw);
    let game = args.whdload.clone().or(cfg_game);
    let mut cfg = if let Some(game) = game {
        let prepared = whdload::prepare(&game, &opts)?;
        let mut derived = raw.clone();
        whdload::apply_to_raw(&mut derived, &prepared);
        Config::try_from(derived)?
    } else {
        Config::try_from(raw.clone())?
    };
    // Substitute the bundled AROS pair when the config names no Kickstart.
    // A state restore may skip it: the state carries the ROM it was made
    // under, so the placeholder build is fine (mirrors main.rs).
    if restore_state && args.statefile.is_some() {
        let _ = copperline::config::resolve_bundled_rom(&mut cfg);
    } else {
        copperline::config::resolve_bundled_rom(&mut cfg)?;
    }
    FLOPPY_COUNT.store(
        cfg.floppy_connected.iter().filter(|c| **c).count().max(1) as i32,
        Ordering::Release,
    );
    let suspended = AUDIO_SUSPENDED.clone();
    let sink: Box<dyn AudioSink> = match LiveAudio::open(suspended) {
        Some(a) => Box::new(a),
        None => {
            log::warn!("startup: no audio device; running silent");
            Box::new(copperline::audio::NullSink)
        }
    };
    let mut emu = copperline::emulator::build_machine(&cfg, sink, true, true)?;
    if restore_state {
        if let Some(state) = &args.statefile {
            log::info!("startup: restoring {}", state.display());
            if let Err(e) = emu.load_state(state) {
                log::error!("startup: restore failed: {e:#}");
            }
        }
    }
    Ok(ClEmu::wrap(emu))
}

/// The emulation thread. `uae4arm_host_run` owns it until Quit; like the
/// original it may be entered again for the next game.
fn run_loop(first: LaunchArgs) -> i32 {
    let mut current = first;
    let mut emu = match build(&current, true) {
        Ok(e) => Some(e),
        Err(e) => {
            log::error!("startup: machine did not build: {e:#}");
            // Nothing to run and nothing for a Quit to release: give the
            // caller its failure now rather than an empty loop that looks
            // like a live session. uae4arm_host_run cleans up either way.
            return -1;
        }
    };
    let mut published_frame: Option<u64> = None;
    let start = Instant::now();
    let beam_watch = std::env::var_os("CL_BEAM_WATCH").is_some();
    let mut beam_next = 0.0f64;
    let mut exit = 0i32;

    loop {
        // ---- drain host commands
        for command in drain_queue() {
            match command {
                Command::Quit => QUIT.store(true, Ordering::Release),
                Command::Key(code, pressed) => {
                    if let Some(e) = &mut emu {
                        if let Ok(k) = u8::try_from(code) {
                            e.emu.bus_mut().enqueue_key_event(k, pressed);
                        }
                    }
                }
                Command::Pause(flag) => {
                    PAUSED.store(flag, Ordering::Release);
                    AUDIO_SUSPENDED.store(flag, Ordering::Release);
                }
                Command::Restart => {
                    if let Some(e) = &mut emu {
                        match build(&current, false) {
                            Ok(new) => {
                                *e = new;
                                published_frame = None;
                            }
                            Err(err) => log::error!("restart: rebuild failed: {err:#}"),
                        }
                    }
                }
                Command::Launch { config, whdload } => {
                    let args = LaunchArgs {
                        config,
                        whdload,
                        statefile: None,
                        logfile: current.logfile.clone(),
                    };
                    match build(&args, false) {
                        Ok(new) => {
                            current = args;
                            emu = Some(new);
                            published_frame = None;
                        }
                        Err(err) => log::error!("launch: rebuild failed: {err:#}"),
                    }
                }
                Command::InsertFloppy(drive, path) => {
                    if let Some(e) = &mut emu {
                        match e
                            .emu
                            .bus_mut()
                            .floppy
                            .insert_disk_image(drive, path.clone(), false)
                        {
                            Ok(()) => {
                                log::info!("filesys: df{drive} <- {}", path.display())
                            }
                            Err(err) => {
                                log::warn!("filesys: df{drive} insert failed: {err:#}")
                            }
                        }
                    }
                }
                Command::EjectFloppy(drive) => {
                    if let Some(e) = &mut emu {
                        let _ = e.emu.bus_mut().floppy.eject_disk_image(drive);
                    }
                }
                Command::Port0Joystick(on) => {
                    SHARED.lock().unwrap().port0_joystick = on;
                    if let Some(e) = &mut emu {
                        apply_ports(&mut e.emu);
                    }
                }
                Command::SwapPadPort => {
                    let now = if PAD_PORT.load(Ordering::Acquire) == 1 {
                        0
                    } else {
                        1
                    };
                    PAD_PORT.store(now, Ordering::Release);
                    if let Some(e) = &mut emu {
                        apply_ports(&mut e.emu);
                    }
                }
                Command::CorrectAspect(on) => {
                    CORRECT_ASPECT.store(on, Ordering::Release);
                }
                Command::MouseMove(dx, dy) => {
                    if let Some(e) = &mut emu {
                        let port = mouse_port();
                        e.emu.bus_mut().input.add_mouse_delta(port, dx, dy);
                    }
                }
                Command::MouseButton(button, pressed) => {
                    if let Some(e) = &mut emu {
                        e.emu
                            .bus_mut()
                            .input
                            .set_mouse_button(mouse_port(), button as u8, pressed);
                    }
                }
                Command::SaveSession {
                    state,
                    config,
                    title,
                } => match &mut emu {
                    Some(e) => {
                        if !perform_save_session(e, &state, &config, &title) {
                            log::error!("host: session snapshot FAILED for {}", state.display());
                        }
                    }
                    None => log::error!("host: no machine to snapshot"),
                },
                Command::SaveState(path) => {
                    if let Some(e) = &mut emu {
                        if let Err(err) = e.emu.save_state(&path) {
                            log::warn!("savestate: {} failed: {err:#}", path.display());
                        }
                    }
                }
                Command::PadSync => {
                    if let Some(e) = &mut emu {
                        apply_ports(&mut e.emu);
                    }
                }
            }
        }
        if QUIT.load(Ordering::Acquire) {
            break;
        }

        // ---- run
        if PAUSED.load(Ordering::Acquire) {
            std::thread::sleep(std::time::Duration::from_millis(5));
            continue;
        }
        if beam_watch {
            let now = start.elapsed().as_secs_f64();
            if now >= beam_next {
                beam_next = now + 1.0;
                if let Some(e) = &mut emu {
                    let bus = e.emu.bus();
                    eprintln!(
                        "BEAM t={:.1}s emu_t={:.3} frames={} vpos={} hpos={} pc={:06x} | rendered={:?} published={:?} present_len={} rows={} w={} serial={}",
                        now,
                        bus.emulated_seconds(),
                        bus.emulated_frames(),
                        bus.agnus.vpos,
                        bus.agnus.hpos,
                        e.emu.machine.pc(),
                        e.last_rendered_frame,
                        published_frame,
                        e.present.len(),
                        e.present_rows,
                        e.present_width,
                        crate::framebuffer::uae4arm_host_framebuffer_serial(),
                    );
                }
            }
        }
        if let Some(e) = &mut emu {
            let now_ms = start.elapsed().as_secs_f64() * 1000.0;
            match e.run(now_ms, 8) {
                Ok(_) => {
                    if e.last_rendered_frame != published_frame && !e.present.is_empty() {
                        framebuffer::publish(&e.present, e.present_width, e.present_rows);
                        published_frame = e.last_rendered_frame;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
                Err(err) => {
                    log::error!("run: {err:#}");
                    exit = -1;
                    break;
                }
            }
        } else {
            // No machine (build failed): wait only for Quit.
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
    }
    exit
}

/// The port the mouse answers on: always the one the pad is NOT in.
fn mouse_port() -> usize {
    if PAD_PORT.load(Ordering::Acquire) == 1 {
        0
    } else {
        1
    }
}

/// Re-derives both ports' devices and the pad's full state. Called from
/// the drain only - the port table is the emulation thread's.
fn apply_ports(emu: &mut copperline::emulator::Emulator) {
    let shared = SHARED.lock().unwrap();
    let pad_port = PAD_PORT.load(Ordering::Acquire) as usize;
    let mouse = mouse_port();

    // Which pad the onscreen/external selectors want. onscreen_mode is the
    // Flutter surface (0/1/2); external_mode is the JSEM-style request
    // (3 joystick / 7 CD32); either overrides the other by being newer in
    // the queue order the drain preserves.
    let kind = if shared.onscreen_mode != 0 {
        shared.onscreen_mode
    } else {
        match shared.external_mode {
            7 => 2,
            3 => 1,
            _ => 0,
        }
    };

    let active: Option<&Pad> = shared
        .pads
        .iter()
        .enumerate()
        .find(|(id, p)| p.attached && (kind == 0 || *id == kind as usize))
        .map(|(_, p)| p)
        // The host attached a pad without selecting a mode: drive it anyway.
        .or_else(|| shared.pads.iter().find(|p| p.attached));

    emu.bus_mut()
        .input
        .set_port_device(mouse, PortDevice::Mouse);
    match active {
        Some(pad) => {
            let device = if pad.cd32 {
                PortDevice::Cd32Pad
            } else {
                PortDevice::Joystick
            };
            emu.bus_mut().input.set_port_device(pad_port, device);
            let (u, d, l, r) = pad.merged();
            emu.bus_mut()
                .input
                .set_joystick(pad_port, u, d, l, r, pad.fire, pad.button2);
            if pad.cd32 {
                emu.bus_mut()
                    .input
                    .set_cd32_buttons(pad_port, pad.play, pad.rwd, pad.ffw, pad.green, pad.yellow);
            }
        }
        None => {
            // No host pad: the port sits empty unless a second joystick was
            // asked into port 0.
            if shared.port0_joystick && pad_port != 0 {
                emu.bus_mut().input.set_port_device(0, PortDevice::Joystick);
            } else {
                emu.bus_mut()
                    .input
                    .set_port_device(pad_port, PortDevice::None);
            }
        }
    }
    if shared.port0_joystick && pad_port == 0 {
        // One pad, one port it can be in: the pad wins port 0; a second
        // physical stick has no source in the bridge.
        log::info!("input: port 0 taken by the pad; second joystick idle");
    }
}

/// Writes the state file, then the states/recent.txt index row, in the
/// same ts\ttitle\tstate\tconfig format the Amiberry core writes, capped
/// at five with the dropped rows' files removed.
fn perform_save_session(
    emu: &mut ClEmu,
    state: &std::path::Path,
    config: &std::path::Path,
    title: &str,
) -> bool {
    let Some(directory) = state.parent() else {
        return false;
    };
    if let Err(e) = std::fs::create_dir_all(directory) {
        log::warn!("host: cannot create {}: {e}", directory.display());
        return false;
    }
    if let Err(e) = emu.emu.save_state(state) {
        log::warn!("host: snapshot write failed: {e:#}");
        return false;
    }
    if !state.exists() {
        log::warn!("host: the snapshot was not written to {}", state.display());
        return false;
    }

    let index = directory.join("recent.txt");
    let mut lines: Vec<String> = std::fs::read_to_string(&index)
        .unwrap_or_default()
        .lines()
        .filter(|line| {
            // timestamp \t title \t state \t config - the state path is the
            // field between the second and third tabs.
            let mut tabs = line.match_indices('\t').map(|(i, _)| i);
            match (tabs.nth(1), tabs.next()) {
                (Some(second), Some(third)) => {
                    &line[second + 1..third] != state.to_str().unwrap_or("")
                }
                _ => true,
            }
        })
        .map(str::to_string)
        .collect();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    lines.insert(
        0,
        format!("{now}\t{title}\t{}\t{}", state.display(), config.display()),
    );
    while lines.len() > 5 {
        if let Some(dropped) = lines.pop() {
            let mut tabs = dropped.match_indices('\t').map(|(i, _)| i);
            if let (Some(second), Some(third)) = (tabs.nth(1), tabs.next()) {
                let _ = std::fs::remove_file(&dropped[second + 1..third]);
            }
        }
    }
    match std::fs::write(&index, lines.join("\n") + "\n") {
        Ok(()) => true,
        Err(e) => {
            log::warn!("host: recent.txt not written: {e}");
            false
        }
    }
}

// ------------------------------------------------------------- C surface

fn c_str(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
    }
}

/// Runs the emulator on the calling thread until Quit. Same argv contract
/// as the Amiberry core: --config/--whdload/--statefile/--logfile; unknown
/// flags are logged and ignored.
#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_run(argc: i32, argv: *const *const c_char) -> i32 {
    ensure_logger();
    if RUNNING.swap(true, Ordering::AcqRel) {
        log::error!("startup: a second uae4arm_host_run while one is live; refusing");
        return -1;
    }
    let args: Vec<String> = if argv.is_null() {
        Vec::new()
    } else {
        (1..argc) // skip argv[0]
            .map(|i| c_str(unsafe { *argv.add(i as usize) }))
            .collect()
    };
    let parsed = parse_args(&args);
    if let Some(p) = &parsed.logfile {
        SHARED.lock().unwrap().log_path = Some(p.clone());
        if LOG_ENABLED.load(Ordering::Acquire) {
            reopen_logfile();
        }
    }
    framebuffer::reset();
    PAD_PORT.store(1, Ordering::Release);
    PAUSED.store(false, Ordering::Release);
    AUDIO_SUSPENDED.store(false, Ordering::Release);
    QUIT.store(false, Ordering::Release);
    let code = run_loop(parsed);
    // Clear anything a releasing finger left queued so the next game does
    // not inherit it - the same reset_host_queues the original does.
    QUEUE.lock().unwrap().clear();
    {
        let mut s = SHARED.lock().unwrap();
        for pad in &mut s.pads {
            pad.release_all();
            pad.attached = false;
        }
        s.onscreen_mode = 0;
        s.external_mode = -1;
    }
    RUNNING.store(false, Ordering::Release);
    code
}

#[no_mangle]
pub extern "C" fn uae4arm_host_send_key(amiga_keycode: i32, pressed: bool) {
    enqueue(Command::Key(amiga_keycode, pressed));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_pause(paused: bool) {
    enqueue(Command::Pause(paused));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_restart() {
    enqueue(Command::Restart);
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_launch(
    config_path: *const c_char,
    whdload_archive: *const c_char,
) -> bool {
    let config = c_str(config_path);
    let archive = c_str(whdload_archive);
    if config.is_empty() && archive.is_empty() {
        return false;
    }
    if !config.is_empty() && !std::path::Path::new(&config).exists() {
        return false;
    }
    enqueue(Command::Launch {
        config: (!config.is_empty()).then(|| PathBuf::from(config)),
        whdload: (!archive.is_empty()).then(|| PathBuf::from(archive)),
    });
    true
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_emulation_visible(_visible: bool) {
    // No window: the picture is the host's texture and stays visible.
}

#[no_mangle]
pub extern "C" fn uae4arm_host_quit() {
    QUIT.store(true, Ordering::Release);
    enqueue(Command::Quit);
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_set_session(
    state_path: *const c_char,
    config_path: *const c_char,
    title: *const c_char,
) {
    let mut s = SHARED.lock().unwrap();
    s.session_state = c_str(state_path);
    s.session_config = c_str(config_path);
    let t = c_str(title);
    s.session_title = if t.is_empty() {
        "Amiga session".into()
    } else {
        t
    };
}

#[no_mangle]
pub extern "C" fn uae4arm_host_save_session() -> bool {
    let (state, config, title) = {
        let s = SHARED.lock().unwrap();
        (
            s.session_state.clone(),
            s.session_config.clone(),
            s.session_title.clone(),
        )
    };
    if state.is_empty() || config.is_empty() {
        return false;
    }
    enqueue(Command::SaveSession {
        state: PathBuf::from(state),
        config: PathBuf::from(config),
        title,
    });
    true
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_insert_floppy(drive: i32, path: *const c_char) {
    if !(0..=3).contains(&drive) {
        return;
    }
    let path = c_str(path);
    if path.is_empty() {
        return;
    }
    enqueue(Command::InsertFloppy(drive as usize, PathBuf::from(path)));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_eject_floppy(drive: i32) {
    if !(0..=3).contains(&drive) {
        return;
    }
    enqueue(Command::EjectFloppy(drive as usize));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_get_floppy_count() -> i32 {
    FLOPPY_COUNT.load(Ordering::Acquire)
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_onscreen_controller(mode: i32) {
    SHARED.lock().unwrap().onscreen_mode = mode;
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_external_controller_mode(jsem_mode: i32) {
    SHARED.lock().unwrap().external_mode = jsem_mode;
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_apply_pending_controller_mode() {
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_desktop_fullscreen(_enabled: bool) {
    // No window to put fullscreen; the host decides what it draws.
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_port0_joystick(joystick: bool) {
    enqueue(Command::Port0Joystick(joystick));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_swap_pad_port() {
    enqueue(Command::SwapPadPort);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_pad_port() -> i32 {
    PAD_PORT.load(Ordering::Acquire)
}

#[no_mangle]
pub extern "C" fn uae4arm_host_set_correct_aspect(enabled: bool) {
    enqueue(Command::CorrectAspect(enabled));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_get_correct_aspect() -> bool {
    CORRECT_ASPECT.load(Ordering::Acquire)
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_apply_controller_mapping(
    _sdl_to_target: *const i32,
    _count: i32,
) {
    // No physical-controller table in the bridge; mappings are the app's.
}

#[no_mangle]
pub extern "C" fn uae4arm_host_mouse_move(dx: i32, dy: i32) {
    if dx == 0 && dy == 0 {
        return;
    }
    enqueue(Command::MouseMove(dx, dy));
}

#[no_mangle]
pub extern "C" fn uae4arm_host_mouse_button(button: i32, pressed: bool) {
    if !(0..=2).contains(&button) {
        return;
    }
    enqueue(Command::MouseButton(button, pressed));
}

#[no_mangle]
pub unsafe extern "C" fn uae4arm_host_save_state(path: *const c_char) {
    let path = c_str(path);
    if path.is_empty() {
        return;
    }
    enqueue(Command::SaveState(PathBuf::from(path)));
}

// ---- host-drawn pads ------------------------------------------------------

#[no_mangle]
pub extern "C" fn uae4arm_host_pad_attach(pad: i32) {
    if !(1..=2).contains(&pad) {
        return;
    }
    {
        let mut s = SHARED.lock().unwrap();
        let p = &mut s.pads[pad as usize];
        p.attached = true;
        p.cd32 = pad == 2;
    }
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_drain_pad_events() {
    // This bridge drains every command each loop tick; the export exists
    // for ABI parity with the core the host also binds.
}

#[no_mangle]
pub extern "C" fn uae4arm_host_pad_axis(pad: i32, axis: i32, value: i32) {
    if !(1..=2).contains(&pad) || !(0..=1).contains(&axis) {
        return;
    }
    {
        let mut s = SHARED.lock().unwrap();
        s.pads[pad as usize].axis[axis as usize] = value.clamp(-32767, 32767);
    }
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_pad_direction(
    pad: i32,
    left: bool,
    right: bool,
    up: bool,
    down: bool,
) {
    if !(1..=2).contains(&pad) {
        return;
    }
    {
        let mut s = SHARED.lock().unwrap();
        let p = &mut s.pads[pad as usize];
        p.left = left;
        p.right = right;
        p.up = up;
        p.down = down;
    }
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_pad_button(pad: i32, button: i32, pressed: bool) {
    if !(1..=2).contains(&pad) {
        return;
    }
    {
        let mut s = SHARED.lock().unwrap();
        let p = &mut s.pads[pad as usize];
        if p.cd32 {
            match button {
                0 => p.fire = pressed,    // red
                1 => p.button2 = pressed, // blue
                2 => p.green = pressed,
                3 => p.yellow = pressed,
                4 => p.play = pressed,
                5 => p.rwd = pressed,
                6 => p.ffw = pressed,
                _ => return,
            }
        } else {
            match button {
                0 => p.fire = pressed,
                1 => p.button2 = pressed,
                _ => return,
            }
        }
    }
    enqueue(Command::PadSync);
}

#[no_mangle]
pub extern "C" fn uae4arm_host_pad_release_all(pad: i32) {
    if !(1..=2).contains(&pad) {
        return;
    }
    {
        let mut s = SHARED.lock().unwrap();
        s.pads[pad as usize].release_all();
    }
    enqueue(Command::PadSync);
}

// ---- music ----------------------------------------------------------------
// The launcher binds these on whichever core it loaded. The ProTracker
// replayer lives in the Amiberry core; over Copperline they are benign
// no-ops so an accidental binding fails quietly rather than unresolved.

#[no_mangle]
pub extern "C" fn uae4arm_host_music_play(_path: *const c_char) -> bool {
    false
}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_stop() {}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_set_paused(_paused: bool) {}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_release_audio() {}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_is_paused() -> bool {
    false
}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_is_playing() -> bool {
    false
}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_title() -> *const c_char {
    c"".as_ptr()
}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_level() -> f32 {
    0.0
}
#[no_mangle]
pub extern "C" fn uae4arm_host_music_set_volume(_volume: f32) {}
