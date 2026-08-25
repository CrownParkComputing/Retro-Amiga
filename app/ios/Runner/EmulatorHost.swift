import Foundation
import UIKit

/// Starts the emulator core inside this app.
///
/// Android launches a separate activity for this; iOS has no such thing, so
/// the core runs in-process. It is a dylib in the bundle's Frameworks
/// directory rather than a linked dependency, because iosbox regenerates its
/// SwiftPM package on every build and there is no supported way to add a link
/// flag to the Runner target - the same reason the dylib is copied in after
/// the fact.
///
/// The core is entered through uae4arm_host_run, a plain C name added for
/// exactly this: amiberry_main is C++ and exports mangled, which a dlsym'ing
/// host would otherwise have to hardcode.
final class EmulatorHost {

  static let shared = EmulatorHost()

  private var handle: UnsafeMutableRawPointer?
  private var running = false

  /// True from X being pressed until the core actually returns. A new launch
  /// during this window waits instead of being refused.
  private var quitting = false

  private typealias RunFn = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
  private typealias SetMainReadyFn = @convention(c) () -> Void

  /// Whether the core loaded. Reported to Dart so the UI can say what is wrong
  /// rather than fail silently.
  func coreAvailable() -> Bool {
    return load() != nil
  }

  private func load() -> UnsafeMutableRawPointer? {
    if let handle = handle { return handle }
    // A .framework bundle, not a bare .dylib. App Store validation rejects an
    // upload carrying a loose dylib in Frameworks/ with "90426: Invalid Swift
    // Support. The SwiftSupport folder is missing" -- historically the only
    // bare dylibs there were the Swift runtime, so Apple's scanner infers an
    // embedded runtime and demands a folder Xcode will never generate for a
    // 15.0 deployment target. The rejection is unfixable while the bare dylib
    // is there, and `altool --validate-app` passes every time because the
    // check only runs server-side after the upload.
    let path = Bundle.main.bundlePath + "/Frameworks/libuae4arm.framework/libuae4arm"
    guard let opened = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
      NSLog("uae4arm: dlopen failed: %@", String(cString: dlerror()))
      return nil
    }
    handle = opened
    return opened
  }

  /// Starts emulation with [args], the same argv the command line takes.
  ///
  /// Returns as soon as the core has been *scheduled*, not once it has
  /// finished. The core's main loop does not return until emulation ends, and
  /// it has to run on the main thread: SDL's iOS video backend talks to UIKit,
  /// which is main-thread-only, and running it anywhere else aborts with
  /// "threading violation: expected the main thread" the moment SDL_Init
  /// reaches the UIKit backend.
  ///
  /// Blocking the main thread is not the mistake it looks like. It is how
  /// every SDL app on iOS runs: SDL_RunApp calls main() and never returns, and
  /// SDL_PumpEvents drives the run loop itself from inside the game loop
  /// (UIKit_PumpEvents -> CFRunLoopRunInMode). So UIKit keeps delivering
  /// events; it is Flutter that stops, which is fine while SDL's window is the
  /// one on screen.
  ///
  /// It is dispatched rather than called inline so the method channel can send
  /// its reply back to Dart first - the reply would otherwise be stuck behind
  /// a main thread that never comes back.
  func launch(args: [String]) throws {
    if running && !quitting {
      throw HostError.message("Emulation is already running.")
    }
    // A second game runs the core again. That used to hang: SDL_Quit at the
    // end of a run tears down a UIKit backend that never comes back, so the
    // next SDL_Init blocked and took the app with it. The core keeps SDL
    // initialised on iOS now (osdep_platform_shutdown_sdl), which is what
    // lets this run again at all - a Linux harness runs the same core twice
    // with a real window, which is how that was pinned to the backend rather
    // than to the emulator.
    guard let handle = load() else {
      throw HostError.message("The emulator core could not be loaded.")
    }
    guard let runSymbol = dlsym(handle, "uae4arm_host_run") else {
      throw HostError.message("The core does not export uae4arm_host_run.")
    }

    // SDL normally learns its main thread from SDL_RunApp, which this app does
    // not use because Flutter owns UIApplicationMain. Telling SDL the main
    // thread is ready is what lets SDL_Init proceed without it.
    if let readySymbol = dlsym(handle, "SDL_SetMainReady") {
      unsafeBitCast(readySymbol, to: SetMainReadyFn.self)()
    }

    controls.onQuit = { [weak self] in self?.quit() }
    controls.onPause = { [weak self] paused in self?.setPaused(paused) }
    controls.onKey = { [weak self] code, pressed in
      self?.sendKey(code, pressed: pressed)
    }
    controls.onPadAttach = { [weak self] pad in
      // Register the device AND flip the pad pref: the pref change is what
      // reruns the port mapping, and without it the device exists but no
      // port listens - directions posted into silence.
      self?.padCall("uae4arm_host_pad_attach", pad)
      self?.padCall("uae4arm_host_set_onscreen_controller", pad)
    }
    controls.onPadDetach = { [weak self] pad in
      self?.padCall("uae4arm_host_pad_release_all", pad)
      self?.padCall("uae4arm_host_set_onscreen_controller", 0)
    }
    controls.onPadButton = { [weak self] pad, button, pressed in
      guard let self = self, let fn = self.symbol("uae4arm_host_pad_button") else { return }
      unsafeBitCast(fn, to: PadButtonFn.self)(pad, button, pressed)
    }
    controls.onPadDirection = { [weak self] pad, l, r, u, d in
      guard let self = self, let fn = self.symbol("uae4arm_host_pad_direction") else { return }
      unsafeBitCast(fn, to: PadDirectionFn.self)(pad, l, r, u, d)
    }
    controls.onMouseMove = { [weak self] dx, dy in
      guard let self = self, let fn = self.symbol("uae4arm_host_mouse_move") else { return }
      unsafeBitCast(fn, to: MouseMoveFn.self)(dx, dy)
    }
    controls.onMouseButton = { [weak self] button, pressed in
      guard let self = self, let fn = self.symbol("uae4arm_host_mouse_button") else { return }
      unsafeBitCast(fn, to: PadButtonlessFn.self)(button, pressed)
    }
    controls.onTwoPlayers = { [weak self] on in
      guard let self = self, let fn = self.symbol("uae4arm_host_set_port0_joystick") else { return }
      unsafeBitCast(fn, to: BoolSetFn.self)(on)
    }

    hasRun = true
    let run = unsafeBitCast(runSymbol, to: RunFn.self)
    // argv[0] is the program name, as the core's option parser expects.
    let argv: [String] = ["Retro-Amiga"] + args
    startWhenIdle(run: run, argv: argv, attemptsLeft: 50)
  }

  /// Starts the core once the previous run has actually let go.
  ///
  /// X ends the session, but the core takes a moment to wind down after
  /// uae_quit - and a player who taps the next game inside that moment used
  /// to be told "Emulation is already running" about a game they had just
  /// left. Waiting here is invisible; the error was not.
  private func startWhenIdle(
    run: @escaping RunFn, argv: [String], attemptsLeft: Int
  ) {
    if running {
      guard attemptsLeft > 0 else {
        NSLog("uae4arm: previous run never ended; not starting another")
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.startWhenIdle(run: run, argv: argv, attemptsLeft: attemptsLeft - 1)
      }
      return
    }
    running = true
    quitting = false

    DispatchQueue.main.async { [weak self] in
      // Copies that outlive this scope: the core keeps the pointers.
      var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
      cStrings.append(nil)

      // The controls go up here, at the last moment before the core takes the
      // main thread, so pause and X are only ever on screen when a session is
      // genuinely being entered - and once the core has the thread, there
      // would be no later moment to add them.
      self?.controls.show()

      NSLog("uae4arm: starting the core with %d arguments", argv.count)
      let status = cStrings.withUnsafeMutableBufferPointer { buffer -> Int32 in
        return run(Int32(argv.count), buffer.baseAddress)
      }
      NSLog("uae4arm: the core returned %d", status)

      for pointer in cStrings where pointer != nil {
        free(pointer)
      }
      // Truth first, appearance second: the state says "ended" before the
      // buttons go, so the visible session can never outlive the real one.
      self?.running = false
      self?.quitting = false
      self?.controls.hide()
    }
  }

  // MARK: - Music
  //
  // The launcher's ProTracker player lives in the same dylib but is
  // independent of emulation: it opens its own audio device and runs whether
  // or not a machine is running. So these load the core without starting it.

  private typealias LaunchFn =
    @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
  private typealias PlayFn = @convention(c) (UnsafePointer<CChar>?) -> Bool
  private typealias VoidFn = @convention(c) () -> Void
  private typealias BoolFn = @convention(c) () -> Bool
  private typealias SetBoolFn = @convention(c) (Bool) -> Void
  private typealias FloatFn = @convention(c) () -> Float
  private typealias SetFloatFn = @convention(c) (Float) -> Void
  private typealias StringFn = @convention(c) () -> UnsafePointer<CChar>?

  /// Whether the core has been run in this process. See [launch].
  private var hasRun = false

  /// The launcher's own window, handed over by the scene delegate.
  weak var launcherWindow: UIWindow?

  /// The in-game controls, which iOS has to draw itself - see
  /// EmulatorControls for why Flutter cannot.
  private let controls = EmulatorControls()

  /// Leaves the game and gives the screen back to the launcher.
  ///
  /// The core is paused rather than ended, because ending it means it can
  /// never run again in this process. Its paused loop still pumps events - it
  /// polls SDL and sleeps 10ms - so the run loop keeps turning and Flutter
  /// keeps drawing.
  ///
  /// What did NOT work first time was the window handling: the launcher drew
  /// but took no touches, because SDL's window was still the key window and
  /// the one being restored was "whatever was key when the game started",
  /// which by then was SDL's own. The launcher's window is held explicitly
  /// now, and SDL's is put out of the way rather than merely hidden.
  func quit() {
    // Ends the core - X closes the session; pause is what pauses. Pausing
    // here instead left the launcher untouchable, and an app that has to be
    // force-quit is worse than one that has to be reopened between games.
    quitting = true
    if let fn = symbol("uae4arm_host_quit") {
      unsafeBitCast(fn, to: VoidFn.self)()
    }
    controls.hide()
    // SDL's window is hidden but still in the scene, and a hidden window that
    // is still key keeps taking the touches. Everything that is not the
    // launcher is put out of the way, then the launcher is made key again.
    setEmulatorWindowsInteractive(false)
    launcherWindow?.isHidden = false
    launcherWindow?.makeKeyAndVisible()
  }

  /// Hands the running core a different machine.
  private func restart(args: [String]) throws {
    guard let fn = symbol("uae4arm_host_launch") else {
      throw HostError.message("This core cannot start a second game.")
    }
    let config = value(after: "--config", in: args) ?? ""
    let archive = value(after: "--autoload", in: args) ?? ""
    let started = config.withCString { configPointer in
      archive.withCString { archivePointer in
        unsafeBitCast(fn, to: LaunchFn.self)(configPointer, archivePointer)
      }
    }
    if !started {
      throw HostError.message("That setup could not be loaded.")
    }
    setEmulatorWindowsInteractive(true)
    setEmulationVisible(true)
    setPaused(false)
    controls.show()
  }

  /// The argument after [flag], which is how the launcher passes the config
  /// and the archive.
  private func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
      return nil
    }
    return args[index + 1]
  }

  /// Turns touch handling on or off for every window that is not the
  /// launcher's - which in this app means SDL's, and the controls' while they
  /// are up.
  private func setEmulatorWindowsInteractive(_ enabled: Bool) {
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      for window in scene.windows where window !== launcherWindow {
        window.isUserInteractionEnabled = enabled
      }
    }
  }

  func setEmulationVisible(_ visible: Bool) {
    guard let fn = symbol("uae4arm_host_set_emulation_visible") else { return }
    unsafeBitCast(fn, to: SetBoolFn.self)(visible)
  }

  func setPaused(_ paused: Bool) {
    guard let fn = symbol("uae4arm_host_set_pause") else { return }
    unsafeBitCast(fn, to: SetBoolFn.self)(paused)
  }

  // MARK: - In-game controls
  //
  // The pad is OUR designed one, drawn by PadOverlayView from the layout the
  // Settings designer saves, feeding the core's virtual-pad entry points -
  // the same route Android's Flutter pad takes. The core's own Amiberry-drawn
  // overlay is not used.

  private typealias KeyFn = @convention(c) (Int32, Bool) -> Void
  private typealias IntFn = @convention(c) (Int32) -> Void
  private typealias PadButtonFn = @convention(c) (Int32, Int32, Bool) -> Void
  private typealias PadDirectionFn = @convention(c) (Int32, Bool, Bool, Bool, Bool) -> Void
  private typealias MouseMoveFn = @convention(c) (Int32, Int32) -> Void
  private typealias PadButtonlessFn = @convention(c) (Int32, Bool) -> Void
  private typealias BoolSetFn = @convention(c) (Bool) -> Void

  private func sendKey(_ code: Int32, pressed: Bool) {
    guard let fn = symbol("uae4arm_host_send_key") else { return }
    unsafeBitCast(fn, to: KeyFn.self)(code, pressed)
  }

  private func padCall(_ name: String, _ pad: Int32) {
    guard let fn = symbol(name) else { return }
    unsafeBitCast(fn, to: IntFn.self)(pad)
  }

  private func symbol(_ name: String) -> UnsafeMutableRawPointer? {
    guard let handle = load() else { return nil }
    return dlsym(handle, name)
  }

  func musicPlay(path: String) -> Bool {
    guard let fn = symbol("uae4arm_host_music_play") else { return false }
    return path.withCString { unsafeBitCast(fn, to: PlayFn.self)($0) }
  }

  func musicStop() {
    guard let fn = symbol("uae4arm_host_music_stop") else { return }
    unsafeBitCast(fn, to: VoidFn.self)()
  }

  func musicReleaseAudio() {
    guard let fn = symbol("uae4arm_host_music_release_audio") else { return }
    unsafeBitCast(fn, to: VoidFn.self)()
  }

  func musicSetPaused(_ paused: Bool) {
    guard let fn = symbol("uae4arm_host_music_set_paused") else { return }
    unsafeBitCast(fn, to: SetBoolFn.self)(paused)
  }

  func musicSetVolume(_ volume: Double) {
    guard let fn = symbol("uae4arm_host_music_set_volume") else { return }
    unsafeBitCast(fn, to: SetFloatFn.self)(Float(volume))
  }

  /// Everything the music UI polls, in one call - it asks several times a
  /// second and a channel round trip per field would be wasteful.
  func musicState() -> [String: Any] {
    func flag(_ name: String) -> Bool {
      guard let fn = symbol(name) else { return false }
      return unsafeBitCast(fn, to: BoolFn.self)()
    }
    var title = ""
    if let fn = symbol("uae4arm_host_music_title"),
       let raw = unsafeBitCast(fn, to: StringFn.self)() {
      title = String(cString: raw)
    }
    var level: Double = 0
    if let fn = symbol("uae4arm_host_music_level") {
      level = Double(unsafeBitCast(fn, to: FloatFn.self)())
    }
    return [
      "playing": flag("uae4arm_host_music_is_playing"),
      "paused": flag("uae4arm_host_music_is_paused"),
      "title": title,
      "level": level,
    ]
  }

  enum HostError: Error {
    case message(String)
  }
}
