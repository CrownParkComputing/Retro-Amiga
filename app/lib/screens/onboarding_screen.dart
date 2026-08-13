import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/amiga_model.dart';
import '../data/app_prefs.dart';
import '../data/file_category.dart';
import '../data/media_library.dart';
import '../data/media_root.dart';
import '../data/whdload_support.dart';
import '../widgets/amiga_logo.dart';

/// First-run setup.
///
/// This exists because the app is useless without a Kickstart ROM: nothing
/// boots, and a shelf with no way to add a working setup is just a dead end.
/// So setup finds the media first, and will not let you past until there is at
/// least one ROM to boot from.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  MediaIndex _index = const MediaIndex.empty();
  AmigaModel _model = AmigaModel.a500;
  bool _scanning = false;
  bool _scanned = false;
  String? _notice;

  /// A Kickstart is the one thing that cannot be worked around later.
  bool get _hasRom => _index.countOf(FileCategory.roms) > 0;

  String _root = '';
  bool _importing = false;
  ImportResult? _imported;

  /// Chooses where media lives, and files everything into it.
  ///
  /// The root is suggested from the scan rather than imposed: a device that
  /// has been running the old launcher already has a collection, and adopting
  /// that folder means the import moves nothing at all. Files outside it are
  /// moved rather than copied - within a volume that is a rename, so a 2GB
  /// collection is filed instantly instead of being duplicated on a handheld
  /// that may not have room for two copies.
  Future<void> _fileIntoRoot() async {
    setState(() => _importing = true);
    final ImportResult result = await MediaImporter.import(_index);
    // What moved is now somewhere else, so the index has to be rebuilt.
    final MediaIndex rescanned = await MediaLibrary.scan();
    if (!mounted) return;
    setState(() {
      _imported = result;
      _index = rescanned;
      _importing = false;
    });
  }

  Future<void> _chooseRoot() async {
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _RootDialog(initial: _root),
    );
    if (chosen == null || chosen.trim().isEmpty) return;
    await MediaRoot.setPath(chosen.trim());
    if (mounted) setState(() => _root = chosen.trim());
  }

  WhdloadStatus _whdload = const WhdloadStatus(
    bootArchiveInstalled: false,
    kickstartCount: 0,
  );
  bool _installingWhdload = false;
  String? _whdloadNotice;

  /// Puts the WHDLoad system files where the core's booter looks, and copies
  /// the Kickstarts it symlinks by name.
  ///
  /// Separate from the Kickstart step above because it answers a different
  /// question: that one is "can this app run anything", this one is "can it
  /// run the .lha files", and a device can easily have one and not the other.
  Future<void> _installWhdload() async {
    setState(() {
      _installingWhdload = true;
      _whdloadNotice = null;
    });

    final WhdloadStatus status = await WhdloadSupport.install(_index);

    if (!mounted) return;
    setState(() {
      _whdload = status;
      _installingWhdload = false;
      _whdloadNotice = status.bootArchiveInstalled
          ? null
          : 'No WHDLoad boot archive on this device. Copy boot-data.zip '
              '(or your whdload boot zip) onto it and scan again.';
    });
  }

  static const List<FileCategory> _shown = <FileCategory>[
    FileCategory.roms,
    FileCategory.floppies,
    FileCategory.hardDrives,
    FileCategory.cdImages,
    FileCategory.whdloadGames,
  ];

  String _artworkFor(FileCategory category) {
    switch (category) {
      case FileCategory.roms:
        return 'assets/machines/kickstart_check.png';
      case FileCategory.floppies:
        return 'assets/machines/floppy_inserted.png';
      case FileCategory.hardDrives:
        return 'assets/machines/drive_dh0.png';
      case FileCategory.cdImages:
        return 'assets/machines/cd32.png';
      case FileCategory.whdloadGames:
        return 'assets/machines/a1200.png';
      case FileCategory.archives:
      case FileCategory.music:
        return 'assets/machines/default.png';
    }
  }

  @override
  void initState() {
    super.initState();
    _scan();
    WhdloadSupport.status().then((WhdloadStatus status) {
      if (mounted) setState(() => _whdload = status);
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _notice = null;
    });

    if (!await MediaLibrary.hasScanPermission()) {
      await MediaLibrary.requestScanPermission();
      // Granting happens on a system screen, so we cannot know the answer
      // here: re-check rather than assume either way.
      if (!await MediaLibrary.hasScanPermission()) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _notice =
                'Storage access is off, so folders cannot be scanned. '
                'Grant it and scan again, or import files directly.';
          });
        }
        return;
      }
    }

    try {
      final MediaIndex index = await MediaLibrary.scan();

      // Adopt the folder the collection already lives in, unless the user has
      // chosen one. A device that has been running the old launcher keeps its
      // library where it is, and the import then has nothing to move.
      String root = await MediaRoot.path();
      final String? suggestion =
          MediaRoot.adoptsExistingCollection ? MediaRoot.suggestFrom(index) : null;
      if (suggestion != null && root == await MediaRoot.defaultPath()) {
        root = suggestion;
        await MediaRoot.setPath(root);
      }

      if (mounted) {
        setState(() {
          _index = index;
          _root = root;
          _scanning = false;
          _scanned = true;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _notice = 'Scan failed: $e';
        });
      }
    }
  }

  /// Copies chosen files into the app's own storage, then rescans.
  ///
  /// This is the way in on iOS, where there is no shared storage to walk, and
  /// a useful fallback on Android when storage access is refused.
  Future<void> _import() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() => _scanning = true);
      int copied = 0;
      for (final PlatformFile picked in result.files) {
        final String? path = picked.path;
        if (path == null) continue;
        // Filed by kind on the way in, so an imported disk lands with the
        // other disks rather than in a flat heap.
        final FileCategory? category = FileCategory.fromPath(path);
        if (category == null) continue;
        try {
          final Directory target = await MediaRoot.folderFor(category);
          File(path).copySync('${target.path}/${picked.name}');
          copied++;
        } on FileSystemException {
          // Skip the one file rather than abandoning the import.
        }
      }

      final MediaIndex index = await MediaLibrary.scan(
        roots: <String>[
          ...await MediaLibrary.defaultRoots(),
          await MediaRoot.path(),
        ],
      );
      if (mounted) {
        setState(() {
          _index = index;
          _scanning = false;
          _scanned = true;
          _notice = copied == 0
              ? 'Nothing imported: none of those files were Amiga media.'
              : null;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _notice = 'Import failed: $e';
        });
      }
    }
  }

  Future<void> _finish() async {
    await AppPrefs.setDefaultModel(_model);
    await AppPrefs.setSetupComplete(value: true);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: <Widget>[
            const SizedBox(height: 16),
            Image.asset(
              'assets/images/retro_recomp_logo.png',
              height: 56,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const AmigaLogo(height: 30),
                const SizedBox(width: 12),
                Text(
                  'Amiga-Retro',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 24),

            const _SectionHeader('1', 'Find your Amiga files'),
            const SizedBox(height: 8),
            const Text(
              'Kickstart ROMs, floppies, hard drives, CD images and WHDLoad '
              'archives. You supply your own.',
            ),
            const SizedBox(height: 12),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Scanning…'),
                  ],
                ),
              )
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.search),
                      label: Text(_scanned ? 'Scan again' : 'Scan for files'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Import files'),
                    ),
                  ),
                ],
              ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _notice!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),

            if (_scanned || !_index.isEmpty) ...<Widget>[
              _SectionHeader(
                _hasRom ? '✓' : '!',
                _index.isEmpty ? 'Nothing found' : 'What was found',
              ),
              const SizedBox(height: 8),
              ..._shown.map((FileCategory category) {
                final int count = _index.countOf(category);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 56,
                    height: 40,
                    child: Image.asset(
                      _artworkFor(category),
                      fit: BoxFit.contain,
                      errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                          const AmigaLogo(height: 20),
                    ),
                  ),
                  title: Text(category.displayName),
                  trailing: Text(
                    count == 0 ? 'none' : '$count',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }),
              if (!_hasRom)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No Kickstart ROM found. The Amiga cannot boot without '
                      'one, so setup needs at least one before you can go on. '
                      'Amiga Forever is the usual legitimate source.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],

            const _SectionHeader('2', 'Where media lives'),
            const SizedBox(height: 8),
            Text(
              MediaRoot.canChoose
                  ? 'Everything is filed here, in a folder per kind. It can be '
                      'anywhere you can write - a collection you already have '
                      'stays put, and survives this app being uninstalled.'
                  : 'iOS only lets the app read its own Documents folder, so '
                      'that is where media lives. It is reachable from the '
                      'Files app.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(_root.isEmpty ? 'Choosing...' : _root),
                    subtitle: const Text('Media folder'),
                    trailing: MediaRoot.canChoose
                        ? TextButton(
                            onPressed: _chooseRoot,
                            child: const Text('Change'),
                          )
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.drive_file_move_outlined),
                    title: Text(
                      _imported == null
                          ? 'File everything into it'
                          : '${_imported!.moved} moved, '
                              '${_imported!.alreadyInPlace} already in place'
                              '${_imported!.extracted > 0 ? ', ${_imported!.extracted} unzipped' : ''}'
                              '${_imported!.failed > 0 ? ', ${_imported!.failed} failed' : ''}',
                    ),
                    subtitle: const Text(
                      'Moves what is elsewhere into Floppies, HardDrives, '
                      'CDROMs, LHA and Kickstarts, and unpacks disk images '
                      'out of zips.',
                    ),
                    trailing: _importing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _scanning ? null : _fileIntoRoot,
                            child: const Text('Import'),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // WHDLoad setup is Android only. The boot archive has to be found
            // on the device, and iOS gives the app nothing to search: no
            // shared storage, and the sandbox holds only what has been handed
            // to it. Rather than show a step that can only ever say "not
            // found", iOS does not offer one.
            if (Platform.isAndroid) ...<Widget>[
            const _SectionHeader('3', 'WHDLoad support'),
            const SizedBox(height: 8),
            const Text(
              'WHDLoad games are .lha archives that need WHDLoad itself to '
              'boot. The core wants those files in one place, and a Kickstart '
              'under the name it expects.',
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  _whdload.ready ? Icons.check_circle : Icons.inventory_2_outlined,
                  color: _whdload.ready
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(
                  _whdload.ready
                      ? 'WHDLoad is ready'
                      : _whdload.bootArchiveInstalled
                          ? 'Boot files installed, no Kickstart yet'
                          : 'Not installed',
                ),
                subtitle: Text(
                  _whdloadNotice ??
                      (_whdload.ready
                          ? 'Boot archive installed, '
                              '${_whdload.kickstartCount} Kickstart'
                              '${_whdload.kickstartCount == 1 ? '' : 's'} in place.'
                          : 'Installs from a boot archive already on this '
                              'device.'),
                ),
                trailing: _installingWhdload
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _scanning ? null : _installWhdload,
                        child: Text(_whdload.ready ? 'Reinstall' : 'Install'),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            ],

            _SectionHeader(Platform.isAndroid ? '4' : '3', 'Pick your usual Amiga'),
            const SizedBox(height: 8),
            const Text('New setups start from this machine.'),
            const SizedBox(height: 12),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AmigaModel.values.length,
                separatorBuilder: (BuildContext c, int i) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int i) {
                  final AmigaModel model = AmigaModel.values[i];
                  final bool isSelected = model == _model;
                  return InkWell(
                    onTap: () => setState(() => _model = model),
                    child: Container(
                      width: 168,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              )
                            : null,
                      ),
                      child: Column(
                        children: <Widget>[
                          Expanded(
                            child: Image.asset(
                              model.artworkPath,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (BuildContext c, Object e, StackTrace? s) =>
                                      const AmigaLogo(height: 24),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            model.displayName,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _hasRom ? _finish : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _hasRom ? 'Finish setup' : 'Add a Kickstart ROM to continue',
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.number, this.title);

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary,
          ),
          child: Text(
            number,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}


/// Where media should live. A text field rather than a folder picker: the
/// picker Android offers returns a content:// tree the emulator core cannot
/// open, since the core takes plain paths.
class _RootDialog extends StatefulWidget {
  const _RootDialog({required this.initial});

  final String initial;

  @override
  State<_RootDialog> createState() => _RootDialogState();
}

class _RootDialogState extends State<_RootDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Media folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '/sdcard/Amiga',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Suggestions:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          for (final String path in const <String>[
            '/sdcard/Amiga',
            '/sdcard/UAE4Arm',
            '/sdcard/Roms/Amiga',
          ])
            TextButton(
              onPressed: () => _controller.text = path,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(path),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Use this'),
        ),
      ],
    );
  }
}
