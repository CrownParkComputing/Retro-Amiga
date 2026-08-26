import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui show Size;

import 'package:ffi/ffi.dart';

/// The emulator core, running INSIDE the launcher process.
///
/// Why this exists: the Android app used to start a second, full-screen
/// Activity for every game, because SDL owns its window and its window owns
/// the screen. Pressing play wiped the launcher, and what came back was a
/// lookalike drawn by a separate Flutter engine.
///
/// The core can run without a window. `gfx_platform_present_frame()` in the
/// fork hands each finished Amiga frame to the platform and, if the platform
/// takes it, SDL never presents -- the libretro build has always worked this
/// way. `host_framebuffer.cpp` implements that tap for this build, so the
/// picture arrives here as pixels and the launcher can draw it in a panel
/// beside its own chrome, on one screen. SDL's video driver is set to
/// `offscreen` so SDL_Init needs no Activity and no surface.
///
/// The core's own entry point never returns, so it runs on its own isolate --
/// which on the Dart side means its own thread. Everything else here is a
/// plain call from the UI isolate: the frame buffer and the host API live in
/// process memory, which both isolates share.
class AmigaCore {
  AmigaCore._(this._lib);

  final DynamicLibrary _lib;

  static AmigaCore? _instance;

  /// Where this platform keeps the core, or null where there is none (tests,
  /// and platforms the core does not build for yet).
  ///
  /// One resolver for every host, because the library IS the same everywhere:
  /// the same CMake target, the same uae4arm_host API, the same framebuffer
  /// tap. Only the packaging differs -- the loader's search path on Android,
  /// lib/ beside the executable on Linux, Frameworks/ on iOS.
  static String? _libraryPath() {
    if (Platform.isAndroid) return 'libuae4arm.so';
    if (Platform.isIOS) {
      // Relative to the loader's rpath, which points at Frameworks/.
      return 'libuae4arm.framework/libuae4arm';
    }
    if (Platform.isLinux) {
      // An explicit override first, for harnesses and odd layouts.
      final String? env = Platform.environment['UAE4ARM_CORE'];
      if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
      // The installed bundle: <exe>/lib/libuae4arm.so, the same file the GTK
      // runner dlopens.
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      final String bundled = '$exeDir/lib/libuae4arm.so';
      if (File(bundled).existsSync()) return bundled;
      // A dev run (`flutter run` from app/): the harness build in the repo.
      Directory dir = Directory.current;
      for (int i = 0; i < 4; i++) {
        final String dev = '${dir.path}/build-linux/libuae4arm.so';
        if (File(dev).existsSync()) return dev;
        dir = dir.parent;
      }
      return null;
    }
    return null;
  }

  /// The resolved path, kept so the core isolate opens the SAME library the
  /// UI isolate did -- they share process memory only if they share the file.
  static String? _openedPath;

  /// Opens the core, or null where there is none to open (tests have no core
  /// at all, and some desktop platforms still run it as a child process).
  static AmigaCore? open() {
    if (_instance != null) return _instance;
    final String? path = _libraryPath();
    if (path == null) return null;
    try {
      final AmigaCore core = AmigaCore._(DynamicLibrary.open(path));
      _openedPath = path;
      return _instance = core;
    } on ArgumentError {
      return null;
    }
  }

  late final void Function(bool) _setFramebufferOutput = _lib
      .lookupFunction<Void Function(Bool), void Function(bool)>(
        'uae4arm_host_set_framebuffer_output',
      );

  late final void Function(bool) _setLogfileEnabled = _lib
      .lookupFunction<Void Function(Bool), void Function(bool)>(
        'uae4arm_host_set_logfile_enabled',
      );

  late final Pointer<Utf8> Function() _logfilePath = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'uae4arm_host_logfile_path',
      );

  /// Where the core is writing its log, or null when it is not writing one.
  /// The Logs page shows it: on a handheld there is no console, and logcat
  /// needs a computer and a cable.
  String? get logfilePath {
    try {
      final p = _logfilePath();
      if (p == nullptr) return null;
      final path = p.toDartString();
      return path.isEmpty ? null : path;
    } on ArgumentError {
      return null;
    }
  }

  late final int Function(
    Pointer<Uint32>,
    int,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Uint64>,
  )
  _copyFramebuffer = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Uint32>,
          Int32,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Uint64>,
        ),
        int Function(
          Pointer<Uint32>,
          int,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Uint64>,
        )
      >('uae4arm_host_copy_framebuffer');

  late final int Function() _framebufferSerial = _lib
      .lookupFunction<Uint64 Function(), int Function()>(
        'uae4arm_host_framebuffer_serial',
      );

  late final int Function() _texturePosted = _lib
      .lookupFunction<Uint64 Function(), int Function()>(
        'uae4arm_host_texture_posted',
      );

  late final void Function(Pointer<Int32>, Pointer<Int32>) _framebufferSize =
      _lib
          .lookupFunction<
            Void Function(Pointer<Int32>, Pointer<Int32>),
            void Function(Pointer<Int32>, Pointer<Int32>)
          >('uae4arm_host_framebuffer_size');

  /// Reused across frames; grows when the Amiga picks a bigger mode.
  Pointer<Uint32> _frameBuf = nullptr;
  int _frameCap = 0;

  /// A byte view over [_frameBuf], rebuilt only when the buffer is
  /// reallocated. [frame] hands a sub-view of this out rather than a fresh
  /// list: at 752x576 a copy is 1.7MB, and allocating that per frame at 30Hz
  /// put ~50MB/s of short-lived garbage through the young generation, which
  /// is most of what made the in-process picture stutter on modest Androids.
  Uint8List? _frameBytes;
  int _lastCopiedSerial = 0;
  final Pointer<Int32> _frameWidth = calloc<Int32>();
  final Pointer<Int32> _frameHeight = calloc<Int32>();
  final Pointer<Uint64> _frameSerial = calloc<Uint64>();

  late final void Function() _quit = _lib
      .lookupFunction<Void Function(), void Function()>('uae4arm_host_quit');

  late final void Function(bool) _setPaused = _lib
      .lookupFunction<Void Function(Bool), void Function(bool)>(
        'uae4arm_host_set_pause',
      );

  /// Whether this core is new enough to hand frames back. A core built before
  /// host_framebuffer.cpp existed simply has no such symbol, and the app must
  /// fall back to the Activity rather than fail to start.
  bool get hasFramebufferOutput {
    try {
      _lib.lookup<NativeFunction<Void Function(Bool)>>(
        'uae4arm_host_set_framebuffer_output',
      );
      return true;
    } on ArgumentError {
      return false;
    }
  }

  bool _running = false;
  bool get isRunning => _running;

  /// Completes when the core isolate exits -- which is when uae4arm_host_run
  /// has RETURNED, not merely been asked to quit. Starting a second run
  /// before the first returns would be two emulators in one set of statics.
  Completer<void>? _exited;

  /// Starts the core on its own isolate. Returns once the isolate is spawned;
  /// the core itself runs until [quit].
  ///
  /// If a previous session is still winding down (or still playing), it is
  /// quit and WAITED for first. This is the launcher's serialisation of the
  /// run-quit-run lifecycle the Linux harness exercises natively.
  Future<void> start(List<String> args) async {
    if (_running) {
      await stopAndWait();
    } else if (_exited != null && !_exited!.isCompleted) {
      await _exited!.future.timeout(const Duration(seconds: 20));
    }
    _running = true;
    // On before the core starts, so the log covers the startup that fails.
    try {
      _setLogfileEnabled(true);
    } on ArgumentError {
      // Older core: logcat only.
    }
    _setFramebufferOutput(true);
    // Headless is set natively by _setFramebufferOutput, before the core's
    // graphics_setup() runs. A `-s headless=yes` here arrives too late: the
    // core builds its surface windowed first and only then parses the
    // command line, and the late flip is what left every published frame
    // empty.
    final exited = _exited = Completer<void>();
    final onExit = ReceivePort();
    onExit.listen((_) {
      onExit.close();
      _running = false;
      if (!exited.isCompleted) exited.complete();
    });
    await Isolate.spawn(_runCore, <String>[
      _openedPath!,
      ...args,
    ], onExit: onExit.sendPort);
  }

  late final void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
  _setSession = _lib
      .lookupFunction<
        Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
      >('uae4arm_host_set_session');
  late final bool Function() _saveSession = _lib
      .lookupFunction<Bool Function(), bool Function()>(
        'uae4arm_host_save_session',
      );

  /// Tells the core where this session's snapshot belongs, so [saveSession]
  /// has somewhere to put it and the Resume shelf has something to list.
  void setSession(String statePath, String configPath, String title) {
    final s = statePath.toNativeUtf8();
    final c = configPath.toNativeUtf8();
    final t = title.toNativeUtf8();
    try {
      _setSession(s, c, t);
    } finally {
      calloc.free(s);
      calloc.free(c);
      calloc.free(t);
    }
  }

  /// Writes the session's save state and records it on the Resume shelf.
  /// False when no session was set - a bare Workbench boot has no place to
  /// go back to, and that is fine.
  bool saveSession() {
    try {
      return _saveSession();
    } on ArgumentError {
      return false;
    }
  }

  /// Quits the core and waits until its run loop has actually returned.
  Future<void> stopAndWait() async {
    if (!_running) return;
    quit();
    final exited = _exited;
    if (exited != null && !exited.isCompleted) {
      await exited.future.timeout(const Duration(seconds: 20));
    }
  }

  void setPaused(bool paused) => _setPaused(paused);

  // Input and media, straight into the host API. These are the same doors the
  // :sdl Activity's JNI goes through; in-process there is no Activity, so the
  // panel's toolbar and touches call them directly.
  late final void Function(int, bool) _sendKey = _lib
      .lookupFunction<Void Function(Int32, Bool), void Function(int, bool)>(
        'uae4arm_host_send_key',
      );
  late final void Function(int, int) _mouseMove = _lib
      .lookupFunction<Void Function(Int32, Int32), void Function(int, int)>(
        'uae4arm_host_mouse_move',
      );
  late final void Function(int, bool) _mouseButton = _lib
      .lookupFunction<Void Function(Int32, Bool), void Function(int, bool)>(
        'uae4arm_host_mouse_button',
      );
  late final void Function(int, Pointer<Utf8>) _insertFloppy = _lib
      .lookupFunction<
        Void Function(Int32, Pointer<Utf8>),
        void Function(int, Pointer<Utf8>)
      >('uae4arm_host_insert_floppy');
  late final int Function() _floppyCount = _lib
      .lookupFunction<Int32 Function(), int Function()>(
        'uae4arm_host_get_floppy_count',
      );

  void sendKey(int amigaKeycode, bool pressed) =>
      _sendKey(amigaKeycode, pressed);
  late final void Function(int) _padAttach = _lib
      .lookupFunction<Void Function(Int32), void Function(int)>(
        'uae4arm_host_pad_attach',
      );
  late final void Function(int, bool, bool, bool, bool) _padDirection = _lib
      .lookupFunction<
        Void Function(Int32, Bool, Bool, Bool, Bool),
        void Function(int, bool, bool, bool, bool)
      >('uae4arm_host_pad_direction');
  late final void Function(int, int, bool) _padButton = _lib
      .lookupFunction<
        Void Function(Int32, Int32, Bool),
        void Function(int, int, bool)
      >('uae4arm_host_pad_button');
  late final void Function(int) _padReleaseAll = _lib
      .lookupFunction<Void Function(Int32), void Function(int)>(
        'uae4arm_host_pad_release_all',
      );
  late final void Function(int) _setOnscreenController = _lib
      .lookupFunction<Void Function(Int32), void Function(int)>(
        'uae4arm_host_set_onscreen_controller',
      );
  late final void Function(int) _setExternalControllerMode = _lib
      .lookupFunction<Void Function(Int32), void Function(int)>(
        'uae4arm_host_set_external_controller_mode',
      );

  /// UAE4ARM_HOST_PAD_JOYSTICK / _CD32.
  void padAttach(int pad) => _padAttach(pad);
  void padDirection(int pad, bool up, bool down, bool left, bool right) =>
      _padDirection(pad, left, right, up, down);
  void padButton(int pad, int button, bool pressed) =>
      _padButton(pad, button, pressed);
  void padReleaseAll(int pad) => _padReleaseAll(pad);

  /// 0 = none, 1 = on-screen joystick, 2 = on-screen CD32 pad.
  void setOnscreenController(int mode) => _setOnscreenController(mode);

  /// JSEM_MODE for port 1: 3 = joystick, 7 = CD32 pad.
  void setPortMode(int jsemMode) => _setExternalControllerMode(jsemMode);

  late final void Function() _swapPadPort = _lib
      .lookupFunction<Void Function(), void Function()>(
        'uae4arm_host_swap_pad_port',
      );
  late final int Function() _padPort = _lib
      .lookupFunction<Int32 Function(), int Function()>(
        'uae4arm_host_pad_port',
      );

  /// Moves the pad to the Amiga's other port, live.
  ///
  /// Most games read a joystick in port 1, which is where the pad starts. A
  /// large minority of the older ones read port 0 -- the mouse port -- and on
  /// real hardware you moved the plug. Without this they cannot be played at
  /// all: the controls work perfectly and the game is not listening to them.
  ///
  /// Silently does nothing on a core too old to have the export, which is the
  /// same as the machine it was built for having no way to swap.
  void swapPadPort() {
    try {
      _swapPadPort();
    } on ArgumentError {
      // Older core: the button will simply not move anything.
    }
  }

  /// Which port the pad is in: 1 by default, 0 after an odd number of swaps.
  int get padPort {
    try {
      return _padPort();
    } on ArgumentError {
      return 1;
    }
  }

  void mouseMove(int dx, int dy) => _mouseMove(dx, dy);
  void mouseButton(int button, bool pressed) => _mouseButton(button, pressed);

  /// How many floppy drives the running machine has; at least one, because a
  /// swap button that reports none could never be used.
  int get floppyCount {
    final n = _floppyCount();
    return n <= 0 ? 1 : n;
  }

  void insertFloppy(int drive, String path) {
    final p = path.toNativeUtf8();
    try {
      _insertFloppy(drive, p);
    } finally {
      calloc.free(p);
    }
  }

  void quit() {
    if (!_running) return;
    _running = false;
    _quit();
  }

  /// The Amiga's current mode, without touching a pixel.
  ///
  /// The texture path needs this and only this: the frames themselves are
  /// pushed to the compositor by the platform, but the panel still has to know
  /// the shape to fit the picture into, and the Amiga changes mode mid-game.
  /// Cheap enough to ask every vsync -- two stores and a mutex the publisher
  /// holds only for a pointer swap.
  ///
  /// `Size.zero` before the first frame, or on a core too old to have the
  /// symbol.
  ui.Size frameSize() {
    try {
      _framebufferSize(_frameWidth, _frameHeight);
    } on ArgumentError {
      return ui.Size.zero;
    }
    return ui.Size(
      _frameWidth.value.toDouble(),
      _frameHeight.value.toDouble(),
    );
  }

  /// The serial of the last frame the platform's texture sink accepted, or 0
  /// if none ever has.
  ///
  /// The panel uses this to decide whether the texture path is really working.
  /// It is not enough that a texture was created: a platform can hand back a
  /// surface that cannot be written to -- Flutter's SurfaceProducer is an
  /// ImageReader in ImageFormat.PRIVATE, which refuses a CPU lock -- and the
  /// symptom is a black picture with perfectly good sound, because nothing in
  /// the path treats a refused present as an error. If frames are being
  /// published and none is being posted, the panel drops the texture and takes
  /// the copy-and-decode route instead.
  ///
  /// 0 on a core too old to have the symbol, which reads the same as "not
  /// working" and falls back for the same reason.
  int texturePostedSerial() {
    try {
      return _texturePosted();
    } on ArgumentError {
      return 0;
    }
  }

  /// The serial of the newest frame the core has published. 0 before the first.
  int publishedSerial() {
    try {
      return _framebufferSerial();
    } on ArgumentError {
      return 0;
    }
  }

  /// The current frame, or null before the core has drawn one.
  ///
  /// Copied natively under the publisher's lock, so width, height and pixels
  /// all describe the SAME frame. Reading them separately raced the swap --
  /// the Amiga changes mode at will (752x576, then 756x574) and a tight copy
  /// made at the wrong width is the picture smeared diagonally across the
  /// panel, which is exactly what the first frames through looked like.
  AmigaFrame? frame() {
    // Most polls happen while paused, while a decode is finishing, or before
    // the next emulated frame. Checking one atomic counter first avoids a
    // full native memcpy and Dart allocation for those unchanged frames.
    final int available = _framebufferSerial();
    if (available == 0 || available == _lastCopiedSerial) return null;

    // First call with the current buffer; if it is too small the call
    // reports the needed size and we grow and retry once.
    var n = _copyFramebuffer(
      _frameBuf,
      _frameCap,
      _frameWidth,
      _frameHeight,
      _frameSerial,
    );
    if (n == 0) {
      final need = _frameWidth.value * _frameHeight.value;
      if (need <= 0) return null;
      if (need > _frameCap) {
        if (_frameBuf != nullptr) calloc.free(_frameBuf);
        _frameCap = need + (need >> 2); // headroom for small mode changes
        _frameBuf = calloc<Uint32>(_frameCap);
        _frameBytes = null; // the old view points at freed memory
        n = _copyFramebuffer(
          _frameBuf,
          _frameCap,
          _frameWidth,
          _frameHeight,
          _frameSerial,
        );
      }
      if (n == 0) return null;
    }
    _lastCopiedSerial = _frameSerial.value;
    // A view over the native buffer, NOT a copy. See [AmigaFrame.pixels] for
    // the lifetime this places on the caller.
    final Uint8List bytes = _frameBytes ??= _frameBuf
        .cast<Uint8>()
        .asTypedList(_frameCap * 4);
    return AmigaFrame(
      width: _frameWidth.value,
      height: _frameHeight.value,
      serial: _frameSerial.value,
      pixels: Uint8List.sublistView(bytes, 0, n * 4),
    );
  }
}

/// One published frame, copied out of the core under the publisher's lock.
class AmigaFrame {
  final int width;
  final int height;
  final int serial;

  /// The pixels, as SDL_PIXELFORMAT_ABGR8888 -- which on a little-endian
  /// machine is R,G,B,A in memory, i.e. Flutter's rgba8888.
  ///
  /// BORROWED, not owned: this is a view straight onto the core's staging
  /// buffer, and the next [AmigaCore.frame] overwrites it in place. Anything
  /// that outlives the current frame must copy. The one consumer,
  /// AmigaScreenView, does not poll again until its upload has finished, so
  /// the buffer is quiet for as long as the view is in use.
  final Uint8List pixels;

  const AmigaFrame({
    required this.width,
    required this.height,
    required this.serial,
    required this.pixels,
  });
}

/// Runs the core's entry point. Never returns until the core quits, which is
/// why it owns this isolate. The first element of [pathAndArgs] is the
/// library path [open] resolved; the rest is the core's argv.
void _runCore(List<String> pathAndArgs) {
  final lib = DynamicLibrary.open(pathAndArgs.first);
  final args = pathAndArgs.sublist(1);

  // Offscreen video: SDL_Init(VIDEO) must succeed with no Activity and no
  // surface. The driver is compiled into the core (SDL_OFFSCREEN_* symbols are
  // in the binary); without this SDL picks its Android driver and asks
  // SDLActivity for a window that does not exist in this process.
  final setenv = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)
      >('setenv');
  final name = 'SDL_VIDEODRIVER'.toNativeUtf8();
  final value = 'offscreen'.toNativeUtf8();
  setenv(name, value, 1);
  calloc.free(name);
  calloc.free(value);

  final run = lib
      .lookupFunction<
        Int32 Function(Int32, Pointer<Pointer<Utf8>>),
        int Function(int, Pointer<Pointer<Utf8>>)
      >('uae4arm_host_run');

  final argv = calloc<Pointer<Utf8>>(args.length + 1);
  for (var i = 0; i < args.length; i++) {
    argv[i] = args[i].toNativeUtf8();
  }
  argv[args.length] = nullptr;
  run(args.length, argv);
}
