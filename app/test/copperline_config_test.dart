import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/copperline_config.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One directory for the whole file: HostPaths.appSupport caches the first
  // answer it is given, so a per-test path would drift out from under the
  // keys the translator writes.
  late final Directory tmp =
      Directory.systemTemp.createTempSync('copperline');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('uae4arm2026/emulator'),
          (MethodCall call) async => switch (call.method) {
            'appSupportDirectory' => tmp.path,
            'emulatorHomeDirectory' => '${tmp.path}/home',
            _ => null,
          },
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('uae4arm2026/emulator'),
          null,
        );
    tmp.deleteSync(recursive: true);
  });

  test('a stock A500 setup translates', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a500,
      romFile: '/media/kick13.rom',
      floppy0: '/media/lemmings.adf',
      chipset: 'ocs',
    );
    final String toml = await CopperlineConfig.generate(settings);

    expect(toml, contains('rom = "/media/kick13.rom"'));
    expect(toml, contains('profile = "A500"'));
    expect(toml, contains('model = "68000"'));
    expect(toml, contains('chip = "512K"'));
    expect(toml, contains('revision = "OCS"'));
    expect(toml, contains('video = "PAL"'));
    expect(toml, contains('[floppy.df0]'));
    expect(toml, contains('path = "/media/lemmings.adf"'));
    // No marker, no Amiberry-isms leak into the TOML.
    expect(toml, isNot(contains('retro-amiga')));
    expect(toml, isNot(contains('uaehf')));
  });

  test('an A1200 with JIT and Z3 carries them over', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a1200,
      cpuModel: 68020,
      address24Bit: false,
      jitCacheSize: 8192,
      fastRam: 8,
      z3Ram: 32,
      chipset: 'aga',
      ntsc: true,
    );
    final String toml = await CopperlineConfig.generate(settings);

    expect(toml, contains('profile = "A1200"'));
    expect(toml, contains('model = "68020"'));
    // Copperline's jit is an interpreted batch path - measured ~10x slower
    // than the precise interpreter on this host - so the .uae jit flag is
    // deliberately not forwarded.
    expect(toml, isNot(contains('jit')));
    expect(toml, contains('z3 = "32M"'));
    expect(toml, contains('revision = "AGA"'));
    expect(toml, contains('video = "NTSC"'));
  });

  test('a 24-bit 68020 names the EC part', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a1200,
      cpuModel: 68020,
      address24Bit: true,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('model = "68EC020"'));
  });

  test('an empty Kickstart asks for the bundled AROS', () async {
    final String toml = await CopperlineConfig.generate(
      const EmulatorSettings(),
    );
    expect(toml, isNot(contains(RegExp('^rom =', multiLine: true))));
  });

  test('host directories mount as filesys volumes', () async {
    final Directory dh0 = Directory('${tmp.path}/WorkbenchHD')
      ..createSync();
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      hardDrives: <String>[dh0.path],
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('[[filesys]]'));
    expect(toml, contains('path = "${dh0.path}"'));
    expect(toml, contains('volume = "WorkbenchHD"'));
    expect(toml, isNot(contains('[copperhf]')));
  });

  test('hard drive images go to copperhf when IDE cannot take them', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a500,
      hardDrives: <String>['/media/system.hdf'],
    );
    // No RDB -> not IDE-worthy even on an IDE machine.
    final String toml = await CopperlineConfig.generate(
      settings,
      isDirectoryPath: (_) => false,
      hasRdb: (_) => false,
      sizeOf: (_) => 100 * 1024 * 1024,
    );
    expect(toml, contains('[copperhf]'));
    expect(toml, contains('unit0 = { path = "/media/system.hdf"'));
  });

  test('RDB images on an IDE machine use the IDE controller', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a1200,
      hardDrives: <String>['/media/system.hdf'],
    );
    final String toml = await CopperlineConfig.generate(
      settings,
      isDirectoryPath: (_) => false,
      hasRdb: (_) => true,
      sizeOf: (_) => 100 * 1024 * 1024,
    );
    expect(toml, contains('[ide]'));
    expect(toml, contains('master = { path = "/media/system.hdf"'));
    expect(toml, isNot(contains('[copperhf]')));
  });

  test('a CD32 disc lands on the console drive, others on SCSI', () async {
    final EmulatorSettings cd32 = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.cd32,
      cdImage: '/media/game.cue',
    );
    final String toml32 = await CopperlineConfig.generate(cd32);
    expect(toml32, contains('[cd]'));
    expect(toml32, contains('image = "/media/game.cue"'));
    expect(toml32, isNot(contains('[scsi]')));

    final EmulatorSettings a1200 = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a1200,
      cdImage: '/media/game.cue',
    );
    final String toml1200 = await CopperlineConfig.generate(
      a1200,
      isDirectoryPath: (_) => false,
    );
    expect(toml1200, contains('[scsi]'));
    expect(toml1200, contains('"/media/game.cue"'));
  });

  test('CD32 asks for a cd32 pad in the joystick port', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.cd32,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('port2 = "cd32"'));
  });

  test('whdload points at the staged kickstarts and archives', () async {
    final String home = '${tmp.path}/home';
    Directory('$home/WHDBoot/save-data/Kickstarts')
        .createSync(recursive: true);

    final String toml = await CopperlineConfig.generate(
      const EmulatorSettings(),
    );
    expect(toml, contains('[whdload]'));
    expect(
      toml,
      contains('kickstarts = "$home/WHDBoot/save-data/Kickstarts"'),
    );
    expect(toml, contains('library = "${tmp.path}/copperline/whdload"'));
    expect(
      toml,
      contains(
        'whd_package = "${tmp.path}/copperline/whdboot/WHDLoad_usr.lha"',
      ),
    );
    expect(
      toml,
      contains(
        'skick_package = "${tmp.path}/copperline/whdboot/skick346.lha"',
      ),
    );
  });

  test('an FPU on a 68000 is dropped, not carried', () async {
    // [cpu] fpu needs the 020+ coprocessor interface; forwarding an
    // A500+68881 .uae would fail the whole machine build.
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a500,
      cpuModel: 68000,
      fpuModel: 68881,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('model = "68000"'));
    expect(toml, isNot(contains('fpu')));
  });

  test('z3 and z3660 stay off a 24-bit machine', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a1200,
      cpuModel: 68020,
      address24Bit: true,
      z3Ram: 32,
      useRtg: true,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('model = "68EC020"'));
    expect(toml, isNot(contains('z3 = ')));
    expect(toml, contains('card = "picasso2plus"'));
  });

  test('z3 RAM carries on a 32-bit machine', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a4000,
      cpuModel: 68040,
      z3Ram: 32,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('z3 = "32M"'));
  });

  test('memory clamps to the ceilings the core enforces', () async {
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a1200,
      chipset: 'aga',
      chipRam: 8, // 4M: AGA caps at 2M
      slowRam: 6, // 1.5M: trapdoor caps at 512K
      fastRam: 16, // Zorro II space is 8M
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('chip = "2048K"'));
    expect(toml, contains('slow = "512K"'));
    expect(toml, contains('fast = "8M"'));
  });

  test('sparse floppy bays keep every configured drive connected', () async {
    // df3 populated while df0/df1 are disabled: drives must count bays,
    // not populated slots, or the core refuses the machine.
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      floppy0Type: -1,
      floppy1Type: -1,
      floppy3: '/media/lemmings.adf',
      floppy3Type: 0,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('drives = 4'));
    expect(toml, contains('[floppy.df3]'));
    expect(toml, contains('path = "/media/lemmings.adf"'));
  });

  test('mixed chipsets map to the per-chip keys', () async {
    final EmulatorSettings ecsAgnus = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a500,
      chipset: 'ecs_agnus',
      chipRam: 2,
    );
    final String toml = await CopperlineConfig.generate(ecsAgnus);
    expect(toml, contains('revision = "ECS"'));
    expect(toml, contains('denise = "8362"'));

    final EmulatorSettings ecsDenise = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a500,
      chipset: 'ecs_denise',
      chipRam: 1,
    );
    final String toml2 = await CopperlineConfig.generate(ecsDenise);
    expect(toml2, contains('revision = "OCS"'));
    expect(toml2, contains('denise = "8373"'));
  });

  test('a 1M-chip OCS setup rides ECS Agnus', () async {
    // OCS proper tops out at 512K chip; the real 1M-chip machines kept the
    // OCS Denise and swapped in an ECS Agnus.
    final EmulatorSettings settings = const EmulatorSettings().copyWith(
      baseModel: AmigaModel.a500,
      chipset: 'ocs',
      chipRam: 2,
    );
    final String toml = await CopperlineConfig.generate(settings);
    expect(toml, contains('revision = "ECS"'));
    expect(toml, contains('denise = "8362"'));
    expect(toml, contains('chip = "1024K"'));
  });

  test('scratch file lands beside the .uae, hidden', () {
    expect(
      CopperlineConfig.scratchPathFor('/data/conf/Lemmings.uae'),
      '/data/conf/.Lemmings.copperline.toml',
    );
  });

  test('writeScratchSettings writes beside the .uae, hidden', () async {
    final File uae = File('${tmp.path}/Game.uae')
      ..writeAsStringSync('chipset=ecs\n');
    // The scratch path is derived from the .uae path, whatever its content.
    final File toml = await CopperlineConfig.writeScratchSettings(
      const EmulatorSettings(),
      uae.path,
    );
    expect(toml.path, '${tmp.path}/.Game.copperline.toml');
    expect(toml.existsSync(), isTrue);
  });
}
