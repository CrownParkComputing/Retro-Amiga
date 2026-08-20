import Flutter
import GameController
import UIKit

/// Adopts the window the app delegate already built, and registers the
/// emulator channel.
///
/// None of the window handling here is guessable from this file. On the Linux
/// build path, iosbox does not compile the AppDelegate.swift next to this one:
/// it substitutes its own, which runs an explicit FlutterEngine and creates the
/// window itself, before any scene exists. That window therefore belongs to no
/// UIWindowScene.
///
/// FlutterSceneDelegate tries to rescue exactly that case by re-parenting the
/// FlutterViewController into a fresh scene window, but on iOS 18 the
/// migration fails: UIKit refuses the re-parent, the FlutterView ends up
/// attached to nothing, and the app runs with a black screen and no error
/// anywhere. An empty FlutterSceneDelegate subclass hits this, and so does
/// creating a second window here.
///
/// So the migration is done properly instead: give the existing window to this
/// scene, take ownership, and clear appDelegate.window so Flutter's legacy path
/// sees nothing to rescue.
///
/// Registering the channel here rather than in AppDelegate follows from the
/// same fact: our AppDelegate is not the one that runs.
class SceneDelegate: FlutterSceneDelegate {

  private static let channelName = "uae4arm2026/emulator"

  /// Held so controller arrivals can be pushed to Dart after registration.
  private var emulatorChannel: FlutterMethodChannel?

  private var controllerObservers: [NSObjectProtocol] = []

  /// Tells the launcher when a controller comes or goes.
  ///
  /// Asking once at startup is not enough on either platform: an MFi or
  /// Bluetooth pad finishes connecting seconds after the app opens, and gets
  /// switched off mid-game. Android pushes the same `gamepadChanged` call from
  /// an InputDeviceListener; this is the iOS half of it, so the Dart side does
  /// not need to know which platform it is talking to.
  private func observeControllers() {
    let notify: (Notification) -> Void = { [weak self] _ in
      self?.emulatorChannel?.invokeMethod(
        "gamepadChanged",
        arguments: !GCController.controllers().isEmpty)
    }
    let center = NotificationCenter.default
    controllerObservers = [
      center.addObserver(
        forName: .GCControllerDidConnect, object: nil, queue: .main, using: notify),
      center.addObserver(
        forName: .GCControllerDidDisconnect, object: nil, queue: .main, using: notify),
    ]
  }

  deinit {
    for observer in controllerObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Cast to the concrete class, not the UIApplicationDelegate protocol:
    // `window` on the protocol existential is immutable, and it has to be
    // cleared below.
    if let windowScene = scene as? UIWindowScene,
       let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
       let existingWindow = appDelegate.window,
       existingWindow.rootViewController != nil {
      // Attaching the scene is the part the app delegate could not do: it ran
      // before any scene existed, so this window had none.
      existingWindow.windowScene = windowScene
      self.window = existingWindow

      // Hides it from FlutterSceneDelegate's migration guard, which fires on
      // appDelegate.window.rootViewController being non-nil.
      appDelegate.window = nil

      existingWindow.makeKeyAndVisible()
      // The host keeps this, so that leaving a game can hand the screen back
      // to a window it KNOWS is the launcher's, rather than to whatever
      // happened to be key when the game started - which by then is SDL's.
      EmulatorHost.shared.launcherWindow = existingWindow
    } else if let windowScene = scene as? UIWindowScene {
      // Nothing built a window, so build one here.
      //
      // The branch above is the Linux path, where iosbox substitutes an
      // AppDelegate that creates the window itself. The AppDelegate committed
      // next to this file does not: it is thin on purpose, on the stated
      // assumption that the window "belongs to SceneDelegate" -- which was only
      // ever half true, because this class adopted a window and never created
      // one. A storyboard would normally instantiate the FlutterViewController,
      // but Main.storyboard is wired to nothing here (no UIMainStoryboardFile,
      // no UISceneStoryboardFile), so on an Xcode build nothing ever made one.
      //
      // No FlutterViewController means no engine, which means Dart never runs:
      // the app launches, the scene connects, and the screen stays black with
      // no crash and nothing in any log.
      //
      // Plugins are registered against this engine specifically. The
      // AppDelegate registers against itself, feeding the implicit engine --
      // a different registry, so this does not trip "Duplicate plugin key".
      let engine = FlutterEngine(name: "main")
      engine.run()
      GeneratedPluginRegistrant.register(with: engine)

      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = FlutterViewController(
        engine: engine, nibName: nil, bundle: nil)
      self.window = window
      window.makeKeyAndVisible()
      EmulatorHost.shared.launcherWindow = window
    }

    // Still call super: it registers the engine for scene life-cycle events,
    // which is how plugins receive them. It finds the FlutterViewController
    // through self.window.rootViewController, which is now correctly set.
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    registerEmulatorChannel()
  }

  private func registerEmulatorChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("uae4arm: no FlutterViewController on this scene; emulator channel not registered")
      return
    }

    // Deliberately NOT registering plugins here. iosbox's substituted
    // AppDelegate already does it, and a second pass aborts the app with
    // "Duplicate plugin key". On an Xcode build our own AppDelegate covers it,
    // so both paths are handled without this.

    let channel = FlutterMethodChannel(
      name: SceneDelegate.channelName,
      binaryMessenger: controller.binaryMessenger)
    emulatorChannel = channel
    observeControllers()

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openControllerMapping":
        // iOS runs the emulator with a native control strip in the same window
        // and does not expose a separate controller-mapping screen.
        result(nil)

      case "platformName":
        result("ios")

      // Whether a real controller is attached, so the launcher does not offer
      // touch controls over hardware that can already play the game. Android
      // answers this from InputDevice; here GCController already knows, and
      // EmulatorControls asks it for the two-player button.
      case "hasGamepad":
        result(!GCController.controllers().isEmpty)

      // Something that changes every time a build is installed, so the
      // launcher can tell a new deploy from an ordinary start and show the
      // setup walkthrough again. The bundle's modification date is that: it
      // is stamped when the app is written to the device, and needs no
      // version number anybody has to remember to bump.
      case "appBuildStamp":
        // The executable's date, read through FileManager. The bundle URL's
        // resourceValues came back empty here and the fallback was epoch zero
        // - a constant, which compares equal to itself for ever and quietly
        // meant the walkthrough never appeared again.
        let paths = [Bundle.main.executablePath, Bundle.main.bundlePath].compactMap { $0 }
        var stamp = 0
        for path in paths {
          if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
             let date = attributes[.modificationDate] as? Date {
            stamp = Int(date.timeIntervalSince1970)
            if stamp > 0 { break }
          }
        }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        // Empty rather than a placeholder when nothing could be read: the
        // launcher treats "cannot tell" as "not a new build", and a made-up
        // value would be indistinguishable from a real one.
        result(stamp > 0 ? "\(version)-\(stamp)" : "")

      // Asked of the host rather than path_provider. That package's iOS
      // implementation binds through package:objective_c FFI, whose native
      // symbols the iosbox build does not link, and the failure surfaces as
      // "Couldn't resolve native function 'DOBJC_initializeApi'" on the first
      // call. These two paths are all it was being used for.
      case "appSupportDirectory":
        result(
          NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true).first)

      case "documentsDirectory":
        result(
          NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true).first)

      case "launch":
        guard let args = (call.arguments as? [String: Any])?["args"] as? [String] else {
          result(FlutterError(code: "no_args",
                              message: "launch requires an args list",
                              details: nil))
          return
        }
        do {
          try EmulatorHost.shared.launch(args: args)
          result(nil)
        } catch EmulatorHost.HostError.message(let message) {
          result(FlutterError(code: "launch_failed", message: message, details: nil))
        } catch {
          result(FlutterError(code: "launch_failed",
                              message: error.localizedDescription,
                              details: nil))
        }

      // Must match what the core computes for itself: on iOS it uses
      // <home>/Documents/Amiberry, so the boot archive has to land there or
      // the WHDLoad booter will not find it.
      case "emulatorHomeDirectory":
        let documents = NSSearchPathForDirectoriesInDomains(
          .documentDirectory, .userDomainMask, true).first
        result(documents.map { $0 + "/Amiberry" })

      case "musicPlay":
        let path = (call.arguments as? [String: Any])?["path"] as? String ?? ""
        result(EmulatorHost.shared.musicPlay(path: path))

      case "musicStop":
        EmulatorHost.shared.musicStop()
        result(nil)

      case "musicSetPaused":
        let paused = (call.arguments as? [String: Any])?["paused"] as? Bool ?? false
        EmulatorHost.shared.musicSetPaused(paused)
        result(nil)

      case "musicSetVolume":
        let volume = (call.arguments as? [String: Any])?["volume"] as? Double ?? 1
        EmulatorHost.shared.musicSetVolume(volume)
        result(nil)

      case "musicState":
        result(EmulatorHost.shared.musicState())

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
