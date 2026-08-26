// What may be offered as a Kickstart.
//
// The ROM category matches on extension -- rom, kick, key, bin -- and two of
// those are far too broad to stand alone. A real PiMiga install carries
// HippoPlayer.key (64 bytes), cin.key (232 bytes) and RiftData.bin (26MB);
// all three were counted as Kickstarts and offered as machines to boot.
//
// Size settles it without opening anything.
import 'package:flutter_test/flutter_test.dart';

import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_library.dart';

MediaFile _rom(String name, int size) =>
    MediaFile(path: '/media/Kickstarts/$name', category: FileCategory.roms, size: size);

void main() {
  group('looksLikeRom', () {
    test('a real Kickstart passes', () {
      expect(
        RomPicker.looksLikeRom(
          _rom('Kickstart v3.1 r40.068 (A1200).rom', 524288),
        ),
        isTrue,
      );
      // The oldest ones are half that.
      expect(RomPicker.looksLikeRom(_rom('kick13.rom', 262144)), isTrue);
      expect(RomPicker.looksLikeRom(_rom('aros-rom.bin', 524288)), isTrue);
    });

    test('a registration keyfile does not', () {
      expect(RomPicker.looksLikeRom(_rom('HippoPlayer.key', 64)), isFalse);
      expect(RomPicker.looksLikeRom(_rom('cin.key', 232)), isFalse);
      expect(RomPicker.looksLikeRom(_rom('Executive.key', 1024)), isFalse);
    });

    test('a game data blob does not', () {
      expect(RomPicker.looksLikeRom(_rom('RiftData.bin', 27799541)), isFalse);
    });

    test("Cloanto's rom.key is named out, whatever its size", () {
      // It belongs beside an encrypted ROM and the core needs it -- but it is
      // not itself a machine, and offering it as one is a dead end.
      expect(RomPicker.looksLikeRom(_rom('rom.key', 524288)), isFalse);
      expect(RomPicker.looksLikeRom(_rom('ROM.KEY', 1024)), isFalse);
    });
  });

  test('the picker will not choose a keyfile even when it is all there is', () {
    // The failure this prevents is quiet: a config naming a 64-byte keyfile as
    // its Kickstart starts, maps no ROM and draws black.
    final List<MediaFile> roms = <MediaFile>[
      _rom('HippoPlayer.key', 64),
      _rom('RiftData.bin', 27799541),
    ];
    expect(RomPicker.kickstartFor(AmigaModel.a1200, roms), isNull);
  });

  test('the picker still finds the real ROM among the noise', () {
    final MediaFile real = _rom('Kickstart v3.1 r40.068 (A1200)[!].rom', 524288);
    final List<MediaFile> roms = <MediaFile>[
      _rom('cin.key', 232),
      real,
      _rom('RiftData.bin', 27799541),
    ];
    expect(RomPicker.kickstartFor(AmigaModel.a1200, roms), real);
  });
}
