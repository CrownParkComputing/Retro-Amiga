import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uae4arm2026/data/legacy_migration.dart';

void main() {
  late Directory temp;
  late Directory support;
  late Directory home;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temp = Directory.systemTemp.createTempSync('retro_amiga_migration_');
    support = Directory('${temp.path}/internal')..createSync();
    home = Directory('${temp.path}/external')..createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('restores old external configs and completes setup', () async {
    final Directory old = Directory('${home.path}/conf')..createSync();
    File(
      '${old.path}/Workbench 3.1.uae',
    ).writeAsStringSync('cpu_model=68020\n');

    final int copied = await LegacyMigration.run(
      appSupportDirectory: support.path,
      emulatorHomeDirectory: home.path,
    );

    expect(copied, 1);
    expect(
      File('${support.path}/conf/Workbench 3.1.uae').readAsStringSync(),
      'cpu_model=68020\n',
    );
    expect(
      (await SharedPreferences.getInstance()).getBool('setup_complete'),
      isTrue,
    );
  });

  test('keeps a different new config with the same name', () async {
    final Directory old = Directory('${home.path}/conf')..createSync();
    final Directory current = Directory('${support.path}/conf')..createSync();
    File('${old.path}/AGS.uae').writeAsStringSync('old');
    File('${current.path}/AGS.uae').writeAsStringSync('new');

    await LegacyMigration.run(
      appSupportDirectory: support.path,
      emulatorHomeDirectory: home.path,
    );

    expect(File('${current.path}/AGS.uae').readAsStringSync(), 'new');
    expect(
      File('${current.path}/AGS (restored).uae').readAsStringSync(),
      'old',
    );
  });

  test('runs only once', () async {
    final Directory old = Directory('${home.path}/conf')..createSync();
    File('${old.path}/First.uae').writeAsStringSync('first');
    await LegacyMigration.run(
      appSupportDirectory: support.path,
      emulatorHomeDirectory: home.path,
    );
    File('${old.path}/Later.uae').writeAsStringSync('later');

    final int copied = await LegacyMigration.run(
      appSupportDirectory: support.path,
      emulatorHomeDirectory: home.path,
    );

    expect(copied, 0);
    expect(File('${support.path}/conf/Later.uae').existsSync(), isFalse);
  });
}
