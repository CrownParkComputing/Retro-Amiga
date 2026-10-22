import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/media_folder.dart';
import 'package:uae4arm2026/data/media_layout.dart';

FolderEntry entry(String name, {String directory = '', int size = 1}) =>
    FolderEntry(documentId: 'id:$name', name: name, directory: directory, size: size);

void main() {
  group('MediaLayoutCheck.fromEntries', () {
    test('clean collection in standard subfolders produces no warnings', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[
          entry('kick13.rom', directory: 'Kickstarts'),
          entry('game.adf', directory: 'Floppies'),
          entry('game.lha', directory: 'LHA'),
          entry('photo.jpg', directory: 'Camera'),
        ],
        readableInPlace: true,
      );
      expect(report.recognizedMedia, 3);
      expect(report.presentSubfolders,
          containsAll(<String>['Kickstarts', 'Floppies', 'LHA']));
      expect(report.warnings, isEmpty);
    });

    test('loose media files mention the expected layout', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[
          entry('game.adf'),
          entry('other.adf'),
          entry('notes.txt'),
        ],
        readableInPlace: true,
      );
      expect(report.looseMediaFiles, 2);
      expect(report.warnings.join(' '), contains('Kickstarts'));
    });

    test('everything under one non-standard folder flags the parent pick', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[
          entry('game.adf', directory: 'Amiga/Floppies'),
          entry('kick13.rom', directory: 'Amiga/Kickstarts'),
        ],
        readableInPlace: true,
      );
      expect(report.umbrellaFolder, 'Amiga');
      expect(report.warnings.join(' '), contains('Re-pick "Amiga"'));
    });

    test('two distinct top folders is a layout, not a wrong level', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[
          entry('a.adf', directory: 'Old'),
          entry('b.adf', directory: 'New'),
        ],
        readableInPlace: true,
      );
      expect(report.umbrellaFolder, isNull);
    });

    test('an empty folder warns that nothing was recognised', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[entry('readme.pdf'), entry('photo.png')],
        readableInPlace: true,
      );
      expect(report.recognizedMedia, 0);
      expect(report.warnings.first, contains('Nothing in that folder'));
    });

    test('rom.key flags Cloanto even before a byte is read', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[
          entry('amiga-os-310.rom', directory: 'Kickstarts'),
          entry('rom.key', directory: 'Kickstarts'),
        ],
        readableInPlace: true,
      );
      expect(report.cloantoKeys, 1);
      expect(report.warnings.join(' '), contains('Cloanto'));
      expect(report.warnings.join(' '), contains('unencrypted Kickstart'));
    });

    test('resolver-only access explains the copy', () {
      final MediaLayoutReport report = MediaLayoutCheck.fromEntries(
        <FolderEntry>[entry('game.adf')],
        readableInPlace: false,
      );
      expect(report.warnings.join(' '), contains('copied'));
    });
  });

  group('encrypted ROM detection', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('roms'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('AMIROMTYPE1 magic marks a file encrypted', () async {
      final File rom = File('${tmp.path}/amiga-os-310.rom');
      rom.writeAsBytesSync(
        'AMIROMTYPE1'.codeUnits + List<int>.filled(100, 0),
      );
      expect(await MediaLayoutCheck.isEncryptedRom(rom), isTrue);
    });

    test('a plain Kickstart header is not encrypted', () async {
      final File rom = File('${tmp.path}/kick13.rom');
      rom.writeAsBytesSync(List<int>.filled(512 * 1024, 0xAB));
      expect(await MediaLayoutCheck.isEncryptedRom(rom), isFalse);
    });

    test('countEncryptedRoms only counts .rom files', () async {
      File('${tmp.path}/enc.rom').writeAsBytesSync('AMIROMTYPE1'.codeUnits);
      File('${tmp.path}/enc.bin').writeAsBytesSync('AMIROMTYPE1'.codeUnits);
      File('${tmp.path}/plain.rom').writeAsBytesSync(List<int>.filled(16, 7));
      expect(await MediaLayoutCheck.countEncryptedRoms(tmp), 1);
    });
  });
}
