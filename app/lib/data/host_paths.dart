import 'dart:io';

import 'package:flutter/services.dart';

/// Where the app may write, asked of the host.
///
/// This exists instead of path_provider. That package's iOS implementation
/// binds through package:objective_c FFI, and the iosbox build does not link
/// its native symbols: the first call fails with "Couldn't resolve native
/// function 'DOBJC_initializeApi'", which surfaced as a scan that could not
/// start. Both hosts already answer a channel, and this is two paths.
class HostPaths {
  const HostPaths._();

  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  static String? _appSupport;
  static String? _documents;

  /// Private storage for configs and the media index.
  static Future<String> appSupport() async {
    final String? cached = _appSupport;
    if (cached != null) return cached;
    final String? path =
        await _channel.invokeMethod<String>('appSupportDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('the host returned no application support directory');
    }
    _appSupport = path;
    return path;
  }

  /// Where imported files land, and on iOS what the Files app can reach.
  static Future<String> documents() async {
    final String? cached = _documents;
    if (cached != null) return cached;
    final String? path =
        await _channel.invokeMethod<String>('documentsDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('the host returned no documents directory');
    }
    _documents = path;
    return path;
  }

  /// Rewrites a path saved by an earlier install so it points at this one.
  ///
  /// iOS hands the app a fresh data container UUID on every install, so an
  /// absolute path stored during setup - /var/mobile/Containers/Data/
  /// Application/`<UUID>`/Documents/kick13.rom - is dead the next time the app
  /// is installed. The file is still there; only the UUID moved. Nothing
  /// reports this: the config loads, the core cannot open the Kickstart, and
  /// the Amiga sits on a black screen.
  ///
  /// A path that still resolves is returned untouched, so this is a no-op on
  /// Android and for anything outside the container.
  static Future<String> repair(String stored) async {
    if (stored.isEmpty) return stored;
    if (FileSystemEntity.typeSync(stored) != FileSystemEntityType.notFound) {
      return stored;
    }

    final Match? match = _containerPath.firstMatch(stored);
    if (match == null) return stored;

    // documents() is <container>/Documents, so its parent is the container we
    // are running in now.
    final String container =
        File(await documents()).parent.path; // trims /Documents
    final String repaired = '$container/${match.group(1)}';
    if (FileSystemEntity.typeSync(repaired) == FileSystemEntityType.notFound) {
      // Nothing recovered; leave the original so the failure names the path
      // the user actually chose.
      return stored;
    }
    return repaired;
  }

  /// Captures whatever follows the container UUID, e.g. "Documents/kick13.rom".
  static final RegExp _containerPath = RegExp(
    r'/Containers/Data/Application/[0-9A-Fa-f-]{36}/(.+)$',
  );
}
