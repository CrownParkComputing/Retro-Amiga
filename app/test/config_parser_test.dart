import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/config_generator.dart';
import 'package:uae4arm2026/data/config_parser.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';

/// The editor reads a config, changes one thing and writes the whole file
/// back, so anything the parser misses is deleted rather than left alone.
/// These tests are about that: what goes in comes out.
void main() {
  group('round trip', () {
    // Built from the machine, as the app builds it. Constructing one field by
    // field makes an impossible Amiga - an A1200 whose chipset says OCS - and
    // then the parser is blamed for reading what is written.
    final EmulatorSettings original =
        EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
          cpuSpeed: 'max',
          jitCacheSize: 16384,
          fpuModel: 68882,
          chipRam: 4,
          fastRam: 8,
          romFile: '/roms/kick31.rom',
          romExtFile: '/roms/cd32-ext.rom',
          floppy0: '/disks/game.adf',
          floppy1: '/disks/game2.adf',
          floppy1Type: 1,
          cdImage: '/cd/game.chd',
          whdloadFilename: '/lha/game.lha',
          hardDrives: <String>['/hd/game.hdf'],
          useRtg: true,
          rtgMemory: 32,
          rtgTrueColour: true,
          rtgWidth: 1280,
          rtgHeight: 720,
          soundOutput: 'normal',
          soundChannels: 'mono',
          soundStereoSeparation: 7,
          autoCrop: true,
          joyport0: 'joy0',
          joyport1: 'onscreen_joy',
          onScreenKeyboard: false,
        );

    late EmulatorSettings parsed;

    setUp(() {
      parsed = ConfigParser.parse(ConfigGenerator.generate(original));
    });

    test('keeps the processor', () {
      expect(parsed.cpuModel, 68020);
      expect(parsed.cpuSpeed, 'max');
      expect(parsed.jitCacheSize, 16384);
    });

    test('keeps the memory', () {
      expect(parsed.chipRam, 4);
      expect(parsed.fastRam, 8);
    });

    test('keeps the media', () {
      expect(parsed.romFile, '/roms/kick31.rom');
      expect(parsed.floppy0, '/disks/game.adf');
    });

    test('keeps hard drives, which an edit used to delete', () {
      expect(parsed.hardDrives, contains('/hd/game.hdf'));
    });

    test('keeps the graphics card', () {
      // An edit on an RTG config used to write gfxcard_size=0 and strip the
      // card the setup was built around.
      expect(parsed.useRtg, isTrue);
      expect(parsed.rtgMemory, 32);
      expect(parsed.rtgTrueColour, isTrue);
      expect(parsed.rtgWidth, 1280);
      expect(parsed.rtgHeight, 720);
    });

    test('keeps the ports and the remaining sound and display keys', () {
      expect(parsed.joyport0, 'joy0');
      // The android override key, not the native one, carries the choice.
      expect(parsed.joyport1, 'onscreen_joy');
      expect(parsed.soundOutput, 'normal');
      expect(parsed.soundChannels, 'mono');
      expect(parsed.autoCrop, isTrue);
      expect(parsed.onScreenKeyboard, isFalse);
      expect(parsed.cd32Fmv, isFalse);
      expect(parsed.whdloadFilename, '/lha/game.lha');
      expect(parsed.floppy1Type, 1);
    });

    test('a second generation is identical to the first', () {
      // What the editor actually does: parse, then write. If this drifts, an
      // edit changes settings the user did not touch.
      expect(
        ConfigGenerator.generate(parsed),
        ConfigGenerator.generate(original),
      );
    });
  });
}
