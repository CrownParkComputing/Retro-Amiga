import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_collections.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';
import 'package:uae4arm2026/data/hard_drive_set.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_library.dart';

MediaFile file(String path, FileCategory category) =>
    MediaFile(path: path, category: category, size: 1);

HardDriveSet _set(String folder, {List<String> drives = const <String>[]}) =>
    HardDriveSet(
      folder: folder,
      bootDrive: drives.isEmpty ? folder : drives.first,
      drives: drives,
      directoryMount: drives.isEmpty,
    );

void main() {
  test('names the packs it recognises, and where', () {
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file('/sd/Amiga/HardDrives/AGS_UAE/System.hdf', FileCategory.hardDrives),
        file('/sd/Amiga/HardDrives/AmigaVision/AmigaVision.hdf',
            FileCategory.hardDrives),
        file('/sd/Amiga/lha/Zeb-WHDLoad-2024/boot.lha',
            FileCategory.whdloadGames),
      ],
    );

    final Map<AmigaCollection, String> found = AmigaCollection.findIn(index);

    expect(found[AmigaCollection.ags], '/sd/Amiga/HardDrives/AGS_UAE');
    expect(found[AmigaCollection.amigaVision],
        '/sd/Amiga/HardDrives/AmigaVision');
    expect(found[AmigaCollection.zebWhdload],
        '/sd/Amiga/lha/Zeb-WHDLoad-2024');
    // Reported as absent rather than omitted: "not found" is an answer.
    expect(found.containsKey(AmigaCollection.pimiga), isFalse);
  });

  test('a floppy named after a pack is not the pack', () {
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file('/sd/Amiga/Floppies/pimiga-intro.adf', FileCategory.floppies),
      ],
    );
    expect(AmigaCollection.findIn(index), isEmpty);
  });

  test('finds the dated WHDLoad pack, which never says "zeb"', () {
    // What is actually on the card: a folder and image named for the build
    // date. Matching on "zeb" missed a 25GB pack in plain sight.
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file(
          '/sd/Amiga/harddrives/WHDLoad (15-Feb-2026)/'
          'A1200 WHDLoad (15-Feb-2026).hdf',
          FileCategory.hardDrives,
        ),
      ],
    );
    expect(
      AmigaCollection.findIn(index)[AmigaCollection.zebWhdload],
      '/sd/Amiga/harddrives/WHDLoad (15-Feb-2026)',
    );
  });

  test('Zeb needs both halves of its name', () {
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file('/sd/Amiga/HardDrives/Zebra Games/games.hdf',
            FileCategory.hardDrives),
      ],
    );
    expect(AmigaCollection.findIn(index).containsKey(AmigaCollection.zebWhdload),
        isFalse);
  });

  group('detect', () {
    test('names PiMiga from the folder', () {
      expect(AmigaCollection.detect(_set('/media/HardDrives/Pimiga')),
          AmigaCollection.pimiga);
      expect(AmigaCollection.detect(_set('/media/HardDrives/PIMIGA5_INTEL')),
          AmigaCollection.pimiga);
    });

    test('names AmigaVision, spelled either way', () {
      expect(AmigaCollection.detect(_set('/media/HardDrives/AmigaVision')),
          AmigaCollection.amigaVision);
      expect(AmigaCollection.detect(_set('/media/HardDrives/Amiga Vision 2024')),
          AmigaCollection.amigaVision);
    });

    test('names a dated WHDLoad pack', () {
      expect(
        AmigaCollection.detect(_set('/media/HardDrives/A1200 WHDLoad (15-Feb-2026)')),
        AmigaCollection.zebWhdload,
      );
    });

    test('leaves an ordinary drive alone', () {
      expect(AmigaCollection.detect(_set('/media/HardDrives/MyWorkbench')), isNull);
    });

    test('PiMiga wins over the AGS-style menu it ships with', () {
      // A PiMiga install contains an AGS_UAE tree of its own. Matching AGS
      // first would configure it without the memory PiMiga needs.
      final HardDriveSet set = _set(
        '/media/HardDrives/Pimiga',
        drives: <String>['/media/HardDrives/Pimiga/AGS_UAE/ags.hdf'],
      );
      expect(AmigaCollection.detect(set), AmigaCollection.pimiga);
    });
  });

  group('apply', () {
    const EmulatorSettings base = EmulatorSettings(romFile: 'kick40068.rom');

    test('PiMiga gets the 040 RTG machine its own config asks for', () {
      final EmulatorSettings s =
          AmigaCollection.pimiga.machine(base, <String>['/hd/System', '/hd/Games']);
      expect(s.cpuModel, 68040);
      expect(s.fpuModel, 68040);
      expect(s.cpuSpeed, 'max');
      expect(s.chipset, 'aga');
      expect(s.chipRam, 16); // 8MB
      // Handheld-sized, not desktop-sized: 512MB of Zorro III beside a
      // 128MB graphics card was 640MB committed, and reallocating the RTG
      // buffers on a screen-mode change got the process killed outright.
      expect(s.z3Ram, 256);
      expect(s.rtgMemory, 32);
      expect(s.useRtg, isTrue);
      expect(s.jitCacheSize, 16384);
      expect(s.jitFpu, isTrue);
      // JIT on an 040 needs the compatible/24-bit pair off, or it silently
      // falls back to interpreting.
      expect(s.cpuCompatible, isFalse);
      expect(s.address24Bit, isFalse);
    });

    test('every profile keeps the ROM and takes the drives', () {
      for (final AmigaCollection profile in AmigaCollection.values) {
        final EmulatorSettings s =
            profile.machine(base, <String>['/hd/One', '/hd/Two']);
        expect(s.romFile, 'kick40068.rom', reason: profile.name);
        expect(s.hardDrives, <String>['/hd/One', '/hd/Two'],
            reason: profile.name);
      }
    });

    test('a WHDLoad pack stays on its native screen', () {
      // RTG is what stops the pack booting: it draws to an AGA screen mode.
      final EmulatorSettings s =
          AmigaCollection.zebWhdload.machine(base, <String>['/hd/WB']);
      expect(s.useRtg, isFalse);
    });

    test('a profile does not inherit the previous machine', () {
      // Built from defaults, so picking a distribution gives the same machine
      // whatever the user had chosen before.
      const EmulatorSettings odd = EmulatorSettings(
        romFile: 'kick40068.rom',
        chipRam: 1,
        ntsc: true,
        fastRam: 8,
      );
      final EmulatorSettings s = AmigaCollection.ags.machine(odd, <String>['/hd/AGS']);
      expect(s.chipRam, 4);
      expect(s.ntsc, isFalse);
      expect(s.fastRam, 0);
    });
  });
}
