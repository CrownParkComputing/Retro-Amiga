/// The Amiga hardware the core can emulate.
///
/// [cmdArg] matches the --model handler in the core's main.cpp; changing one
/// without the other silently boots the wrong machine.
enum AmigaModel {
  a500(
    'A500',
    'Amiga 500',
    'OCS, 68000, 512KB Chip + 512KB Slow',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a500',
  ),
  a500Plus(
    'A500P',
    'Amiga 500+',
    'ECS, 68000, 1MB Chip',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a500',
  ),
  a600(
    'A600',
    'Amiga 600',
    'ECS, 68000, 2MB Chip',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a500',
  ),
  a1000(
    'A1000',
    'Amiga 1000',
    'OCS, 68000, 512KB Chip',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a500',
  ),
  a2000(
    'A2000',
    'Amiga 2000',
    'OCS/ECS, 68000, 512KB Chip + 512KB Slow',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a500',
  ),
  a1200(
    'A1200',
    'Amiga 1200',
    'AGA, 68020, 2MB Chip',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a1200',
  ),
  a3000(
    'A3000',
    'Amiga 3000',
    'ECS, 68030, 2MB Chip + 8MB Fast',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a3000',
  ),
  a4000(
    'A4000',
    'Amiga 4000',
    'AGA, 68040, 2MB Chip + 8MB Fast',
    hasFloppy: true,
    hasCd: false,
    artwork: 'a4000',
  ),
  cd32(
    'CD32',
    'CD32',
    'AGA console, 68EC020, CD drive',
    hasFloppy: false,
    hasCd: true,
    artwork: 'cd32',
  ),
  cdtv(
    'CDTV',
    'CDTV',
    'ECS, 68000, CD drive',
    hasFloppy: false,
    hasCd: true,
    artwork: 'cd32',
  );

  const AmigaModel(
    this.cmdArg,
    this.displayName,
    this.description, {
    required this.hasFloppy,
    required this.hasCd,
    required this.artwork,
  });

  final String cmdArg;
  final String displayName;
  final String description;
  final bool hasFloppy;
  final bool hasCd;

  /// Machine photo. Several models share one: the wedge cases look alike, as
  /// do the towers, and the CD32 stands in for both CD consoles.
  final String artwork;

  String get artworkPath => 'assets/machines/$artwork.png';

  /// Whether the JIT can do anything here.
  ///
  /// It recompiles 68020 and later; on a 68000 or 68010 there is nothing for
  /// it to translate, so the toggle would be a switch that does nothing.
  /// Read from the description rather than a new field, because that string
  /// already names the CPU and two sources of the same fact drift apart.
  bool get canJit =>
      description.contains('68020') ||
      description.contains('68030') ||
      description.contains('68040') ||
      description.contains('68060');

  /// Whether a graphics card can be plugged in. It needs a Zorro bus, which
  /// the wedge machines and both consoles do not have.
  /// A1200 included: it has no Zorro slots itself, but every accelerator that
  /// matters brings them, and an RTG A1200 is what AGS and the RTG game builds
  /// actually run on.
  bool get canRtg => switch (this) {
    AmigaModel.a1200 ||
    AmigaModel.a2000 ||
    AmigaModel.a3000 ||
    AmigaModel.a4000 => true,
    _ => false,
  };

  /// A CD console needs its own Kickstart and an extended ROM alongside it.
  /// Without the second one it starts and shows nothing.
  bool get needsExtendedRom => hasCd;

  static AmigaModel? fromCmdArg(String arg) {
    for (final AmigaModel model in AmigaModel.values) {
      if (model.cmdArg.toUpperCase() == arg.toUpperCase()) return model;
    }
    return null;
  }
}
