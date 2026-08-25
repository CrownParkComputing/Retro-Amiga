import Cocoa
import FlutterMacOS
import Darwin

private final class DesktopCore {
  static let shared = DesktopCore()
  private var handle: UnsafeMutableRawPointer?
  private var running = false

  private typealias RunFn = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
  private typealias PlayFn = @convention(c) (UnsafePointer<CChar>?) -> Bool
  private typealias VoidFn = @convention(c) () -> Void
  private typealias BoolFn = @convention(c) () -> Bool
  private typealias SetBoolFn = @convention(c) (Bool) -> Void
  private typealias FloatFn = @convention(c) () -> Float
  private typealias SetFloatFn = @convention(c) (Float) -> Void
  private typealias StringFn = @convention(c) () -> UnsafePointer<CChar>?

  private func load() -> UnsafeMutableRawPointer? {
    if let handle = handle { return handle }
    let paths = [
      Bundle.main.bundlePath + "/Contents/Frameworks/libuae4arm.framework/libuae4arm",
      Bundle.main.bundlePath + "/Contents/Frameworks/libuae4arm.dylib",
      Bundle.main.bundlePath + "/../lib/libuae4arm.dylib",
    ]
    for path in paths {
      if let opened = dlopen(path, RTLD_NOW | RTLD_GLOBAL) {
        handle = opened
        return opened
      }
    }
    NSLog("uae4arm: could not load the desktop core")
    return nil
  }

  func launch(args: [String]) -> Bool {
    guard !running, let handle = load(),
          let symbol = dlsym(handle, "uae4arm_host_run") else { return false }
    running = true
    let run = unsafeBitCast(symbol, to: RunFn.self)
    let argvValues = ["Retro-Amiga"] + args
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var cStrings = argvValues.map { strdup($0) }
      cStrings.append(nil)
      _ = cStrings.withUnsafeMutableBufferPointer { buffer in
        run(Int32(argvValues.count), buffer.baseAddress)
      }
      for pointer in cStrings where pointer != nil { free(pointer) }
      DispatchQueue.main.async { self?.running = false }
    }
    return true
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
    if let fn = symbol("uae4arm_host_music_stop") { unsafeBitCast(fn, to: VoidFn.self)() }
  }

  func musicReleaseAudio() {
    if let fn = symbol("uae4arm_host_music_release_audio") { unsafeBitCast(fn, to: VoidFn.self)() }
  }

  func musicSetPaused(_ paused: Bool) {
    if let fn = symbol("uae4arm_host_music_set_paused") { unsafeBitCast(fn, to: SetBoolFn.self)(paused) }
  }

  func musicSetVolume(_ volume: Double) {
    if let fn = symbol("uae4arm_host_music_set_volume") { unsafeBitCast(fn, to: SetFloatFn.self)(Float(volume)) }
  }

  func musicState() -> [String: Any] {
    func flag(_ name: String) -> Bool {
      guard let fn = symbol(name) else { return false }
      return unsafeBitCast(fn, to: BoolFn.self)()
    }
    var title = ""
    if let fn = symbol("uae4arm_host_music_title"),
       let raw = unsafeBitCast(fn, to: StringFn.self)() { title = String(cString: raw) }
    let level = symbol("uae4arm_host_music_level").map {
      Double(unsafeBitCast($0, to: FloatFn.self)())
    } ?? 0
    return ["playing": flag("uae4arm_host_music_is_playing"),
            "paused": flag("uae4arm_host_music_is_paused"),
            "title": title, "level": level]
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "uae4arm2026/emulator",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openControllerMapping":
        // macOS has no separate controller-mapping workflow in this build.
        result(nil)

      case "platformName":
        result("macos")

      case "appBuildStamp":
        let paths = [Bundle.main.executableURL?.path, Bundle.main.bundlePath]
          .compactMap { $0 }
        var stamp = 0
        for path in paths {
          if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
             let date = attributes[.modificationDate] as? Date {
            stamp = Int(date.timeIntervalSince1970)
            if stamp > 0 { break }
          }
        }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        result(stamp > 0 ? "\(version)-\(stamp)" : "")

      case "appSupportDirectory":
        result(
          NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true).first)

      case "documentsDirectory":
        result(
          NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true).first)

      case "emulatorHomeDirectory":
        let documents = NSSearchPathForDirectoriesInDomains(
          .documentDirectory, .userDomainMask, true).first
        result(documents.map { $0 + "/Amiberry" })

      case "hasAllFilesAccess":
        result(true)

      case "requestAllFilesAccess":
        result(true)

      case "musicPlay":
        let args = call.arguments as? [String: Any]
        if let path = args?["path"] as? String {
          result(DesktopCore.shared.musicPlay(path: path))
        } else {
          result(false)
        }

      case "musicStop":
        DesktopCore.shared.musicStop()
        result(nil)

      case "musicReleaseAudio":
        DesktopCore.shared.musicReleaseAudio()
        result(nil)

      case "musicSetPaused":
        if let args = call.arguments as? [String: Any], let paused = args["paused"] as? Bool {
          DesktopCore.shared.musicSetPaused(paused)
        }
        result(nil)

      case "musicSetVolume":
        if let args = call.arguments as? [String: Any], let volume = args["volume"] as? Double {
          DesktopCore.shared.musicSetVolume(volume)
        }
        result(nil)

      case "musicState":
        result(DesktopCore.shared.musicState())

      case "launch":
        guard let arguments = call.arguments as? [String: Any],
              let args = arguments["args"] as? [String] else {
          result(FlutterError(code: "no_args", message: "launch requires an args list", details: nil))
          return
        }
        result(DesktopCore.shared.launch(args: args))

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
