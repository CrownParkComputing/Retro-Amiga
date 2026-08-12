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
}
