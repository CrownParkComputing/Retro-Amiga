import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'host_paths.dart';

/// Records framework and unhandled async errors where a tester can find them.
///
/// A layout failure in a release build is invisible from outside the device.
/// There is no red error screen: the widget that threw simply does not paint,
/// so the report that comes back is "white screen" or "it shows nothing", and
/// the exception never leaves the phone. The sister C64 app lost most of a day
/// to one of those -- a sidebar whose clamp received a lower bound above its
/// upper one, which blanked every iPhone in portrait and looked in turn like a
/// signing fault, a core fault and a simulator fault. Once the app wrote its
/// own errors down it named the file and line on the first run.
///
/// The file lands in Documents, which is the one directory the Files app can
/// reach on iOS, so a tester can send it back without a cable or a console.
class ErrorLog {
  const ErrorLog._();

  static const String _fileName = 'amiga-retro-log.txt';
  static File? _file;
  static bool _installed = false;

  /// Hooks the error handlers. Safe to call more than once.
  ///
  /// Deliberately does not await anything: main() must not be held up by a
  /// channel round-trip, and an error thrown before the file is ready is still
  /// printed by the default handler. Lines logged in that window are lost
  /// rather than buffered, which is the right trade for a diagnostic.
  static void install() {
    if (_installed) return;
    _installed = true;
    unawaited(_open());

    final FlutterExceptionHandler? defaultHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // The library and the context are the useful part: they say which
      // subsystem failed and which widget was building, which is what turns
      // "white screen" into somewhere to look.
      _write('FLUTTER ERROR [${details.library}] ${details.exception}');
      final DiagnosticsNode? context = details.context;
      if (context != null) _write('  while ${context.toDescription()}');
      final StackTrace? stack = details.stack;
      if (stack != null) {
        // Trimmed: everything below the app's own frames is framework
        // internals, identical in every report.
        _write(stack.toString().split('\n').take(12).join('\n'));
      }
      defaultHandler?.call(details);
    };

    // Errors outside the widget tree -- a failed await in a timer, an isolate
    // callback -- never reach FlutterError.onError.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _write('UNCAUGHT $error');
      _write(stack.toString().split('\n').take(12).join('\n'));
      return false;
    };
  }

  static Future<void> _open() async {
    try {
      final File file = File('${await HostPaths.documents()}/$_fileName');
      // Truncated per launch. A log that grows for ever is one nobody sends,
      // and the interesting run is always the one that just happened.
      await file.writeAsString(
        '=== Amiga-Retro log -- ${DateTime.now().toIso8601String()} ===\n',
      );
      _file = file;
    } catch (_) {
      // No log file is survivable; refusing to start is not.
    }
  }

  static void _write(String message) {
    debugPrint(message);
    try {
      _file?.writeAsStringSync('$message\n', mode: FileMode.append);
    } catch (_) {}
  }
}
