import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_library.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('scan'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test('a Rust module is not a ProTracker module', () {
    // What the desktop scan actually indexed: fifty mod.rs files as tunes.
    final File rust = write('mod.rs', 'pub mod foo;\n'.codeUnits);
    expect(MediaLibrary.looksLikeModule(rust), isFalse);

    // A real module says M.K. at offset 1080.
    final Uint8List module = Uint8List(2048);
    module.setRange(1080, 1084, 'M.K.'.codeUnits);
    expect(MediaLibrary.looksLikeModule(write('mod.axel_f', module)), isTrue);

    // Too short to hold the tag at all.
    expect(
      MediaLibrary.looksLikeModule(write('mod.tiny', <int>[1, 2, 3])),
      isFalse,
    );
  });

  test('mod.rs is code, mod.axel_f is a tune', () {
    // The Amiga names tunes the other way round, and so does Rust name its
    // modules: fifty mod.rs files were indexed as music.
    expect(MediaLibrary.isNamedModule('src/mod.rs', 40000), isFalse);
    expect(MediaLibrary.isNamedModule('web/mod.js', 40000), isFalse);
    expect(MediaLibrary.isNamedModule('lib/mod.ts', 40000), isFalse);
    expect(MediaLibrary.isNamedModule('Music/mod.axel_f', 40000), isTrue);
    // The fifteen-sample modules that came before M.K. carry no magic at all,
    // and Modland is full of them, so size and suffix decide rather than a
    // tag that may not be there.
    expect(MediaLibrary.isNamedModule('Music/mod.old_one', 20000), isTrue);
    expect(MediaLibrary.isNamedModule('Music/mod.stub', 200), isFalse);
  });

  test('a file named like a module but full of code is rejected', () {
    // 1084 bytes of JavaScript is long enough to be read at offset 1080, so
    // length alone would let it through; the tag is what settles it.
    final List<int> js = List<int>.filled(2000, 0x20);
    expect(MediaLibrary.looksLikeModule(write('mod.js', js)), isFalse);
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
