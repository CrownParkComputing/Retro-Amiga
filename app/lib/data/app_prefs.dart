import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'host_paths.dart';

import 'amiga_model.dart';

/// The handful of things the app remembers between launches.
class AppPrefs {
  const AppPrefs._();

  static const String _setupComplete = 'setup_complete';
  static const String _defaultModel = 'default_model';
  static const String _buildStamp = 'build_stamp';
  static const String _confirmFileDelete = 'confirm_file_delete';
  static const String _screenFill = 'screen_fill';
  static const String _musicVolume = 'music_volume';

  /// Whether the machine boots the bundled AROS ROM instead of the user's
  /// Kickstart. Read at startup, because that is when the ROM is chosen.
  static const String _complianceMode = 'compliance_mode';

  /// Whether first-run setup has been through. Until it has, the app has no
  /// Kickstart and nothing can boot, so the shelf is not worth showing.
  static Future<bool> setupComplete() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupComplete) ?? false;
  }

  /// Whether to boot the bundled AROS ROM rather than a Kickstart of the
  /// user's.
  ///
  /// A mode rather than a setting: it decides which ROM the emulator is
  /// started with, so it takes effect when a machine is next launched, and
  /// while it is on the app deliberately keeps away from the user's own
  /// files. The point is that the app can be shown working with nothing
  /// supplied -- which is what a store review asks -- without borrowing
  /// anything of theirs to do it.
  static Future<bool> complianceMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_complianceMode) ?? false;
  }

  static Future<void> setComplianceMode({required bool value}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_complianceMode, value);
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

  /// Whether deleting a local media file asks for confirmation. Enabled by
  /// default because this action removes the user's file, not just an index
  /// entry.
  static Future<bool> confirmFileDelete() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_confirmFileDelete) ?? true;
  }

  static Future<void> setConfirmFileDelete({required bool value}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_confirmFileDelete, value);
  }

  /// Whether the in-process Amiga picture stretches to fill the whole panel
  /// (16:9 on a phone) rather than keeping its own shape with bars either
  /// side. Off by default: the Amiga's shape is the faithful one.
  ///
  /// Live, not just stored: the Video panel and the in-game button both flip
  /// it, and the picture has to follow whichever was touched.
  static final ValueNotifier<bool> screenFill = ValueNotifier<bool>(false);

  static Future<bool> loadScreenFill() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return screenFill.value = prefs.getBool(_screenFill) ?? false;
  }

  static Future<void> setScreenFill({required bool value}) async {
    screenFill.value = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenFill, value);
  }

  /// Workbench music volume, 0..1.
  static Future<double> musicVolume() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_musicVolume) ?? 1.0;
  }

  static Future<void> setMusicVolume(double value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicVolume, value);
  }
}

/// The one road back into the setup wizard from inside the app.
///
/// The root widget owns whether the wizard or the workbench is showing, and
/// Settings lives several widgets below it with no line of sight. A global
/// notifier is the honest shape of that relationship: Settings requests,
/// the root listens, and neither needs to know the other's tree.
class SetupFlow {
  const SetupFlow._();

  static final ValueNotifier<int> requests = ValueNotifier<int>(0);

  static void request() => requests.value++;
}
