import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_log.dart';
import '../theme/amiga_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _sub = AppLog.added.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<LogEntry> get _visible {
    final List<LogEntry> all = AppLog.entries;
    if (!_errorsOnly) return all;
    return all
        .where((LogEntry e) => e.level != LogLevel.info)
        .toList();
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

  @override
  Widget build(BuildContext context) {
    final List<LogEntry> entries = _visible;

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
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: AppLog.asText()),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
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
