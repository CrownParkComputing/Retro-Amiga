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

  private typealias RunFn = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
  private typealias SetMainReadyFn = @convention(c) () -> Void

  /// Whether the core loaded. Reported to Dart so the UI can say what is wrong
  /// rather than fail silently.
  func coreAvailable() -> Bool {
    return load() != nil
  }

  private func load() -> UnsafeMutableRawPointer? {
    if let handle = handle { return handle }
    let path = Bundle.main.bundlePath + "/Frameworks/libuae4arm.dylib"
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
    if running {
      throw HostError.message("Emulation is already running.")
    }
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

    // The controls go up before the core takes the main thread: once it has
    // it, nothing else on this thread runs until emulation ends, so there
    // would be no later moment to add them.
    controls.onQuit = { [weak self] in self?.quit() }
    controls.onPause = { [weak self] paused in self?.setPaused(paused) }
    controls.show()

    let run = unsafeBitCast(runSymbol, to: RunFn.self)
    // argv[0] is the program name, as the core's option parser expects.
    let argv: [String] = ["Amiga-Retro"] + args
    running = true

    DispatchQueue.main.async { [weak self] in
      // Copies that outlive this scope: the core keeps the pointers.
      var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
      cStrings.append(nil)

      NSLog("uae4arm: starting the core with %d arguments", argv.count)
      let status = cStrings.withUnsafeMutableBufferPointer { buffer -> Int32 in
        return run(Int32(argv.count), buffer.baseAddress)
      }
      NSLog("uae4arm: the core returned %d", status)

      for pointer in cStrings where pointer != nil {
        free(pointer)
      }
      self?.controls.hide()
      self?.running = false
    }
  }

  // MARK: - Music
  //
  // The launcher's ProTracker player lives in the same dylib but is
  // independent of emulation: it opens its own audio device and runs whether
  // or not a machine is running. So these load the core without starting it.

  private typealias PlayFn = @convention(c) (UnsafePointer<CChar>?) -> Bool
  private typealias VoidFn = @convention(c) () -> Void
  private typealias BoolFn = @convention(c) () -> Bool
  private typealias SetBoolFn = @convention(c) (Bool) -> Void
  private typealias FloatFn = @convention(c) () -> Float
  private typealias SetFloatFn = @convention(c) (Float) -> Void
  private typealias StringFn = @convention(c) () -> UnsafePointer<CChar>?

  /// The in-game controls, which iOS has to draw itself - see
  /// EmulatorControls for why Flutter cannot.
  private let controls = EmulatorControls()

  /// Ends emulation. The core unwinds on its next frame, uae4arm_host_run
  /// returns, and the launcher's own window is on top again.
  func quit() {
    guard let fn = symbol("uae4arm_host_quit") else { return }
    unsafeBitCast(fn, to: VoidFn.self)()
  }

  func setPaused(_ paused: Bool) {
    guard let fn = symbol("uae4arm_host_set_pause") else { return }
    unsafeBitCast(fn, to: SetBoolFn.self)(paused)
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
