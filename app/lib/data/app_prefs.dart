import 'package:shared_preferences/shared_preferences.dart';

import 'host_paths.dart';

import 'amiga_model.dart';

/// The handful of things the app remembers between launches.
class AppPrefs {
  const AppPrefs._();

  static const String _setupComplete = 'setup_complete';
  static const String _defaultModel = 'default_model';
  static const String _buildStamp = 'build_stamp';

  /// Whether first-run setup has been through. Until it has, the app has no
  /// Kickstart and nothing can boot, so the shelf is not worth showing.
  static Future<bool> setupComplete() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupComplete) ?? false;
  }

  static Future<void> setSetupComplete({required bool value}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupComplete, value);
  }

  /// Whether this is the first run of a newly installed build.
  ///
  /// A new build is a new set of paths, a new scan and often new settings, and
  /// the walkthrough is where all of that is visible: what was found, where it
  /// lives, whether WHDLoad is ready. So a deploy shows it again rather than
  /// dropping straight onto the shelf with no sign of what changed.
  ///
  /// The stamp comes from the host - the install time on Android, the bundle's
  /// date on iOS, the executable's on the desktop - because no version number
  /// gets bumped reliably between test builds.
  static Future<bool> isNewBuild() async {
    final String stamp = await HostPaths.buildStamp();
    if (stamp.isEmpty) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_buildStamp) != stamp;
  }

  static Future<void> rememberBuild() async {
    final String stamp = await HostPaths.buildStamp();
    if (stamp.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_buildStamp, stamp);
  }

  /// The machine new setups start from.
  static Future<AmigaModel> defaultModel() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? arg = prefs.getString(_defaultModel);
    if (arg == null) return AmigaModel.a500;
    return AmigaModel.fromCmdArg(arg) ?? AmigaModel.a500;
  }

  static Future<void> setDefaultModel(AmigaModel model) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultModel, model.cmdArg);
  }
}
