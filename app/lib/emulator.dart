import 'package:flutter/services.dart';

/// The one road from the Flutter UI into the emulator core.
///
/// Every platform binds the same channel: on Android it starts the SDL
/// activity in its own process, on iOS it presents the emulator view
/// controller, on desktop it runs the core as a child process. The Dart side
/// only ever hands over an argument list, exactly as the command line takes.
class Emulator {
  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// Starts emulation. [args] is passed through verbatim to the core.
  static Future<void> launch(List<String> args) async {
    await _channel.invokeMethod<bool>('launch', <String, Object?>{'args': args});
  }

  /// Which host implementation answered, for showing platform-specific UI.
  static Future<String> platformName() async {
    return await _channel.invokeMethod<String>('platformName') ?? 'unknown';
  }

  /// Boots straight into a machine with no media, the quickest way to prove
  /// the whole chain works. `-G` keeps the core from expecting a GUI of its
  /// own — this fork has none.
  static Future<void> launchModel(String model) {
    return launch(<String>['--rescan-roms', '--model', model, '-G']);
  }

  /// Boots a machine with a floppy in DF0.
  static Future<void> launchFloppy(String model, String path) {
    return launch(<String>[
      '--rescan-roms',
      '--model',
      model,
      '-0',
      path,
      '-G',
    ]);
  }

  /// Runs a saved .uae configuration.
  static Future<void> launchConfig(String configPath) {
    return launch(<String>['--rescan-roms', '--config', configPath, '-G']);
  }
}

/// The machines the core knows, with the command-line name it expects.
class AmigaModel {
  const AmigaModel(this.id, this.name, this.blurb);

  final String id;
  final String name;
  final String blurb;

  static const List<AmigaModel> all = <AmigaModel>[
    AmigaModel('A500', 'Amiga 500', 'OCS, 512K chip — the one under the telly'),
    AmigaModel('A500P', 'Amiga 500+', 'ECS, 1MB chip'),
    AmigaModel('A600', 'Amiga 600', 'ECS, IDE'),
    AmigaModel('A1200', 'Amiga 1200', 'AGA, 68020 — the one you saved up for'),
    AmigaModel('A4000', 'Amiga 4000', 'AGA, 68040'),
    AmigaModel('CD32', 'CD32', 'AGA console, CD drive'),
    AmigaModel('CDTV', 'CDTV', 'ECS, CD drive'),
  ];
}
