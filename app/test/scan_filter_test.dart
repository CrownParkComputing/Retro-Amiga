import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_library.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('scan'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test('the mod./med. prefix convention no longer counts as music', () {
    // Music is .mod files only: the AmigaDOS "mod.name" naming doubled a
    // Modland-style dump in the index, and the player is a ProTracker
    // replayer anyway.
    expect(FileCategory.fromPath('Music/mod.axel_f'), isNull);
    expect(FileCategory.fromPath('Music/med.tune'), isNull);
    expect(FileCategory.fromPath('Music/axel_f.mod'), FileCategory.music);
    expect(FileCategory.fromPath('Music/tune.med'), isNull);
    expect(FileCategory.fromPath('Music/tune.xm'), isNull);
  });

  test('a Kickstart is recognised and a stray .bin is not', () {
    expect(
      MediaLibrary.looksLikeKickstart(
        write('kick.rom', <int>[0x11, 0x14, 0x4E, 0xF9, 0, 0, 0, 0]),
      ),
      isTrue,
    );
    expect(
      MediaLibrary.looksLikeKickstart(write('vgabios.bin', <int>[0x55, 0xAA])),
      isFalse,
    );
  });

  test('legacy DMS and DSK images are not imported into the library', () {
    expect(FileCategory.fromPath('/drop/old.dms'), isNull);
    expect(FileCategory.fromPath('/drop/old.dsk'), isNull);
  });
}
