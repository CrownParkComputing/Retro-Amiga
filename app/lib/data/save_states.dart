import 'dart:io';

import 'host_paths.dart';

/// A game you can pick up where you left it.
class SaveState {
  const SaveState({
    required this.title,
    required this.statePath,
    required this.configPath,
    required this.savedAt,
  });

  final String title;

  /// The .uss the core wrote.
  final String statePath;

  /// The config it was running, so the machine comes back the same.
  final String configPath;

  final DateTime savedAt;

  bool get exists => File(statePath).existsSync();

  /// "3 minutes ago" and the like. Relative rather than a clock time, because
  /// what matters is which of five is the one you were just playing.
  String get ago {
    final Duration since = DateTime.now().difference(savedAt);
    if (since.inMinutes < 1) return 'just now';
    if (since.inMinutes < 60) return '${since.inMinutes} min ago';
    if (since.inHours < 24) {
      return '${since.inHours} hour${since.inHours == 1 ? '' : 's'} ago';
    }
    return '${since.inDays} day${since.inDays == 1 ? '' : 's'} ago';
  }
}

/// The last few games, as the emulator left them.
///
/// The emulator writes a save state when a session ends and records it in a
/// flat index; this reads it. Both halves are deliberately simple - four
/// tab-separated fields - because the writer is Java in one process and the
/// reader is Dart in another, and a format both can be trusted with beats a
/// format either could get subtly wrong.
class SaveStates {
  const SaveStates._();

  /// Matches the cap the writer enforces.
  static const int keep = 5;

  static Future<Directory> _directory() async {
    final Directory dir = Directory('${await HostPaths.appSupport()}/states');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<List<SaveState>> list() async {
    try {
      final File index = File('${(await _directory()).path}/recent.txt');
      if (!index.existsSync()) return <SaveState>[];

      final List<SaveState> states = <SaveState>[];
      for (final String line in index.readAsLinesSync()) {
        final List<String> parts = line.split('\t');
        if (parts.length < 4) continue;
        final int millis = int.tryParse(parts[0]) ?? 0;
        final SaveState state = SaveState(
          savedAt: DateTime.fromMillisecondsSinceEpoch(millis),
          title: parts[1],
          statePath: parts[2],
          configPath: parts[3],
        );
        // A state whose file has gone is not worth offering.
        if (state.exists) states.add(state);
      }
      return states;
    } on Object {
      return <SaveState>[];
    }
  }

  static Future<void> remove(SaveState state) async {
    try {
      final File file = File(state.statePath);
      if (file.existsSync()) file.deleteSync();

      final File index = File('${(await _directory()).path}/recent.txt');
      if (!index.existsSync()) return;
      final List<String> kept = index
          .readAsLinesSync()
          .where((String l) => !l.contains(state.statePath))
          .toList();
      index.writeAsStringSync('${kept.join('\n')}\n');
    } on Object {
      // Leaving a stale entry is harmless: list() drops what is not there.
    }
  }
}
