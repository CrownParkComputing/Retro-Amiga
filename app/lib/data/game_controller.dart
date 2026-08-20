import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether a real controller is attached, and word when that changes.
///
/// The emulator activity has always asked this before drawing its overlay
/// pad. The in-process panel - which is where a game runs now on every
/// platform - never did, so it drew touch controls on top of a handheld's own
/// sticks and left the real hardware unused.
///
/// A one-off check at startup is not enough. A Bluetooth pad finishes pairing
/// a few seconds after the app opens, and a USB one gets unplugged mid-game;
/// the host pushes `gamepadChanged` for both, so the answer stays current
/// without anything polling for it.
class GameController {
  const GameController._();

  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// Listenable so a screen can rebuild on it directly.
  static final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  static bool _listening = false;

  /// Called with the pad state a physical controller is reporting.
  ///
  /// Set by whatever is running the core - the workbench panel - so the
  /// events reach the same pad the on-screen controls drive.
  static void Function(bool left, bool right, bool up, bool down)? onDirection;
  static void Function(int button, bool pressed)? onButton;

  /// Starts watching, and answers once with what is attached now.
  ///
  /// Safe to call more than once: the handler is installed only the first
  /// time, so a second screen asking does not displace the first.
  static Future<bool> start() async {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((MethodCall call) async {
        switch (call.method) {
          case 'gamepadChanged':
            connected.value = call.arguments as bool? ?? false;
          case 'physicalPadDirection':
            final Map<Object?, Object?> a =
                (call.arguments as Map<Object?, Object?>?) ?? const {};
            onDirection?.call(
              a['left'] as bool? ?? false,
              a['right'] as bool? ?? false,
              a['up'] as bool? ?? false,
              a['down'] as bool? ?? false,
            );
          case 'physicalPadButton':
            final Map<Object?, Object?> a =
                (call.arguments as Map<Object?, Object?>?) ?? const {};
            onButton?.call(
              (a['button'] as num?)?.toInt() ?? 0,
              a['pressed'] as bool? ?? false,
            );
        }
        return null;
      });
    }
    return refresh();
  }

  /// Tells the host whether a game is running.
  ///
  /// That decides whether controller events are swallowed and pushed into the
  /// core, or left alone. Outside a game the same buttons drive the launcher's
  /// own navigation, and eating them would leave a handheld unable to move
  /// around its own menus.
  static Future<void> setGameRunning(bool running) async {
    try {
      await _channel.invokeMethod<bool>('setGameRunning', <String, Object>{
        'running': running,
      });
    } on PlatformException {
      // A host without the forwarding path.
    } on MissingPluginException {
      // iOS and desktop: SDL sees their controllers directly.
    }
  }

  static Future<bool> refresh() async {
    try {
      final bool has =
          await _channel.invokeMethod<bool>('hasGamepad') ?? false;
      connected.value = has;
      return has;
    } on PlatformException {
      return connected.value;
    } on MissingPluginException {
      // Desktop and iOS have no handler. Answering "no controller" there
      // keeps the on-screen pad, which is the right default for a touch
      // device and harmless on a desktop that has a keyboard anyway.
      return false;
    }
  }
}
