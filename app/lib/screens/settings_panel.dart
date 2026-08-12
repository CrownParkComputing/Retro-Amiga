import 'dart:io';

import 'package:flutter/material.dart';

import '../data/media_library.dart';
import '../data/media_root.dart';
import '../data/whdload_support.dart';
import '../theme/amiga_theme.dart';

/// Where things live and how they get there, after setup has run.
///
/// The same three actions setup offers - choose the media folder, file
/// everything into it, install WHDLoad - because none of them is a one-off:
/// media arrives on a device long after the first run.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  String _root = '';
  MediaIndex _index = const MediaIndex.empty();
  WhdloadStatus _whdload = const WhdloadStatus(
    bootArchiveInstalled: false,
    kickstartCount: 0,
  );

  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String root = await MediaRoot.path();
    final MediaIndex index = await MediaLibrary.cached();
    final WhdloadStatus whdload = await WhdloadSupport.status();
    if (!mounted) return;
    setState(() {
      _root = root;
      _index = index;
      _whdload = whdload;
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final String message = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = message;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const _Header('Media'),
        Card(
          color: AmigaColors.card,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(_root.isEmpty ? '...' : _root),
                subtitle: const Text('Media folder'),
                trailing: MediaRoot.canChoose
                    ? TextButton(
                        onPressed: _busy ? null : _chooseRoot,
                        child: const Text('Change'),
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Scan for media'),
                subtitle: Text('${_index.files.length} files indexed'),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final MediaIndex index = await MediaLibrary.scan();
                            return '${index.files.length} files found.';
                          }),
                  child: const Text('Scan'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('File everything into the media folder'),
                subtitle: const Text(
                  'Moves what is elsewhere into Floppies, HardDrives, CDROMs, '
                  'LHA and Kickstarts, and unpacks disk images out of zips.',
                ),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final ImportResult result =
                                await MediaImporter.import(_index);
                            await MediaLibrary.scan();
                            return '${result.moved} moved, '
                                '${result.alreadyInPlace} already in place'
                                '${result.extracted > 0 ? ', ${result.extracted} unzipped' : ''}'
                                '${result.failed > 0 ? ', ${result.failed} failed' : ''}.';
                          }),
                  child: const Text('Import'),
                ),
              ),
            ],
          ),
        ),

        // Android only, for the same reason setup is: iOS gives the app
        // nothing to search for a boot archive.
        if (Platform.isAndroid) ...<Widget>[
          const _Header('WHDLoad'),
          Card(
            color: AmigaColors.card,
            child: ListTile(
              leading: Icon(
                _whdload.ready ? Icons.check_circle : Icons.inventory_2_outlined,
                color: _whdload.ready ? AmigaColors.tickGreen : null,
              ),
              title: Text(
                _whdload.ready
                    ? 'Ready'
                    : _whdload.bootArchiveInstalled
                        ? 'Boot files installed, no Kickstart yet'
                        : 'Not installed',
              ),
              subtitle: Text(
                _whdload.ready
                    ? '${_whdload.kickstartCount} Kickstart'
                    '${_whdload.kickstartCount == 1 ? '' : 's'} in place.'
                    : 'Needs boot-data.zip somewhere readable - the media '
                        'folder is the obvious place.',
              ),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final WhdloadStatus status =
                              await WhdloadSupport.install(_index);
                          return status.ready
                              ? 'WHDLoad is ready.'
                              : status.bootArchiveInstalled
                                  ? 'Boot files installed, but no Kickstart '
                                      'could be placed.'
                                  : 'No boot archive found.';
                        }),
                child: Text(_whdload.ready ? 'Reinstall' : 'Install'),
              ),
            ),
          ),
        ],

        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _notice!,
              style: const TextStyle(color: AmigaColors.tickGreen),
            ),
          ),
      ],
    );
  }

  Future<void> _chooseRoot() async {
    final TextEditingController controller =
        TextEditingController(text: _root);
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Media folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/sdcard/Amiga',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use this'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (chosen == null || chosen.trim().isEmpty) return;
    await MediaRoot.setPath(chosen.trim());
    await _load();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AmigaColors.accent,
        ),
      ),
    );
  }
}
