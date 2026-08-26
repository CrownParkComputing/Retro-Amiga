import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/config_generator.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';

/// Ported from the launcher's ConfigGeneratorTest.kt, with three expectations
/// corrected: seven of that suite's 103 tests fail against the code they test,
/// so it could not be carried over as-is. Each correction is noted where it
/// applies.
String gen(EmulatorSettings settings) => ConfigGenerator.generate(
  settings,
  // Nothing in these tests touches the filesystem: paths are fictional.
  isDirectoryPath: (String path) => false,
  hasRdb: (String path) => true,
);

void main() {
  _hardfileTests();
  _bigImageTests();
  group('header and always-present keys', () {
    test('starts with the header the core expects', () {
      expect(
        gen(const EmulatorSettings()),
        startsWith(ConfigGenerator.generatedByHeader),
      );
    });

    test('always writes use_gui=no', () {
      expect(gen(const EmulatorSettings()), contains('use_gui=no'));
    });

    test('always writes every floppy type, and a path only when set', () {
      // CORRECTED from the Kotlin test, which asserts "floppy0=" is always
      // present. The generator only emits a path when non-empty, so that
      // assertion fails; the types are what is unconditional.
      final String output = gen(const EmulatorSettings());
      for (int i = 0; i < 4; i++) {
        expect(output, contains('floppy${i}type='));
      }
      expect(output, isNot(contains('floppy0=')));
      expect(
        gen(const EmulatorSettings(floppy0: '/disks/game.adf')),
        contains('floppy0=/disks/game.adf'),
      );
    });

    test('always writes sound and display keys', () {
      final String output = gen(const EmulatorSettings());
      for (final String key in <String>[
        'sound_output=',
        'sound_frequency=',
        'sound_channels=',
        'gfx_width=',
        'gfx_height=',
        'amiberry.gfx_correct_aspect=',
        'amiberry.gfx_auto_crop=',
      ]) {
        expect(output, contains(key));
      }
    });
  });

  group('cpu', () {
    test('writes the cpu model', () {
      expect(
        gen(const EmulatorSettings(cpuModel: 68020)),
        contains('cpu_model=68020'),
      );
    });

    test('writes booleans as true/false', () {
      final String output = gen(const EmulatorSettings());
      expect(output, contains('cpu_compatible=true'));
      expect(output, contains('immediate_blits=false'));
    });

    test('omits the fpu when there is none, writes it when there is', () {
      expect(gen(const EmulatorSettings()), isNot(contains('fpu_model=')));
      expect(
        gen(const EmulatorSettings(fpuModel: 68882)),
        contains('fpu_model=68882'),
      );
    });

    test('omits jit keys when the cache is off, writes them when on', () {
      final String off = gen(const EmulatorSettings());
      expect(off, isNot(contains('cachesize=')));
      expect(off, isNot(contains('compfpu=')));

      final String on = gen(
        const EmulatorSettings(jitCacheSize: 8192, jitFpu: true),
      );
      expect(on, contains('cachesize=8192'));
      expect(on, contains('compfpu=true'));
    });

    test('forces cpu_compatible off when jit is on', () {
      // The pairing makes self-modifying code crawl. The core only
      // auto-disables it for 68040+, so the generator does it for all.
      final String output = gen(
        const EmulatorSettings(cpuCompatible: true, jitCacheSize: 8192),
      );
      expect(output, contains('cpu_compatible=false'));
    });
  });

  group('memory and rtg', () {
    test('omits z3mem when zero, writes it when set', () {
      expect(gen(const EmulatorSettings()), isNot(contains('z3mem_size=')));
      expect(gen(const EmulatorSettings(z3Ram: 64)), contains('z3mem_size=64'));
    });

    test('rtg on brings the Zorro III card, off zeroes the card', () {
      final String on = gen(const EmulatorSettings(useRtg: true));
      expect(on, contains('gfxcard_type=ZorroIII'));
      expect(on, contains('rtg_nocustom=true'));
      expect(gen(const EmulatorSettings()), contains('gfxcard_size=0'));
    });

    test('rtg swaps in the rtg resolution', () {
      expect(
        gen(
          const EmulatorSettings(useRtg: true, rtgWidth: 1920, rtgHeight: 1080),
        ),
        contains('gfx_width=1920'),
      );
      expect(
        gen(const EmulatorSettings(gfxWidth: 720)),
        contains('gfx_width=720'),
      );
    });
  });

  group('rom', () {
    test('omits both rom keys when empty', () {
      final String output = gen(const EmulatorSettings());
      expect(output, isNot(contains('kickstart_rom_file=')));
      expect(output, isNot(contains('kickstart_ext_rom_file=')));
    });

    test('writes the rom when set', () {
      expect(
        gen(const EmulatorSettings(romFile: '/path/kick.rom')),
        contains('kickstart_rom_file=/path/kick.rom'),
      );
    });
  });

  group('cd', () {
    test('omits cdimage when empty on a floppy machine', () {
      expect(gen(const EmulatorSettings()), isNot(contains('cdimage0=')));
    });

    test('writes cdimage with the ,image suffix the core needs', () {
      expect(
        gen(const EmulatorSettings(cdImage: '/path/game.iso')),
        contains('cdimage0=/path/game.iso,image'),
      );
    });

    test('does not double the ,image suffix', () {
      expect(
        gen(const EmulatorSettings(cdImage: '/path/game.iso,image')),
        contains('cdimage0=/path/game.iso,image'),
      );
    });

    test('accepts every cd format the core can actually mount', () {
      // The launcher this replaces allowed only iso and chd, so a .cue was
      // dropped despite blkdev_cdimage.cpp having a parser for it.
      for (final String ext in <String>[
        'cue',
        'ccd',
        'mds',
        'nrg',
        'chd',
        'iso',
      ]) {
        expect(
          gen(EmulatorSettings(cdImage: '/path/game.$ext')),
          contains('cdimage0=/path/game.$ext,image'),
          reason: '.$ext is mountable by the core and must survive',
        );
      }
    });

    test('still drops a path that is not a cd image at all', () {
      expect(
        gen(const EmulatorSettings(cdImage: '/path/notes.txt')),
        isNot(contains('cdimage0=')),
      );
    });

    test('the cd consoles declare an absent disc rather than none at all', () {
      // Without this the BIOS loops.
      expect(
        gen(EmulatorSettings.fromModel(AmigaModel.cd32)),
        contains('cdimage0_present=false'),
      );
      expect(
        gen(EmulatorSettings.fromModel(AmigaModel.cdtv)),
        contains('cdimage0_present=false'),
      );
    });
  });

  group('joystick ports', () {
    test('onscreen_joy maps to joy1 natively, keeping the host marker', () {
      // CORRECTED from the Kotlin test, which also expects
      // onscreen_joystick=true. The generator forces the core's own on-screen
      // controls off unconditionally, because the host draws them; that is
      // the shipping behaviour and the test contradicts it.
      final String output = gen(
        const EmulatorSettings(joyport1: 'onscreen_joy'),
      );
      expect(output, contains('joyport1=joy1'));
      expect(output, contains('amiberry.android_joyport1=onscreen_joy'));
      expect(output, contains('amiberry.touch_settings_version=1'));
      expect(output, contains('onscreen_joystick=false'));
      expect(output, contains('amiberry.onscreen_joystick=false'));
      expect(output, contains('vkbd_enabled=false'));
      expect(output, contains('input.default_osk=false'));
    });

    test('any other joyport1 passes through unchanged', () {
      final String output = gen(const EmulatorSettings(joyport1: 'joy0'));
      expect(output, contains('joyport1=joy0'));
      expect(output, contains('amiberry.android_joyport1=joy0'));
    });

    test('a cd32 puts port 1 in cd32 pad mode', () {
      // Without this, CD32 titles polling the pad's shift register see no
      // usable controller at all, not merely fewer buttons.
      expect(
        gen(EmulatorSettings.fromModel(AmigaModel.cd32)),
        contains('joyport1mode=cd32joy'),
      );
      expect(
        gen(EmulatorSettings.fromModel(AmigaModel.a1200)),
        isNot(contains('joyport1mode=')),
      );
    });
  });

  group('hard drives', () {
    test('a directory becomes filesystem2, bootable first', () {
      final String output = ConfigGenerator.generate(
        const EmulatorSettings(hardDrives: <String>['/games/WB']),
        isDirectoryPath: (String path) => true,
        hasRdb: (String path) => true,
      );
      expect(output, contains('filesystem2=rw,DH0:WB:"/games/WB",0'));
    });

    test('the Zeb bootstrap outranks the image RDB', () {
      final EmulatorSettings settings =
          EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
            hardDrives: <String>[
              '/Amiga/WHDBoot/zeb-bootstrap',
              '/Amiga/WHDBoot/save-data',
              '/Amiga/HardDrives/Zeb WHDLoad/Zeb.img',
            ],
          );

      final String output = ConfigGenerator.generate(
        settings,
        isDirectoryPath: (String path) => !path.endsWith('.img'),
        hasRdb: (String path) => path.endsWith('.img'),
      );

      expect(
        output,
        contains(
          'filesystem2=rw,DH0:zeb-bootstrap:'
          '"/Amiga/WHDBoot/zeb-bootstrap",10',
        ),
      );
    });

    test(
      'an rdb hardfile gets auto geometry, and real ide on ide machines',
      () {
        final String output = ConfigGenerator.generate(
          EmulatorSettings.fromModel(
            AmigaModel.a1200,
          ).copyWith(hardDrives: <String>['/games/wb.hdf']),
          isDirectoryPath: (String path) => false,
          hasRdb: (String path) => true,
        );
        expect(output, contains('0,0,0'));
        expect(output, contains('ide0'));
      },
    );

    test('an rdb-less hardfile falls back to uaehf with explicit geometry', () {
      // Real IDE cannot discover a drive with no partition table, and the
      // core needs a CHS to synthesise one.
      final String output = ConfigGenerator.generate(
        EmulatorSettings.fromModel(
          AmigaModel.a1200,
        ).copyWith(hardDrives: <String>['/games/raw.hdf']),
        isDirectoryPath: (String path) => false,
        hasRdb: (String path) => false,
      );
      expect(output, contains('32,1,2'));
      expect(output, contains('uae0'));
    });

    test('only the first drive is bootable', () {
      final String output = ConfigGenerator.generate(
        const EmulatorSettings(
          hardDrives: <String>['/games/one.hdf', '/games/two.hdf'],
        ),
        isDirectoryPath: (String path) => false,
        hasRdb: (String path) => true,
      );
      expect(output, contains(',512,0,'));
      expect(output, contains(',512,-128,'));
    });
  });

  group('per-machine defaults', () {
    test('a4000 brings 68040, aga, fpu and jit', () {
      final String output = gen(EmulatorSettings.fromModel(AmigaModel.a4000));
      expect(output, contains('cpu_model=68040'));
      expect(output, contains('chipset=aga'));
      expect(output, contains('fpu_model=68040'));
      expect(output, contains('cachesize=16384'));
      expect(output, contains('compfpu=true'));
      expect(output, contains('chipmem_size=4'));
      expect(output, contains('fastmem_size=8'));
      expect(output, contains('ide=a4000'));
    });

    test('a cd32 is a 24-bit 68020 with no jit and no floppy', () {
      final EmulatorSettings settings = EmulatorSettings.fromModel(
        AmigaModel.cd32,
      );
      expect(settings.jitCacheSize, 0);
      expect(settings.floppy0Type, -1);
      final String output = gen(settings);
      expect(output, contains('cpu_24bit_addressing=true'));
      expect(output, contains('chipset_compatible=CD32'));
      expect(output, contains('cd32cd=true'));
      expect(output, contains('nr_floppies=0'));
    });

    test('a500 is a cycle-exact 68000 with chip and slow ram', () {
      final String output = gen(EmulatorSettings.fromModel(AmigaModel.a500));
      expect(output, contains('cpu_model=68000'));
      expect(output, contains('chipset=ocs'));
      expect(output, contains('cycle_exact=true'));
      expect(output, contains('chipmem_size=1'));
      expect(output, contains('bogomem_size=2'));
    });

    test('every model maps to a cmdArg the core accepts', () {
      // The core's --model handler is the authority; a typo here boots the
      // wrong machine silently.
      const Set<String> known = <String>{
        'A500',
        'A500P',
        'A600',
        'A1000',
        'A2000',
        'A1200',
        'A3000',
        'A4000',
        'CD32',
        'CDTV',
      };
      for (final AmigaModel model in AmigaModel.values) {
        expect(known, contains(model.cmdArg));
      }
    });
  });

  group('floppy count', () {
    test('counts the highest enabled drive', () {
      expect(gen(const EmulatorSettings()), contains('nr_floppies=1'));
      expect(
        gen(const EmulatorSettings(floppy1Type: 0)),
        contains('nr_floppies=2'),
      );
      expect(
        gen(
          const EmulatorSettings(
            floppy1Type: 0,
            floppy2Type: 0,
            floppy3Type: 0,
          ),
        ),
        contains('nr_floppies=4'),
      );
      expect(
        gen(const EmulatorSettings(floppy0Type: -1)),
        contains('nr_floppies=0'),
      );
    });
  });
}

void _hardfileTests() {
  group('hard drives', () {
    test('the filesys slot is empty, not a device name', () {
      const EmulatorSettings settings = EmulatorSettings(
        hardDrives: <String>['/sdcard/UAE4Arm/harddrives/game.hdf'],
      );
      final String config = ConfigGenerator.generate(settings);
      final String line = config
          .split('\n')
          .firstWhere((String l) => l.startsWith('hardfile2='));

      // rw,DEV:path,sectors,surfaces,reserved,blocksize,bootpri,filesys,controller
      // The field after bootpri is a filesystem handler the core loads from
      // disk. Naming a device there sends it looking for a file that does not
      // exist, and the drive never mounts.
      expect(line, isNot(contains('uaehf.device')));
      expect(line, contains(',512,0,,uae0'));
    });

    test('a big set goes on the UAE controller, not IDE', () {
      // A real A600/A1200/A4000 IDE has two units and the core models that,
      // so an AGS set of ten drives on ide0..ide9 gives a machine that starts
      // and never boots.
      final EmulatorSettings settings =
          EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
            hardDrives: <String>[
              '/ags/Workbench.hdf',
              '/ags/Games.hdf',
              '/ags/Music.hdf',
              '/ags/Work.hdf',
            ],
          );
      final List<String> lines = ConfigGenerator.generate(
        settings,
      ).split('\n').where((String l) => l.startsWith('hardfile2=')).toList();

      expect(lines, hasLength(4));
      expect(
        lines.every((String l) => l.contains(',uae')),
        isTrue,
        reason: 'every drive should be on the UAE controller',
      );
      expect(lines.any((String l) => l.contains(',ide')), isFalse);
    });

    test('two drives still use IDE on a machine that has one', () {
      final EmulatorSettings settings = EmulatorSettings.fromModel(
        AmigaModel.a1200,
      ).copyWith(hardDrives: <String>['/hd/one.hdf', '/hd/two.hdf']);
      final List<String> lines = ConfigGenerator.generate(
        settings,
      ).split('\n').where((String l) => l.startsWith('hardfile2=')).toList();
      expect(lines, hasLength(2));
      expect(lines.every((String l) => l.contains(',ide')), isTrue);
    });
  });
}

void _bigImageTests() {
  group('images past the IDE limit', () {
    String genWith(EmulatorSettings s, Map<String, int> sizes) =>
        ConfigGenerator.generate(
          s,
          isDirectoryPath: (String p) => false,
          hasRdb: (String p) => true,
          sizeOf: (String p) => sizes[p] ?? 0,
        );

    test('a 10GB RDB image goes on uaehf, not the emulated IDE', () {
      // AmigaVision: one 10GB image plus a small saves drive. Two drives, so
      // the old rule chose IDE -- which addresses 32 bits of byte offset and
      // therefore cannot boot past 4GB. It mounted and booted nothing.
      const String big = '/hd/AmigaVision.hdf';
      const String saves = '/hd/AmigaVision-Saves.hdf';
      final String out = genWith(
        const EmulatorSettings(
          baseModel: AmigaModel.a1200,
          hardDrives: <String>[big, saves],
        ),
        <String, int>{big: 10 * 1024 * 1024 * 1024, saves: 84 * 1024 * 1024},
      );
      expect(out, contains('uae0'));
      expect(out, isNot(contains('ide0')));
    });

    test('small RDB images still use the IDE the machine really has', () {
      const String a = '/hd/Work.hdf';
      final String out = genWith(
        const EmulatorSettings(
          baseModel: AmigaModel.a1200,
          hardDrives: <String>[a],
        ),
        <String, int>{a: 512 * 1024 * 1024},
      );
      expect(out, contains('ide0'));
    });

    test('one oversized drive moves the whole set off the IDE', () {
      // The boot drive is what matters, and splitting a two-drive set across
      // two controllers buys nothing.
      const String big = '/hd/Huge.hdf';
      const String small = '/hd/Small.hdf';
      final String out = genWith(
        const EmulatorSettings(
          baseModel: AmigaModel.a1200,
          hardDrives: <String>[big, small],
        ),
        <String, int>{big: 25 * 1024 * 1024 * 1024, small: 100 * 1024 * 1024},
      );
      // The machine still HAS an IDE controller (ide=a600/a1200); what must
      // not happen is a drive being attached to it.
      expect(out, isNot(contains('ide0')));
      expect(out, isNot(contains('ide1')));
      expect(out, contains('uae0'));
    });
  });
}
