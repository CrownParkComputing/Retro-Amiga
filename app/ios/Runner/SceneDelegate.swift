import Flutter
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

    let channel = FlutterMethodChannel(
      name: SceneDelegate.channelName,
      binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "platformName":
        result("ios")

      case "launch":
        guard let args = (call.arguments as? [String: Any])?["args"] as? [String] else {
          result(FlutterError(code: "no_args",
                              message: "launch requires an args list",
                              details: nil))
          return
        }
        // Not wired yet. The core dylib ships in the bundle with its host API
        // exported, but starting SDL inside a Flutter-owned UIApplication
        // still needs the run-loop work, so say so rather than fail silently.
        result(FlutterError(code: "unimplemented",
                            message: "The iOS emulator host is not wired up yet "
                                   + "(\(args.count) arguments were ready to pass).",
                            details: nil))

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
