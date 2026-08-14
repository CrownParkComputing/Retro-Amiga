import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uae4arm2026/data/app_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('uae4arm2026/emulator');
  String stamp = '111';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return call.method == 'appBuildStamp' ? stamp : null;
    });
  });

  test('a redeployed build shows the walkthrough again', () async {
    // Nothing remembered yet: this build is new.
    expect(await AppPrefs.isNewBuild(), isTrue);

    await AppPrefs.rememberBuild();
    expect(await AppPrefs.isNewBuild(), isFalse);

    // A new install stamps a different time, so the walkthrough returns.
    stamp = '222';
    expect(await AppPrefs.isNewBuild(), isTrue);
  });

  test('a placeholder stamp is treated as "cannot tell"', () async {
    // iOS answered "0" for a while - a constant that compares equal to itself
    // for ever, which turned the walkthrough off and said nothing about it.
    stamp = '0';
    expect(await AppPrefs.isNewBuild(), isFalse);
    await AppPrefs.rememberBuild();
    stamp = '1.0-1786620000';
    expect(await AppPrefs.isNewBuild(), isTrue);
  });

  test('a host that cannot say is not treated as new', () async {
    // Otherwise the walkthrough would come back on every single launch, which
    // is worse than never showing it.
    stamp = '';
    expect(await AppPrefs.isNewBuild(), isFalse);
  });
}
