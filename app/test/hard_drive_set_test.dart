import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/hard_drive_set.dart';

void main() {
  late Directory temporary;

  setUp(() => temporary = Directory.systemTemp.createTempSync('hdf-set-'));
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'AGS_UAE is found through a dated wrapper and boots Workbench first',
    () {
      final Directory ags = Directory('${temporary.path}/15 Feb/AGS_UAE')
        ..createSync(recursive: true);
      for (final String name in <String>[
        'Games.hdf',
        'Workbench.hdf',
        'Music.hdz',
        'Work.vhd',
      ]) {
        File('${ags.path}/$name').writeAsBytesSync(<int>[0]);
      }
      final Directory shared = Directory('${ags.path}/Shared')..createSync();

      final HardDriveSet? set = HardDriveSet.inspect(temporary.path);

      expect(set, isNotNull);
      expect(set!.driveCount, 4);
      expect(set.bootDrive, endsWith('Workbench.hdf'));
      expect(set.sharedFolder, shared.path);
      expect(set.looksLikeAgs, isTrue);
      expect(set.allMounts.first, set.bootDrive);
      expect(set.allMounts.last, shared.path);
    },
  );

  test('a dated WHDLoad HDF folder is supported without forcing AGS RTG', () {
    final Directory pack = Directory('${temporary.path}/WHDLoad 15th Feb')
      ..createSync(recursive: true);
    File('${pack.path}/Game.hdf').writeAsBytesSync(<int>[0]);

    final HardDriveSet? set = HardDriveSet.inspect(pack.path);

    expect(set, isNotNull);
    expect(set!.allMounts, <String>['${pack.path}/Game.hdf']);
    expect(set.looksLikeAgs, isFalse);
  });

  test('a folder with ordinary Amiga files can itself be mounted', () {
    File('${temporary.path}/Startup-Sequence').writeAsStringSync('echo hello');

    final HardDriveSet? set = HardDriveSet.inspect(
      temporary.path,
      allowDirectoryMount: true,
    );

    expect(set, isNotNull);
    expect(set!.directoryMount, isTrue);
    expect(set.allMounts, <String>[temporary.path]);
  });
}
