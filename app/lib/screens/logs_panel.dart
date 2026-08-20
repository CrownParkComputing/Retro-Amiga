import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_log.dart';
import '../theme/amiga_theme.dart';
import '../ffi/amiga_core.dart';

/// What the app has been doing.
///
/// The emulator's own log goes to the system log, which needs a cable and a
/// laptop to read. This is the launcher's side - scans, imports, what was
/// launched and with which arguments, and anything that failed - readable on
/// the device, which is where the question "why did that not work" is asked.
class LogsPanel extends StatefulWidget {
  const LogsPanel({super.key});

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  StreamSubscription<LogEntry>? _sub;
  final ScrollController _scroll = ScrollController();
  bool _errorsOnly = false;

  /// The EMULATOR's own log, as opposed to the app's.
  ///
  /// With the core running inside this process it writes a log file, and this
  /// is the only place anyone can read it on the device itself -- logcat needs
  /// a computer and a cable, and "it just says Starting the Amiga" is not
  /// something you can debug from the app's own messages. See
  /// AmigaCore.logfilePath.
  bool _coreLog = false;
  String _coreText = '';
  Timer? _coreTimer;

  Future<void> _readCoreLog() async {
    final String? path = AmigaCore.open()?.logfilePath;
    if (path == null) {
      if (mounted) {
        setState(() {
          _coreText = 'The core is not writing a log file. It starts one when '
              'a game launches.';
        });
      }
      return;
    }
    try {
      final File file = File(path);
      if (!file.existsSync()) {
        if (mounted) setState(() => _coreText = 'No log yet: \$path');
        return;
      }
      final List<String> lines = await file.readAsLines();
      // The tail is what matters; a whole session's log is megabytes.
      final List<String> tail = lines.length > 400
          ? lines.sublist(lines.length - 400)
          : lines;
      if (mounted) setState(() => _coreText = tail.join('\n'));
    } catch (e) {
      if (mounted) setState(() => _coreText = 'Could not read \$path: \$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _sub = AppLog.added.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _coreTimer?.cancel();
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<LogEntry> get _visible {
    final List<LogEntry> all = AppLog.entries;
    if (!_errorsOnly) return all;
    return all.where((LogEntry e) => e.level != LogLevel.info).toList();
  }

  static Color _colourFor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return AmigaColors.textDim;
      case LogLevel.warn:
        return AmigaColors.workbenchOrange;
      case LogLevel.error:
        return AmigaColors.tickRed;
    }
  }

  Widget _header(List<LogEntry> entries) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(
            children: <Widget>[
              Text(
                '${entries.length} line${entries.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AmigaColors.text,
                ),
              ),
              const SizedBox(width: 14),
              FilterChip(
                label: const Text('Problems only'),
                selected: _errorsOnly,
                onSelected: (bool on) => setState(() => _errorsOnly = on),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Emulator'),
                selected: _coreLog,
                onSelected: (bool on) {
                  setState(() => _coreLog = on);
                  _coreTimer?.cancel();
                  if (on) {
                    _readCoreLog();
                    // While a game is running the log grows; refreshing beats
                    // asking the user to leave and come back.
                    _coreTimer = Timer.periodic(
                      const Duration(seconds: 2),
                      (_) => _readCoreLog(),
                    );
                  }
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () {
                  // Whichever log is on screen: copying the app's messages
                  // while looking at the emulator's would be a trap.
                  final String text = _coreLog ? _coreText : AppLog.asText();
                  final ScaffoldMessengerState messenger =
                      ScaffoldMessenger.of(context);
                  Clipboard.setData(ClipboardData(text: text));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Log copied.')),
                  );
                },
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(AppLog.clear),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AmigaColors.panelBorder),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<LogEntry> entries = _visible;
    if (_coreLog) {
      return Column(
        children: <Widget>[
          _header(entries),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SelectableText(
                _coreText.isEmpty ? 'Reading...' : _coreText,
                style: const TextStyle(
                  color: AmigaColors.textDim,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        _header(entries),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing logged yet.',
                    style: TextStyle(color: AmigaColors.textDim),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(10),
                  // Newest first: the last thing that happened is the thing
                  // being asked about.
                  reverse: true,
                  itemCount: entries.length,
                  itemBuilder: (BuildContext context, int i) {
                    final LogEntry entry = entries[entries.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                          children: <TextSpan>[
                            TextSpan(
                              text: '${entry.time}  ',
                              style: const TextStyle(
                                color: AmigaColors.textDim,
                              ),
                            ),
                            TextSpan(
                              text: '${entry.source.padRight(9)} ',
                              style: TextStyle(
                                color: _colourFor(entry.level),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: entry.message,
                              style: TextStyle(
                                color: entry.level == LogLevel.info
                                    ? AmigaColors.text
                                    : _colourFor(entry.level),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
