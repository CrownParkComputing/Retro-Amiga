import Flutter
import UIKit

/// Application lifecycle host.
///
/// Deliberately thin: Info.plist declares a scene manifest, so the window and
/// its root FlutterViewController belong to SceneDelegate, and that is where
/// the emulator channel is registered.
@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
