import 'dart:io';

import 'amiga_model.dart';
import 'app_log.dart';
import 'aros_rom.dart';
import 'config_generator.dart';
import 'config_parser.dart';
import 'copperline_assets.dart';
import 'emulator_settings.dart';
import 'file_category.dart';
import 'media_root.dart';
import 'host_paths.dart';
import 'whdload_support.dart';

/// Turns [EmulatorSettings] into the TOML the Copperline core reads.
///
/// The .uae stays the setup's source of truth: it is what the shelf lists,
/// what the editor edits, and what survives an app reinstall's path repair.
/// This file is generated fresh at every launch into conf/ as a scratch
/// file, the way `--config` hands Amiberry its .uae.
///
/// What cannot carry over is named in a comment rather than silently
/// dropped, so the gap is visible to anyone reading the generated file:
/// collision level, immediate blits, interpolation -- Copperline has no
/// setting for them because its timing model has no knobs to turn.
class CopperlineConfig {
  const CopperlineConfig._();

  static String _esc(String path) =>
      '"${path.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  /// Machine profile names as Copperline spells them. There is no A2000
  /// profile; an A2000 setup rides the A500 profile and lets the explicit
  /// [memory]/[chipset] sections carry the difference.
  static String _profile(AmigaModel model) => switch (model) {
    AmigaModel.a1000 => 'A1000',
    AmigaModel.a500 => 'A500',
    AmigaModel.a2000 => 'A500',
    AmigaModel.a500Plus => 'A500Plus',
    AmigaModel.a600 => 'A600',
    AmigaModel.a1200 => 'A1200',
    AmigaModel.a3000 => 'A3000',
    AmigaModel.a4000 => 'A4000',
    AmigaModel.cdtv => 'CDTV',
    AmigaModel.cd32 => 'CD32',
  };

  /// 24-bit addressing on a 68020 is the EC part, which is how Copperline
  /// spells it; CD32 is always the EC part regardless.
  static String _cpu(EmulatorSettings s) {
    if (s.baseModel == AmigaModel.cd32) return '68EC020';
    if (s.cpuModel == 68020 && s.address24Bit) return '68EC020';
    return '${s.cpuModel}';
  }

  /// Whether the emitted CPU has a 32-bit address bus. Copperline gates
  /// Zorro III RAM, accelerator RAM and the Z3660/Graffity Z3 cards on it,
  /// and refuses the whole machine when one is asked of a 24-bit part.
  static bool _cpu32Bit(EmulatorSettings s) =>
      s.baseModel != AmigaModel.cd32 &&
      s.cpuModel != 68000 &&
      s.cpuModel != 68010 &&
      !(s.cpuModel == 68020 && s.address24Bit);

  /// The chipset section: the broad revision plus, where the .uae names a
  /// mixed chipset (ECS Agnus alone, or ECS Denise alone), the per-chip
  /// keys Copperline carries for exactly that combination.
  ///
  /// OCS is only expressible while chip RAM fits the OCS ceiling (512K) --
  /// a 1M-chip "OCS" setup rides ECS Agnus, which is how real 1M-chip
  /// A500s are built anyway.
  static void _writeChipset(StringBuffer out, EmulatorSettings s) {
    final int chipBytes = s.chipRam * 512 * 1024;
    switch (s.chipset) {
      case 'aga':
        out.writeln('revision = "AGA"');
      case 'ecs_agnus':
        out.writeln('revision = "ECS"');
        out.writeln('denise = "8362"');
      case 'ecs_denise':
        if (chipBytes <= 512 * 1024) {
          out.writeln('revision = "OCS"');
        } else {
          out.writeln('revision = "ECS"');
        }
        out.writeln('denise = "8373"');
      case 'ocs' when chipBytes <= 512 * 1024:
        out.writeln('revision = "OCS"');
      case 'ocs':
        out.writeln('revision = "ECS"');
        out.writeln('denise = "8362"');
      default:
        out.writeln('revision = "ECS"');
    }
    out.writeln('video = "${s.ntsc ? 'NTSC' : 'PAL'}"');
  }

  /// A host directory mounts as [[filesys]]; an image goes to a controller.
  /// Same rules as ConfigGenerator: IDE only for <=2 RDB images on an
  /// IDE-equipped machine and only while none exceeds the 4GB IDE limit.
  static bool _usesIde(
    EmulatorSettings s,
    List<String> images,
    bool Function(String) rdb,
    int Function(String) sizeOf,
  ) {
    final bool ideCapable =
        s.baseModel == AmigaModel.a600 ||
        s.baseModel == AmigaModel.a1200 ||
        s.baseModel == AmigaModel.a4000;
    if (!ideCapable || images.isEmpty || images.length > 2) return false;
    if (images.any((String p) => sizeOf(p) >= ConfigGenerator.ideMaxImageBytes)) {
      return false;
    }
    return images.every(rdb);
  }

  /// Generates the TOML for [settings].
  ///
  /// [isDirectoryPath], [hasRdb] and [sizeOf] are injectable for tests, as
  /// in ConfigGenerator.
  static Future<String> generate(
    EmulatorSettings settings, {
    bool Function(String path)? isDirectoryPath,
    bool Function(String path)? hasRdb,
    int Function(String path)? sizeOf,
  }) async {
    final bool Function(String) isDir =
        isDirectoryPath ??
        (String path) =>
            !path.startsWith('content://') && Directory(path).existsSync();
    final bool Function(String) rdb = hasRdb ?? ConfigGenerator.hasRdbSignature;
    final int Function(String) sizeOfImage = sizeOf ?? _imageSize;

    final String support = await HostPaths.appSupport();
    // The staged files the keys below name. Everything Copperline looks for
    // "next to the binary" has to live inside the app's own directories on
    // the phone hosts, so it ships as assets and is copied out on demand;
    // the TOML points at the copies.
    await CopperlineAssets.ensureInstalled();
    final String fmvRom = await CopperlineAssets.pathFor(
      'assets/copperline/fmv/copperline-fmv.rom',
    );
    final String a2091Rom = await CopperlineAssets.pathFor(
      'assets/copperline/a2091/copperline-a2091.rom',
    );
    final String whdPackage = await CopperlineAssets.pathFor(
      'assets/whdboot/WHDLoad_usr.lha',
    );
    final String skickPackage = await CopperlineAssets.pathFor(
      'assets/whdboot/skick346.lha',
    );
    final StringBuffer out = StringBuffer();
    out.writeln('# Generated by Retro-Amiga for the Copperline core.');
    out.writeln('# The .uae beside it is the setup\'s source of truth; this');
    out.writeln('# file is rewritten at every launch.');
    out.writeln();

    // ROM. A named Kickstart wins; with none, point at the AROS pair the app
    // already stages for Amiberry -- Copperline's own bundled-AROS search
    // only looks next to the binary, which is not a place files can live on
    // the phone hosts.
    if (settings.romFile.isNotEmpty) {
      out.writeln('rom = ${_esc(settings.romFile)}');
      if (settings.romExtFile.isNotEmpty) {
        out.writeln('extended_rom = ${_esc(settings.romExtFile)}');
      }
    } else {
      try {
        await ArosRom.installIfMissing();
        final Directory roms =
            await MediaRoot.folderFor(FileCategory.roms);
        final File main = File('${roms.path}/aros-rom.bin');
        final File ext = File('${roms.path}/aros-ext.bin');
        if (main.existsSync() && ext.existsSync()) {
          out.writeln('rom = ${_esc(main.path)}');
          out.writeln('extended_rom = ${_esc(ext.path)}');
        }
      } on Object {
        // No media root to look in: leave rom unset and let the core's own
        // bundled-AROS search run -- it at least exists on desktop builds.
      }
    }
    if (settings.baseModel == AmigaModel.cd32 && settings.cd32Fmv) {
      out.writeln('fmv = true');
      out.writeln('fmv_rom = ${_esc(fmvRom)}');
    }
    out.writeln();

    out.writeln('[paths]');
    // Everything Copperline writes - nvram, staged WHDLoad games, traces -
    // stays inside the app's own directory so an iOS container move is
    // repaired the same way every other stored path is.
    out.writeln('base = ${_esc('$support/copperline')}');
    out.writeln('nvram = "nvram"');
    out.writeln();

    out.writeln('[machine]');
    out.writeln('profile = "${_profile(settings.baseModel)}"');
    out.writeln();

    out.writeln('[cpu]');
    out.writeln('model = "${_cpu(settings)}"');
    // fpu = true on a 68000/68010 fails validation outright (the FPU needs
    // the 020+ coprocessor interface), so an A500 with a 68881 optioned in
    // the .uae has to lose it here rather than fail the whole build.
    if (settings.fpuModel > 0 && settings.cpuModel >= 68020) {
      out.writeln('fpu = true');
    }
    // Copperline's [cpu] jit is deliberately NOT forwarded: it is a
    // batch/trace path that flat-bills one CPU clock per instruction, so a
    // 14 MHz machine must retire ~14M guest instructions per second of
    // host-interpreted work (measured ~4-6 fps, pinned at 96% CPU). The
    // precise interpreter bills realistic cycles and holds a full 50 fps
    // PAL on the same host. cachesize/cpu_speed=max are Amiberry knobs.
    // ignore: no `jit = true` here on purpose
    out.writeln();

    out.writeln('[chipset]');
    _writeChipset(out, settings);
    out.writeln();

    out.writeln('[memory]');
    // chipRam counts half-megabytes, slowRam quarter-megabytes. Each has a
    // hard ceiling in the core (512K on OCS, 2M otherwise; 512K trapdoor;
    // 8M Zorro II fast) past which the whole machine refuses to build, so
    // an over-generous .uae is clamped, not carried.
    final int chipK = (settings.chipRam * 512).clamp(
      512,
      settings.chipset == 'ocs' && settings.chipRam * 512 <= 512
          ? 512
          : 2048,
    );
    if (chipK != settings.chipRam * 512) {
      AppLog.warn(
        'launch',
        'copperline: chip RAM ${settings.chipRam * 512}K exceeds the '
            'chipset ceiling; clamped to ${chipK}K',
      );
    }
    final int slowK = (settings.slowRam * 256).clamp(0, 512);
    if (slowK != settings.slowRam * 256) {
      AppLog.warn(
        'launch',
        'copperline: slow RAM ${settings.slowRam * 256}K exceeds the '
            '512K trapdoor maximum; clamped',
      );
    }
    final int fastM = settings.fastRam.clamp(0, 8);
    if (fastM != settings.fastRam) {
      AppLog.warn(
        'launch',
        'copperline: fast RAM ${settings.fastRam}M exceeds the 8M '
            'Zorro II space; clamped',
      );
    }
    out.writeln('chip = "${chipK}K"');
    out.writeln('slow = "${slowK}K"');
    out.writeln('fast = "${fastM}M"');
    // z3 sits above the 24-bit horizon; asking for it on an EC020-class
    // machine fails validation rather than silently shrinking.
    if (settings.z3Ram > 0) {
      if (_cpu32Bit(settings)) {
        out.writeln('z3 = "${settings.z3Ram}M"');
      } else {
        AppLog.warn(
          'launch',
          'copperline: ${settings.z3Ram}M Zorro III RAM needs a 32-bit CPU; '
              'the drive is skipped',
        );
      }
    }
    out.writeln();

    // RTG: a Zorro III card needs a 32-bit CPU; a 24-bit machine gets the
    // Zorro II Picasso II+ instead. True-colour needs no flag: both cards
    // offer their full mode list.
    if (settings.useRtg) {
      out.writeln('[rtg]');
      if (!_cpu32Bit(settings)) {
        out.writeln('card = "picasso2plus"');
        out.writeln('vram = "2M"');
      } else {
        out.writeln('card = "z3660"');
      }
      out.writeln();
    }

    // Floppies. A drive with type -1 is not wired at all.
    final List<String> floppies = <String>[
      settings.floppy0,
      settings.floppy1,
      settings.floppy2,
      settings.floppy3,
    ];
    final List<int> types = <int>[
      settings.floppy0Type,
      settings.floppy1Type,
      settings.floppy2Type,
      settings.floppy3Type,
    ];
    // `drives` counts connected bays from df0 up, not populated slots:
    // media on df2 with drives = 2 fails validation. The number is the
    // highest wired bay + 1; a sparse .uae simply shows an empty drive.
    int drives = 0;
    for (int i = 0; i < 4; i++) {
      if (types[i] != -1) drives = i + 1;
    }
    out.writeln('[floppy]');
    out.writeln('drives = $drives');
    for (int i = 0; i < 4; i++) {
      if (types[i] == -1 || floppies[i].isEmpty) continue;
      out.writeln();
      out.writeln('[floppy.df$i]');
      out.writeln('path = ${_esc(floppies[i])}');
    }
    out.writeln();

    // CD: the consoles take it on their own controller; elsewhere it goes
    // on the SCSI bus, the one controller that takes an ATAPI drive on any
    // machine (copperhf rejects optical media).
    final bool console = settings.baseModel == AmigaModel.cd32 ||
        settings.baseModel == AmigaModel.cdtv;
    final String cdImage = settings.cdImage.trim();
    final List<String> images = settings.hardDrives
        .where((String p) => p.isNotEmpty && !isDir(p))
        // copperhf mounts a raw image or nothing. A file the core would
        // reject anyway -- an archive picked as a drive, a truncated image
        // -- currently kills the machine's build: the launch ends with no
        // machine and nothing on the resume shelf. Size is exactly what the
        // core checks (a non-empty multiple of 512), so check it here and
        // drop what can never have been a disk. SAF content URIs stay
        // untouched: their size is unknowable this side of the platform.
        .where((String p) {
          if (p.startsWith('content://')) return true;
          final int size = sizeOfImage(p);
          if (size > 0 && size % 512 == 0) return true;
          AppLog.warn(
            'launch',
            'copperline: "$p" cannot be a raw hardfile; the drive is skipped',
          );
          return false;
        })
        .toList();
    final List<String> dirs = settings.hardDrives
        .where((String p) => p.isNotEmpty && isDir(p))
        .toList();
    final bool cdOnScsi = cdImage.isNotEmpty && !console;
    final int scsiUnits = (images.length > 7 ? images.length - 7 : 0) +
        (cdOnScsi ? 1 : 0);

    if (console) {
      out.writeln('[cd]');
      if (cdImage.isNotEmpty) out.writeln('image = ${_esc(cdImage)}');
      out.writeln();
    }

    // Hard drives. Directories become live filesystem mounts; images follow
    // the same IDE-vs-emulated-controller split as the .uae generator, with
    // copperhf standing in for uaehf.
    final bool useIde = _usesIde(settings, images, rdb, sizeOfImage);
    if (useIde) {
      out.writeln('[ide]');
      for (int i = 0; i < images.length; i++) {
        final String slot = i == 0 ? 'master' : 'slave';
        final int bootPri = i == 0 ? 0 : -128;
        out.writeln(
          '$slot = { path = ${_esc(images[i])}, bootpri = $bootPri }',
        );
      }
      out.writeln();
    } else if (images.isNotEmpty) {
      // copperhf has seven units; a larger set overflows onto the SCSI bus,
      // which boots off the bundled A2091 ROM and needs no Kickstart driver.
      out.writeln('[copperhf]');
      final int onHf = images.length.clamp(0, 7);
      for (int i = 0; i < onHf; i++) {
        out.writeln(
          'unit$i = { path = ${_esc(images[i])}, bootpri = ${i == 0 ? 0 : -128} }',
        );
      }
      out.writeln();
    }
    if (scsiUnits > 0) {
      out.writeln('[scsi]');
      out.writeln('controller = "a2091"');
      // The A2091 boots off Copperline's own open ROM; name the staged copy
      // because the bundled-ROM search does not reach inside an app bundle.
      out.writeln('rom = ${_esc(a2091Rom)}');
      int unit = 0;
      for (int i = 7; i < images.length && unit < 7; i++, unit++) {
        out.writeln('unit$unit = ${_esc(images[i])}');
      }
      if (cdOnScsi && unit < 7) {
        out.writeln('unit$unit = ${_esc(cdImage)}');
      }
      out.writeln();
    }
    for (final String dir in dirs) {
      final String name = dir.split('/').last;
      out.writeln('[[filesys]]');
      out.writeln('path = ${_esc(dir)}');
      out.writeln('volume = ${_esc(name.isEmpty ? 'Host' : name)}');
      out.writeln('bootpri = -128');
      out.writeln();
    }

    // WHDLoad: the archive arrives on the command line (--whdload); what the
    // TOML carries is where its Kickstarts and save library live, which is
    // the same staging the Amiberry booter is fed.
    final String? home = await WhdloadSupport.home();
    if (home != null && home.isNotEmpty) {
      out.writeln('[whdload]');
      out.writeln('kickstarts = ${_esc('$home/WHDBoot/save-data/Kickstarts')}');
      out.writeln('library = ${_esc('$support/copperline/whdload')}');
      // The archives Copperline's booter unpacks, staged from the app's own
      // assets -- the WHDLoad_usr.lha Amiberry consumes unpacked, this core
      // reads whole.
      out.writeln('whd_package = ${_esc(whdPackage)}');
      out.writeln('skick_package = ${_esc(skickPackage)}');
      out.writeln();
    }

    // Input: the on-screen pads reach the core through the host API, so the
    // TOML only says what sits in each port as the baseline.
    out.writeln('[input]');
    out.writeln(
      'port1 = "${settings.joyport0 == 'mouse' ? 'mouse' : 'joystick'}"',
    );
    // A console (or a setup whose pad is the CD32 one) holds a CD32 pad;
    // a port the config empties stays empty; anything else is a joystick.
    final String port2 = settings.onScreenCd32Pad ||
            settings.baseModel == AmigaModel.cd32
        ? 'cd32'
        : (settings.joyport1 == 'none' ? 'none' : 'joystick');
    out.writeln('port2 = "$port2"');
    out.writeln();

    out.writeln('[audio]');
    out.writeln('channel_mode = "${settings.soundChannels == 'mono' ? 'mono' : 'stereo'}"');
    // The .uae scale is 0-10, Copperline's 0-100.
    out.writeln('stereo_separation = ${settings.soundStereoSeparation * 10}');
    out.writeln('output_enabled = ${settings.soundOutput == 'none' ? 'false' : 'true'}');
    out.writeln();

    out.writeln('[display]');
    if (settings.autoCrop) out.writeln('autocrop = true');
    out.writeln();

    // No keys for: cpu_compatible / cycle_exact (Copperline runs one
    // deterministic clock), immediate_blits, collision_level, sound
    // interpolation, gfx sizes (the host owns presentation), onscreen_*,
    // floppy drive model (the dfN section has none), bsdsocket (the
    // hostsocket board is a different feature).
    return out.toString();
  }

  /// Where the scratch TOML for [uaePath] goes: beside it, hidden from the
  /// shelf listing by the same leading dot as .current_settings.uae.
  static String scratchPathFor(String uaePath) {
    final int slash = uaePath.lastIndexOf('/');
    final String dir = slash < 0 ? '.' : uaePath.substring(0, slash);
    String name = slash < 0 ? uaePath : uaePath.substring(slash + 1);
    if (name.endsWith('.uae')) name = name.substring(0, name.length - 4);
    return '$dir/.$name.copperline.toml';
  }

  /// Parses [uaePath], writes its TOML, returns the file. The config is
  /// assumed freshly repaired -- every launch path calls
  /// ConfigStore.repairConfigFile before handing the path over.
  static Future<File> writeScratch(String uaePath) async {
    final String text = File(uaePath).readAsStringSync();
    final EmulatorSettings settings = ConfigParser.parse(text);
    return writeScratchSettings(settings, uaePath);
  }

  static Future<File> writeScratchSettings(
    EmulatorSettings settings,
    String uaePath,
  ) async {
    final File file = File(scratchPathFor(uaePath));
    file.writeAsStringSync(await generate(settings));
    return file;
  }

  static int _imageSize(String path) {
    if (path.startsWith('content://')) return 0;
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }
}
