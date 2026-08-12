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
      self?.running = false
    }
  }

  enum HostError: Error {
    case message(String)
  }
}
