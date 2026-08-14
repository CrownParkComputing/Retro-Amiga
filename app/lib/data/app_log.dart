import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'host_paths.dart';

/// How serious a line is.
enum LogLevel { info, warn, error }

/// One thing that happened.
class LogEntry {
  LogEntry(this.level, this.source, this.message) : at = DateTime.now();

  final LogLevel level;

  /// Which part of the app said it - "scan", "import", "whdload", "launch".
  final String source;

  final String message;
  final DateTime at;

  String get time =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';

  @override
  String toString() => '$time  ${level.name.toUpperCase().padRight(5)}  '
      '${source.padRight(9)}  $message';
}

/// What the app did, kept so a failure can be looked at afterwards.
///
/// The emulator's own log goes to the system log, which needs a cable and a
/// laptop to read. This is the launcher's side - scans, imports, what was
/// launched with which arguments, and anything that went wrong - held in
/// memory and mirrored to a file, so "it did not work" can be answered on the
/// device itself.
class AppLog {
  const AppLog._();

  /// Enough to cover a session without growing without bound.
  static const int _maxEntries = 500;

  static final Queue<LogEntry> _entries = Queue<LogEntry>();
  static final StreamController<LogEntry> _added =
      StreamController<LogEntry>.broadcast();

  static Stream<LogEntry> get added => _added.stream;
  static List<LogEntry> get entries => _entries.toList();

  static void info(String source, String message) =>
      _add(LogEntry(LogLevel.info, source, message));
  static void warn(String source, String message) =>
      _add(LogEntry(LogLevel.warn, source, message));
  static void error(String source, String message) =>
      _add(LogEntry(LogLevel.error, source, message));

  static void _add(LogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    if (!_added.isClosed) _added.add(entry);
    _appendToFile(entry);
  }

  static void clear() {
    _entries.clear();
    if (!_added.isClosed) {
      _added.add(LogEntry(LogLevel.info, 'log', 'cleared'));
    }
  }

  /// The whole buffer as text, for copying out.
  static String asText() => _entries.map((LogEntry e) => '$e').join('\n');

  static File? _file;
  static bool _fileTried = false;

  /// Appended rather than written whole, and failures are swallowed: a log
  /// that throws while recording a problem is worse than no log.
  static Future<void> _appendToFile(LogEntry entry) async {
    try {
      if (!_fileTried) {
        _fileTried = true;
        _file = File('${await HostPaths.appSupport()}/amiga-retro.log');
      }
      await _file?.writeAsString('$entry\n', mode: FileMode.append);
    } on Object {
      // Not being able to write the log is not worth reporting to the log.
    }
  }

  static Future<String> filePath() async =>
      '${await HostPaths.appSupport()}/amiga-retro.log';
}
