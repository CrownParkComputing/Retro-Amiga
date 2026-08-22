// The compliance demo has to be a real, bootable Amiga disk and a machine
// that boots a ROM nobody supplied. Both are easy to break silently.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/compliance_demo.dart';
import 'package:uae4arm2026/data/media_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the demo disk is a bootable ADF', () async {
    // Kickstart verifies the boot block before it will execute anything, and
    // a wrong checksum is not an error message: the disk simply is not
    // bootable and the machine sits on the insert-disk screen, which looks
    // exactly like a demo that does not work.
    final ByteData data =
        await rootBundle.load('assets/demo/demo.adf');
    final Uint8List bytes = data.buffer.asUint8List();

    expect(bytes.length, 901120, reason: 'a standard 880K disk');
    expect(String.fromCharCodes(bytes.sublist(0, 3)), 'DOS');

    var sum = 0;
    for (var i = 0; i < 1024; i += 4) {
      final int word = data.getUint32(i);
      sum += word;
      if (sum > 0xFFFFFFFF) sum = (sum & 0xFFFFFFFF) + 1;
    }
    expect(sum, 0xFFFFFFFF,
        reason: 'the boot checksum must fold to all ones, or it will not boot');
  });

  test('compliance mode takes the bundled ROM and nothing else', () {
    // The mode's whole claim is that the machine runs on a ROM nobody had to
    // supply. Quietly picking up a Kickstart the user happens to have would
    // defeat that, and invisibly, because both boot.
    final roms = <MediaFile>[
      const MediaFile(
          path: '/m/roms/kick31.rom', category: FileCategory.roms, size: 524288),
      const MediaFile(
          path: '/m/roms/aros-rom.bin',
          category: FileCategory.roms,
          size: 524288),
    ];

    final picked =
        RomPicker.kickstartFor(AmigaModel.a500, roms, preferAros: true);
    expect(picked?.name, 'aros-rom.bin');

    // And with no AROS present it must report nothing rather than fall back
    // to the user's ROM, which would hide the problem behind a machine that
    // boots.
    final onlyUser = <MediaFile>[roms.first];
    expect(RomPicker.kickstartFor(AmigaModel.a500, onlyUser, preferAros: true),
        isNull);

    // Ordinary mode is unchanged.
    expect(RomPicker.kickstartFor(AmigaModel.a500, roms)?.name, isNotNull);
  });

  test('preparing the demo leaves exactly one disk image', () async {
    final Directory dir = Directory.systemTemp.createTempSync('amigademo');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Old Demo.adf').writeAsBytesSync(<int>[1, 2, 3]);

    await ComplianceDemo.prepare(into: dir);

    final adfs = (await ComplianceDemo.files(from: dir))
        .where((String f) => f.toLowerCase().endsWith('.adf'))
        .toList();
    expect(adfs, <String>[ComplianceDemo.diskName]);
  });
}
