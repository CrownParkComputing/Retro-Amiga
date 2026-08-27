import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
import '../data/file_category.dart';
import '../data/hard_drive_set.dart';
import '../data/media_folder.dart';
import '../data/media_library.dart';
import '../data/media_root.dart';
import '../theme/amiga_theme.dart';
import '../widgets/import_progress_dialog.dart';

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

  /// The folder the user granted on Android, shown instead of the internal
  /// destination: it is the one they chose and the only one they can change.
  String? _sourceFolder;
  MediaIndex _index = const MediaIndex.empty();
  bool _busy = false;
  bool _confirmFileDelete = true;
  StreamSubscription<MediaIndex>? _mediaChanges;

  List<HardDriveSet> get _hardDriveSetups => _root.isEmpty
      ? const <HardDriveSet>[]
      : HardDriveSet.discoverIn(_index, '$_root/HardDrives');

  String get _inventorySummary {
    final List<String> parts = <String>[
      for (final FileCategory category in <FileCategory>[
        FileCategory.roms,
        FileCategory.floppies,
        FileCategory.hardDrives,
        FileCategory.cdImages,
        FileCategory.whdloadGames,
      ])
        if (_index.countOf(category) > 0)
          '${_index.countOf(category)} ${category.displayName}',
    ];
    if (_hardDriveSetups.isNotEmpty) {
      parts.add('${_hardDriveSetups.length} complete hard-drive setup(s)');
    }
    return parts.isEmpty ? 'Nothing found in this folder' : parts.join(' · ');
  }

  @override
  void initState() {
    super.initState();
    _mediaChanges = MediaLibrary.changes.listen((MediaIndex index) {
      if (mounted) setState(() => _index = index);
    });
    _load();
  }

  @override
  void dispose() {
    _mediaChanges?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final String root = await MediaRoot.path();
    final MediaIndex index = await MediaLibrary.cached();
    final bool confirmFileDelete = await AppPrefs.confirmFileDelete();
    final String? source = await MediaFolder.displayPath();
    if (!mounted) return;
    setState(() {
      _root = root;
      _index = index;
      _confirmFileDelete = confirmFileDelete;
      _sourceFolder = source;
    });
  }

  /// Picks a source folder and brings in what it holds.
  ///
  /// Always opens the picker, including when a folder is already granted:
  /// correcting a wrong choice is the main reason anyone opens this row.
  Future<void> _chooseSourceFolder() async {
    final String? picked = await MediaFolder.pick();
    if (picked == null) return; // Backed out.
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await ImportProgressDialog.run<ImportResult>(
        context,
        title: 'Importing Amiga files',
        initialMessage: 'Scanning the selected folder and AGS collection…',
        operation: (ImportProgressUpdate update) =>
            MediaFolderImporter.importAll(
              onProgress: (int done, int total) =>
                  update('Copying recognised files…', done: done, total: total),
            ),
      );
      await MediaLibrary.scan();
    } on Exception {
      // The import reports its own failures to the log; the reload below
      // shows whatever did land rather than leaving a half-updated screen.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _setConfirmFileDelete(bool value) async {
    setState(() => _confirmFileDelete = value);
    await AppPrefs.setConfirmFileDelete(value: value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const SettingsHeader('Media'),
        Card(
          color: AmigaColors.card,
          child: Column(
            children: <Widget>[
              // On Android the row is about the folder the user PICKED, not
              // the app's internal destination. The destination cannot be
              // changed and showing its path invites the question of how.
              if (MediaFolder.isSupported)
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload),
                  title: Text(_sourceFolder ?? 'No folder chosen'),
                  subtitle: Text(
                    _sourceFolder == null
                        ? 'Choose the folder your Amiga files are in'
                        : _inventorySummary,
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : _chooseSourceFolder,
                    child: Text(_sourceFolder == null ? 'Choose' : 'Change'),
                  ),
                )
              else
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(_root.isEmpty ? '...' : _root),
                  subtitle: Text('Media folder - ${_index.files.length} files'),
                  trailing: MediaRoot.canChoose
                      ? TextButton(
                          onPressed: _busy ? null : _chooseRoot,
                          child: const Text('Change'),
                        )
                      : null,
                ),
              // One action instead of Scan-plus-Import: the wizard IS the
              // scan, the import, the Kickstart placement and the report,
              // and it already knows how to say what it found. Two buttons
              // that each did half of it were a maintenance quiz.
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Run setup again'),
                subtitle: const Text(
                  'Rescans everything - Kickstarts, games, music, zips '
                  'dropped in the folder - through the same walkthrough a '
                  'new install gets.',
                ),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await AppPrefs.setSetupComplete(value: false);
                          SetupFlow.request();
                        },
                  child: const Text('Run'),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Confirm before deleting files'),
                subtitle: const Text(
                  'Ask before permanently deleting local media from Files.',
                ),
                value: _confirmFileDelete,
                onChanged: _setConfirmFileDelete,
              ),
            ],
          ),
        ),

        if (_hardDriveSetups.isNotEmpty) ...<Widget>[
          const SettingsHeader('Detected hard-drive setups'),
          Card(
            color: AmigaColors.card,
            child: Column(
              children: <Widget>[
                for (final HardDriveSet setup in _hardDriveSetups)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      setup.looksLikeAgs ? Icons.grid_view : Icons.storage,
                    ),
                    title: Text(setup.name),
                    subtitle: Text(
                      '${setup.driveCount} drive(s) · boots '
                      '${setup.bootDrive.split(RegExp(r'[/\\]')).last}'
                      '${setup.looksLikeAgs ? ' · AGS/RTG' : ''}'
                      '${setup.looksLikeZebWhdload ? ' · Zeb WHDLoad' : ''}',
                    ),
                  ),
              ],
            ),
          ),
        ],

        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Future<void> _chooseRoot() async {
    final TextEditingController controller = TextEditingController(text: _root);
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

/// A section heading, shared by the setting panels.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key});

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
