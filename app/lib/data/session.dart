import 'dart:io';

import 'host_paths.dart';

/// Whether there is a game to go back to.
///
/// The emulator writes a marker file when it starts and clears it when it
/// quits properly, so a marker still present means the session was left rather
/// than ended - backgrounded, or killed by the system. That is the only case
/// where offering "Resume" means anything, which is why the rail entry appears
/// only then.
///
/// It is a file rather than a flag in memory because the emulator runs in its
/// own process on Android: the launcher cannot see the emulator's variables,
/// but both can see the same directory.
class Session {
  const Session._();

  static const String _markerName = 'session_active';

  /// Set as soon as a launch is requested, so the launcher does not have to
  /// wait for the emulator process to start before it knows.
  static bool _startedThisRun = false;

  static void markStarted() => _startedThisRun = true;

  /// True if a game was started and has not quit.
  static Future<bool> exists() async {
    if (_startedThisRun) return true;
    try {
      return File('${await HostPaths.appSupport()}/$_markerName').existsSync();
    } on Object {
      return false;
    }
  }

  /// The config that session was running, if the marker names one.
  static Future<String> configPath() async {
    try {
      final File marker = File('${await HostPaths.appSupport()}/$_markerName');
      if (!marker.existsSync()) return '';
      return marker.readAsStringSync().trim();
    } on Object {
      return '';
    }
  }

  static Future<void> clear() async {
    _startedThisRun = false;
    try {
      final File marker = File('${await HostPaths.appSupport()}/$_markerName');
      if (marker.existsSync()) marker.deleteSync();
    } on Object {
      // Nothing to do: the worst case is an offer to resume something that is
      // no longer there, which the Resume panel handles.
    }
  }
}
