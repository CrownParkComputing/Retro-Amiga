import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/hard_drive_set.dart';
import 'package:uae4arm2026/data/amiga_collections.dart';
import 'package:uae4arm2026/data/media_library.dart';

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

  test('a Zeb raw image is recognised as a WHDLoad hard-drive setup', () {
    final Directory hardDrives = Directory('${temporary.path}/HardDrives')
      ..createSync();
    final Directory zeb = Directory('${hardDrives.path}/Zeb WHDLoad 15 Feb')
      ..createSync();
    final File image = File('${zeb.path}/Zebs-WHDLoad.img')
      ..writeAsBytesSync(<int>[0]);
    // A loose HDF must stay an individual choice, not be merged into Zeb's
    // complete setup merely because both live below HardDrives.
    File('${hardDrives.path}/Workbench31.hdf').writeAsBytesSync(<int>[0]);

    final MediaIndex index = MediaIndex(
      roots: <String>[temporary.path],
      files: <MediaFile>[
        MediaFile(path: image.path, category: FileCategory.hardDrives, size: 1),
        MediaFile(
          path: '${hardDrives.path}/Workbench31.hdf',
          category: FileCategory.hardDrives,
          size: 1,
        ),
      ],
    );

    final List<HardDriveSet> found = HardDriveSet.discoverIn(
      index,
      hardDrives.path,
    );

    expect(found, hasLength(1));
    expect(found.single.folder, zeb.path);
    expect(found.single.allMounts, <String>[image.path]);
    expect(found.single.looksLikeZebWhdload, isTrue);
    expect(found.single.looksLikeAgs, isFalse);
  });

  test('discoverIn offers an image-less folder as a directory mount', () {
    // The WinUAE "add a directory as a hard drive" case: an Amiga volume kept
    // as plain files, which contributes no hard-drive IMAGE to the index and
    // so used to be invisible here however carefully it was placed.
    final Directory hardDrives = Directory('${temporary.path}/HardDrives')
      ..createSync(recursive: true);
    final Directory workbench = Directory('${hardDrives.path}/Workbench31')
      ..createSync(recursive: true);
    File('${workbench.path}/Startup-Sequence').writeAsStringSync('echo hi');
    // An empty folder is not a drive: mounting it would give an empty DH0.
    Directory('${hardDrives.path}/Empty').createSync(recursive: true);

    final List<HardDriveSet> found = HardDriveSet.discoverIn(
      const MediaIndex(files: <MediaFile>[], roots: <String>[]),
      hardDrives.path,
    );

    expect(found, hasLength(1));
    expect(found.single.folder, workbench.path);
    expect(found.single.directoryMount, isTrue);
    expect(found.single.allMounts, <String>[workbench.path]);
  });

  test('a symlinked distribution folder is found', () {
    // How a 25GB PiMiga gets into the library without being stored twice.
    // listSync(followLinks: false) calls this a Link rather than a Directory,
    // which an `is Directory` test drops on the floor.
    final Directory hardDrives = Directory('${temporary.path}/HardDrives')
      ..createSync(recursive: true);
    final Directory elsewhere = Directory('${temporary.path}/elsewhere/Pimiga')
      ..createSync(recursive: true);
    File('${elsewhere.path}/Startup-Sequence').writeAsStringSync('echo hi');
    Link('${hardDrives.path}/Pimiga').createSync(elsewhere.path);

    final List<HardDriveSet> found = HardDriveSet.discoverIn(
      const MediaIndex(files: <MediaFile>[], roots: <String>[]),
      hardDrives.path,
    );

    expect(found, hasLength(1));
    expect(found.single.directoryMount, isTrue);
    expect(AmigaCollection.detect(found.single), AmigaCollection.pimiga);
  });

  test('the system drive is chosen, not whatever sorts first', () {
    // AmigaVision ships AmigaVision.hdf beside AmigaVision-Saves.hdf, and '-'
    // sorts before '.', so alphabetical order boots the 84MB saves drive.
    // It mounts perfectly and boots nothing, which on screen is the Kickstart
    // insert-disk prompt and no indication that the 10GB drive beside it was
    // the one wanted.
    const String big = '/hd/AmigaVision/AmigaVision.hdf';
    const String saves = '/hd/AmigaVision/AmigaVision-Saves.hdf';
    final HardDriveSet set = HardDriveSet.fromPaths(
      '/hd/AmigaVision',
      <String>[saves, big],
      sizes: <String, int>{big: 10 * 1024 * 1024 * 1024, saves: 84 * 1024 * 1024},
    );
    expect(set.bootDrive, big);
  });

  test('a named system drive still wins over the largest', () {
    // Size is the tie-breaker, not the rule: a games drive is often the
    // biggest thing in the folder.
    const String workbench = '/hd/Pack/Workbench.hdf';
    const String games = '/hd/Pack/Games.hdf';
    final HardDriveSet set = HardDriveSet.fromPaths(
      '/hd/Pack',
      <String>[games, workbench],
      sizes: <String, int>{games: 40 * 1024 * 1024 * 1024, workbench: 512 * 1024 * 1024},
    );
    expect(set.bootDrive, workbench);
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
