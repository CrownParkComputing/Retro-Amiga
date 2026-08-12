import 'package:shared_preferences/shared_preferences.dart';

import 'amiga_model.dart';

/// The handful of things the app remembers between launches.
class AppPrefs {
  const AppPrefs._();

  static const String _setupComplete = 'setup_complete';
  static const String _defaultModel = 'default_model';

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
