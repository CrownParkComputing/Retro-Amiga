import 'amiga_model.dart';
import 'emulator_settings.dart';

/// Reads a .uae file back into [EmulatorSettings].
///
/// The generator is the authority on what a config looks like; this is its
/// inverse, and only for the keys it writes. Anything else in the file - keys
/// a user added by hand, or ones a future core adds - is left alone by the
/// editor, because [ConfigStore.saveOver] keeps the original text for
/// everything the editor did not touch.
///
/// A missing key means the default, which is why this starts from a settings
/// object for the machine rather than from nothing: a config that does not
/// mention chipmem still has whatever the machine implies.
class ConfigParser {
  const ConfigParser._();

  static Map<String, String> _pairs(String text) {
    final Map<String, String> out = <String, String>{};
    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(';') || trimmed.startsWith('#')) {
        continue;
      }
      final int equals = trimmed.indexOf('=');
      if (equals <= 0) continue;
      // Later wins: the core takes the last value for a repeated key.
      out[trimmed.substring(0, equals).trim()] =
          trimmed.substring(equals + 1).trim();
    }
    return out;
  }

  static bool _bool(String? value, bool fallback) {
    if (value == null) return fallback;
    final String v = value.toLowerCase();
    return v == 'true' || v == 'yes' || v == '1';
  }

  static int _int(String? value, int fallback) =>
      value == null ? fallback : (int.tryParse(value) ?? fallback);

  /// The machine a config was made for.
  ///
  /// Inferred rather than read: no key in the file names the model, because
  /// the core has no such setting - a config is hardware, and the model is
  /// just a set of hardware. So the chipset and the CPU are read back the same
  /// way the shelf reads them, and the two must agree or an edited config
  /// would come back as a different machine.
  static AmigaModel modelFrom(String text) {
    final Map<String, String> pairs = _pairs(text);
    if (_bool(pairs['cd32cd'], false)) return AmigaModel.cd32;
    if (_bool(pairs['cdtv'], false)) return AmigaModel.cdtv;

    final String chipset = (pairs['chipset'] ?? '').toLowerCase();
    final int cpu = _int(pairs['cpu_model'], 68000);

    if (chipset == 'aga') {
      return cpu >= 68040 ? AmigaModel.a4000 : AmigaModel.a1200;
    }
    if (cpu >= 68030) return AmigaModel.a3000;
    if (chipset.startsWith('ecs')) return AmigaModel.a600;
    return AmigaModel.a500;
  }

  static EmulatorSettings parse(String text, {AmigaModel? model}) {
    final Map<String, String> pairs = _pairs(text);
    final AmigaModel machine = model ?? modelFrom(text);
    final EmulatorSettings defaults = EmulatorSettings.fromModel(machine);

    return defaults.copyWith(
      // Key names are the generator's: cpu_model and compfpu, not cpu_type and
      // comp_fpu. Reading a key the generator never writes means silently
      // falling back to the machine default, which looks right whenever the
      // config happens to hold the default and wrong the rest of the time.
      cpuModel: _int(pairs['cpu_model'], defaults.cpuModel),
      cpuCompatible: _bool(pairs['cpu_compatible'], defaults.cpuCompatible),
      address24Bit:
          _bool(pairs['cpu_24bit_addressing'], defaults.address24Bit),
      cpuSpeed: pairs['cpu_speed'] ?? defaults.cpuSpeed,
      fpuModel: _int(pairs['fpu_model'], defaults.fpuModel),
      jitCacheSize: _int(pairs['cachesize'], defaults.jitCacheSize),
      jitFpu: _bool(pairs['compfpu'], defaults.jitFpu),

      chipset: pairs['chipset'] ?? defaults.chipset,
      immediateBlits: _bool(pairs['immediate_blits'], defaults.immediateBlits),
      collisionLevel: pairs['collision_level'] ?? defaults.collisionLevel,
      cycleExact: _bool(pairs['cycle_exact'], defaults.cycleExact),
      ntsc: _bool(pairs['ntsc'], defaults.ntsc),

      chipRam: _int(pairs['chipmem_size'], defaults.chipRam),
      slowRam: _int(pairs['bogomem_size'], defaults.slowRam),
      fastRam: _int(pairs['fastmem_size'], defaults.fastRam),
      z3Ram: _int(pairs['z3mem_size'], defaults.z3Ram),

      romFile: pairs['kickstart_rom_file'] ?? defaults.romFile,
      romExtFile: pairs['kickstart_ext_rom_file'] ?? defaults.romExtFile,

      floppy0: pairs['floppy0'] ?? defaults.floppy0,
      floppy1: pairs['floppy1'] ?? defaults.floppy1,
      floppy2: pairs['floppy2'] ?? defaults.floppy2,
      floppy3: pairs['floppy3'] ?? defaults.floppy3,
      floppy0Type: _int(pairs['floppy0type'], defaults.floppy0Type),
      floppy1Type: _int(pairs['floppy1type'], defaults.floppy1Type),
      floppy2Type: _int(pairs['floppy2type'], defaults.floppy2Type),
      floppy3Type: _int(pairs['floppy3type'], defaults.floppy3Type),

      // The CD line carries options after the path: "image" and the like.
      cdImage: (pairs['cdimage0'] ?? defaults.cdImage).split(',').first,
      cd32Fmv: _bool(pairs['cd32fmv'], defaults.cd32Fmv),
      whdloadFilename: pairs['whdload_filename'] ?? defaults.whdloadFilename,

      soundFreq: _int(pairs['sound_frequency'], defaults.soundFreq),
      soundChannels: pairs['sound_channels'] ?? defaults.soundChannels,
      soundStereoSeparation:
          _int(pairs['sound_stereo_separation'], defaults.soundStereoSeparation),
      soundInterpolation:
          pairs['sound_interpol'] ?? defaults.soundInterpolation,

      correctAspect: _bool(
        pairs['amiberry.gfx_correct_aspect'] ?? pairs['gfx_correct_aspect'],
        defaults.correctAspect,
      ),
      showLeds: _bool(pairs['show_leds'], defaults.showLeds),

      // Hard drives are read back because the editor rewrites the whole file:
      // anything not parsed is not written, and a setup that lost its hard
      // drive on being edited is worse than one that could not be edited.
      hardDrives: _hardDrives(text),
    );
  }

  /// The paths of every hard drive a config mounts, in order.
  ///
  /// Both spellings the generator uses are read: hardfile2 for an image and
  /// filesystem2 for a directory. The path sits in the field after the device
  /// name and may be quoted.
  static List<String> _hardDrives(String text) {
    final List<String> drives = <String>[];

    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      final bool isImage = trimmed.startsWith('hardfile2=');
      final bool isDirectory = trimmed.startsWith('filesystem2=');
      if (!isImage && !isDirectory) continue;

      // hardfile2=rw,DH0:"path",...     filesystem2=rw,DH0:Label:"path",...
      final int colon = trimmed.indexOf(':');
      if (colon < 0) continue;
      String rest = trimmed.substring(colon + 1);
      if (isDirectory) {
        // Skip the volume label.
        final int second = rest.indexOf(':');
        if (second < 0) continue;
        rest = rest.substring(second + 1);
      }

      String path = rest;
      if (path.startsWith('"')) {
        final int end = path.indexOf('"', 1);
        if (end > 0) path = path.substring(1, end);
      } else {
        final int comma = path.indexOf(',');
        if (comma > 0) path = path.substring(0, comma);
      }
      path = path.trim();
      if (path.isNotEmpty) drives.add(path);
    }

    return drives.isEmpty ? const <String>[''] : drives;
  }
}
