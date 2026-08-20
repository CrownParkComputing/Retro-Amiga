import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/media_library.dart';

/// The ROM list is only useful if it holds Kickstarts and nothing else. On a
/// device shared with other emulators the `bin` extension matches almost
/// anything, so detection is by content: the header bytes here are the ones
/// real Kickstarts carry, taken from kick13.rom and kick40068.A1200.rom.
File write(Directory dir, String name, List<int> bytes) {
  final File file = File('${dir.path}/$name');
  file.writeAsBytesSync(Uint8List.fromList(bytes));
  return file;
}

List<int> padded(List<int> head, int length) => <int>[
  ...head,
  ...List<int>.filled(length - head.length, 0),
];

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('kickstart_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('accepts a 256K Kickstart', () {
    // 0x1111 identifier, then the 68k reset jump.
    final File rom = write(
      dir,
      'kick13.rom',
      padded(<int>[0x11, 0x11, 0x4E, 0xF9], 64),
    );
    expect(MediaLibrary.looksLikeKickstart(rom), isTrue);
  });

  test('accepts a 512K Kickstart', () {
    final File rom = write(
      dir,
      'kick40068.rom',
      padded(<int>[0x11, 0x14, 0x4E, 0xF9], 64),
    );
    expect(MediaLibrary.looksLikeKickstart(rom), isTrue);
  });

  test("accepts Cloanto's encrypted ROMs", () {
    // Those carry a text header and are decrypted by the core given a rom.key.
    final File rom = write(
      dir,
      'amiga-os-310.rom',
      padded('AMIROMTYPE1'.codeUnits, 64),
    );
    expect(MediaLibrary.looksLikeKickstart(rom), isTrue);
  });

  test('rejects another emulator\'s .bin ROM', () {
    // The case this exists for: bin is a Kickstart extension and also a
    // Mega Drive, PlayStation and BIOS extension.
    final File rom = write(
      dir,
      'scph1001.bin',
      padded(<int>[0x00, 0x00, 0x00, 0x00], 64),
    );
    expect(MediaLibrary.looksLikeKickstart(rom), isFalse);
  });

  test('rejects the right identifier with the wrong reset jump', () {
    final File rom = write(
      dir,
      'not-a-rom.bin',
      padded(<int>[0x11, 0x11, 0x00, 0x00], 64),
    );
    expect(MediaLibrary.looksLikeKickstart(rom), isFalse);
  });

  test('rejects a file too short to have a header', () {
    final File rom = write(dir, 'stub.rom', <int>[0x11, 0x11]);
    expect(MediaLibrary.looksLikeKickstart(rom), isFalse);
  });

  test('rejects a file that is not there', () {
    expect(
      MediaLibrary.looksLikeKickstart(File('${dir.path}/absent.rom')),
      isFalse,
    );
  });
}
