import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the core settings are pointed at the current container', () async {
    // What the iPad actually held: every path in the emulator's own settings
    // naming a container iOS had already deleted, which is why a WHDLoad game
    // mounted DH0 and DH3 from nowhere.
    final Directory dir = Directory.systemTemp.createTempSync('settings');
    final Directory documents = Directory('${dir.path}/Documents')
      ..createSync(recursive: true);
    final Directory settings = Directory('${documents.path}/Amiberry/Settings')
      ..createSync(recursive: true);
    final File conf = File('${settings.path}/amiberry.conf')
      ..writeAsStringSync('''
whdboot_path=/private/var/mobile/Containers/Data/Application/57C79B76-DAA1-46EB-9FC3-57CAF1925A7C/Documents/Amiberry/WHDBoot/
rom_path=/var/mobile/Containers/Data/Application/57C79B76-DAA1-46EB-9FC3-57CAF1925A7C/Documents/Amiberry/ROMs/
gui_theme=default
''');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('uae4arm2026/emulator'),
          (MethodCall call) async => documents.path,
        );

    await ConfigStore.repairEmulatorSettings();

    final String text = conf.readAsStringSync();
    expect(text, contains('${documents.path}/Amiberry/WHDBoot/'));
    expect(text, contains('${documents.path}/Amiberry/ROMs/'));
    expect(text, isNot(contains('57C79B76')));
    // Settings that are not paths are left alone.
    expect(text, contains('gui_theme=default'));

    dir.deleteSync(recursive: true);
  });
}
