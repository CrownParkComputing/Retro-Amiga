import 'amiga_model.dart';

/// Everything a saved setup holds, in the shape the core's .uae files expect.
///
/// Field names follow cfgfile_save_options() in the core rather than anything
/// Dart-idiomatic, so a reader can match them against a config file by eye.
class EmulatorSettings {
  const EmulatorSettings({
    this.baseModel = AmigaModel.a500,
    // CPU
    this.cpuModel = 68000,
    this.cpuCompatible = true,
    this.address24Bit = true,
    this.cpuSpeed = 'real', // 'max' or 'real'
    this.fpuModel = 0, // 0 = none, else 68881 / 68882 / 68040
    this.jitCacheSize = 0, // 0 = disabled, else KB
    this.jitFpu = false,
    // Chipset
    this.chipset = 'ocs', // ocs, ecs_agnus, ecs_denise, ecs, aga
    this.immediateBlits = false,
    this.collisionLevel = 'playfields',
    this.cycleExact = false,
    this.ntsc = false,
    this.useRtg = false,
    // Memory
    this.chipRam = 1, // half-megabytes: 1 = 512KB, 2 = 1MB, 4 = 2MB
    this.slowRam = 2, // 256KB units
    this.fastRam = 0, // megabytes
    this.z3Ram = 0, // megabytes
    // ROM
    this.romFile = '',
    this.romExtFile = '',
    // Floppies
    this.floppy0 = '',
    this.floppy0Type = 0, // 0 = 3.5" DD, 1 = 3.5" HD, -1 = disabled
    this.floppy1 = '',
    this.floppy1Type = -1,
    this.floppy2 = '',
    this.floppy2Type = -1,
    this.floppy3 = '',
    this.floppy3Type = -1,
    // CD
    this.cdImage = '',
    this.cd32Fmv = false,
    // WHDLoad
    this.whdloadFilename = '',
    // Hard drives
    this.hardDrives = const <String>[''],
    // Sound
    this.soundOutput = 'exact',
    this.soundFreq = 44100,
    this.soundChannels = 'stereo',
    this.soundStereoSeparation = 7,
    this.soundInterpolation = 'anti',
    // Display
    this.gfxWidth = 720,
    this.gfxHeight = 568,
    this.rtgWidth = 1920,
    this.rtgHeight = 1080,
    this.correctAspect = false,
    this.autoCrop = false,
    this.showLeds = false,
    // Input
    this.joyport0 = 'mouse',
    this.joyport1 = 'none',
    this.onScreenJoystick = false,
    this.onScreenCd32Pad = false,
    this.onScreenKeyboard = true,
  });

  final AmigaModel baseModel;

  final int cpuModel;
  final bool cpuCompatible;
  final bool address24Bit;
  final String cpuSpeed;
  final int fpuModel;
  final int jitCacheSize;
  final bool jitFpu;

  final String chipset;
  final bool immediateBlits;
  final String collisionLevel;
  final bool cycleExact;
  final bool ntsc;
  final bool useRtg;

  final int chipRam;
  final int slowRam;
  final int fastRam;
  final int z3Ram;

  final String romFile;
  final String romExtFile;

  final String floppy0;
  final int floppy0Type;
  final String floppy1;
  final int floppy1Type;
  final String floppy2;
  final int floppy2Type;
  final String floppy3;
  final int floppy3Type;

  final String cdImage;
  final bool cd32Fmv;

  final String whdloadFilename;

  final List<String> hardDrives;

  final String soundOutput;
  final int soundFreq;
  final String soundChannels;
  final int soundStereoSeparation;
  final String soundInterpolation;

  final int gfxWidth;
  final int gfxHeight;
  final int rtgWidth;
  final int rtgHeight;
  final bool correctAspect;
  final bool autoCrop;
  final bool showLeds;

  final String joyport0;
  final String joyport1;
  final bool onScreenJoystick;
  final bool onScreenCd32Pad;
  final bool onScreenKeyboard;

  /// Hardware defaults per machine, matching what the real thing shipped with.
  factory EmulatorSettings.fromModel(AmigaModel model) {
    switch (model) {
      case AmigaModel.a500:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68000,
          chipset: 'ocs',
          chipRam: 1,
          slowRam: 2,
          cycleExact: true,
        );
      case AmigaModel.a500Plus:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68000,
          chipset: 'ecs',
          chipRam: 2,
          slowRam: 0,
          cycleExact: true,
        );
      case AmigaModel.a600:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68000,
          chipset: 'ecs',
          chipRam: 2,
          slowRam: 0,
          cycleExact: true,
        );
      case AmigaModel.a1000:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68000,
          chipset: 'ocs',
          chipRam: 1,
          slowRam: 0,
          cycleExact: true,
        );
      case AmigaModel.a2000:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68000,
          chipset: 'ocs',
          chipRam: 1,
          slowRam: 2,
          cycleExact: true,
        );
      case AmigaModel.a1200:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68020,
          chipset: 'aga',
          chipRam: 4,
          slowRam: 0,
          address24Bit: false,
          cpuSpeed: 'max',
          cycleExact: false,
        );
      case AmigaModel.a3000:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68030,
          chipset: 'ecs',
          chipRam: 4,
          slowRam: 0,
          fastRam: 8,
          address24Bit: false,
          cpuSpeed: 'max',
        );
      case AmigaModel.a4000:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68040,
          chipset: 'aga',
          chipRam: 4,
          slowRam: 0,
          fastRam: 8,
          address24Bit: false,
          fpuModel: 68040,
          cpuSpeed: 'max',
          jitCacheSize: 16384,
          jitFpu: true,
        );
      case AmigaModel.cd32:
        // Real CD32 hardware: 68EC020, so 24-bit addressing, AGA, 2MB chip,
        // no fast RAM and no floppy. Deliberately no JIT - CD32 titles are
        // timing-sensitive and many rely on 24-bit-addressing quirks that JIT
        // mode breaks. Interpreted 68020 at "approximate" speed is the right
        // trade: not the slow cycle-exact model, but still a real 68020.
        // Booting needs the CD32 kickstart plus its extended ROM.
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68020,
          chipset: 'aga',
          chipRam: 4,
          slowRam: 0,
          address24Bit: true,
          cpuSpeed: 'real',
          cycleExact: false,
          floppy0Type: -1,
        );
      case AmigaModel.cdtv:
        return EmulatorSettings(
          baseModel: model,
          cpuModel: 68000,
          chipset: 'ocs',
          chipRam: 2,
          slowRam: 0,
          cycleExact: true,
          floppy0Type: -1,
        );
    }
  }

  EmulatorSettings copyWith({
    AmigaModel? baseModel,
    int? cpuModel,
    bool? cpuCompatible,
    bool? address24Bit,
    String? cpuSpeed,
    int? fpuModel,
    int? jitCacheSize,
    bool? jitFpu,
    String? chipset,
    bool? immediateBlits,
    String? collisionLevel,
    bool? cycleExact,
    bool? ntsc,
    bool? useRtg,
    int? chipRam,
    int? slowRam,
    int? fastRam,
    int? z3Ram,
    String? romFile,
    String? romExtFile,
    String? floppy0,
    int? floppy0Type,
    String? floppy1,
    int? floppy1Type,
    String? floppy2,
    int? floppy2Type,
    String? floppy3,
    int? floppy3Type,
    String? cdImage,
    bool? cd32Fmv,
    String? whdloadFilename,
    List<String>? hardDrives,
    String? soundOutput,
    int? soundFreq,
    String? soundChannels,
    int? soundStereoSeparation,
    String? soundInterpolation,
    int? gfxWidth,
    int? gfxHeight,
    int? rtgWidth,
    int? rtgHeight,
    bool? correctAspect,
    bool? autoCrop,
    bool? showLeds,
    String? joyport0,
    String? joyport1,
    bool? onScreenJoystick,
    bool? onScreenCd32Pad,
    bool? onScreenKeyboard,
  }) {
    return EmulatorSettings(
      baseModel: baseModel ?? this.baseModel,
      cpuModel: cpuModel ?? this.cpuModel,
      cpuCompatible: cpuCompatible ?? this.cpuCompatible,
      address24Bit: address24Bit ?? this.address24Bit,
      cpuSpeed: cpuSpeed ?? this.cpuSpeed,
      fpuModel: fpuModel ?? this.fpuModel,
      jitCacheSize: jitCacheSize ?? this.jitCacheSize,
      jitFpu: jitFpu ?? this.jitFpu,
      chipset: chipset ?? this.chipset,
      immediateBlits: immediateBlits ?? this.immediateBlits,
      collisionLevel: collisionLevel ?? this.collisionLevel,
      cycleExact: cycleExact ?? this.cycleExact,
      ntsc: ntsc ?? this.ntsc,
      useRtg: useRtg ?? this.useRtg,
      chipRam: chipRam ?? this.chipRam,
      slowRam: slowRam ?? this.slowRam,
      fastRam: fastRam ?? this.fastRam,
      z3Ram: z3Ram ?? this.z3Ram,
      romFile: romFile ?? this.romFile,
      romExtFile: romExtFile ?? this.romExtFile,
      floppy0: floppy0 ?? this.floppy0,
      floppy0Type: floppy0Type ?? this.floppy0Type,
      floppy1: floppy1 ?? this.floppy1,
      floppy1Type: floppy1Type ?? this.floppy1Type,
      floppy2: floppy2 ?? this.floppy2,
      floppy2Type: floppy2Type ?? this.floppy2Type,
      floppy3: floppy3 ?? this.floppy3,
      floppy3Type: floppy3Type ?? this.floppy3Type,
      cdImage: cdImage ?? this.cdImage,
      cd32Fmv: cd32Fmv ?? this.cd32Fmv,
      whdloadFilename: whdloadFilename ?? this.whdloadFilename,
      hardDrives: hardDrives ?? this.hardDrives,
      soundOutput: soundOutput ?? this.soundOutput,
      soundFreq: soundFreq ?? this.soundFreq,
      soundChannels: soundChannels ?? this.soundChannels,
      soundStereoSeparation:
          soundStereoSeparation ?? this.soundStereoSeparation,
      soundInterpolation: soundInterpolation ?? this.soundInterpolation,
      gfxWidth: gfxWidth ?? this.gfxWidth,
      gfxHeight: gfxHeight ?? this.gfxHeight,
      rtgWidth: rtgWidth ?? this.rtgWidth,
      rtgHeight: rtgHeight ?? this.rtgHeight,
      correctAspect: correctAspect ?? this.correctAspect,
      autoCrop: autoCrop ?? this.autoCrop,
      showLeds: showLeds ?? this.showLeds,
      joyport0: joyport0 ?? this.joyport0,
      joyport1: joyport1 ?? this.joyport1,
      onScreenJoystick: onScreenJoystick ?? this.onScreenJoystick,
      onScreenCd32Pad: onScreenCd32Pad ?? this.onScreenCd32Pad,
      onScreenKeyboard: onScreenKeyboard ?? this.onScreenKeyboard,
    );
  }
}
