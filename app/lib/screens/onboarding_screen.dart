import 'dart:io';

import 'package:flutter/material.dart';

import '../data/amiga_model.dart';
import '../data/app_prefs.dart';
import '../data/compliance_demo.dart';
import '../data/aros_rom.dart';
import '../data/file_category.dart';
import '../data/media_folder.dart';
import '../data/media_library.dart';
import '../data/media_root.dart';
import '../data/startup_import.dart';
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
  /// The folder the user picked, shown so a wrong choice is visible.
  String? _sourceFolder;
  String? _notice;

  /// A Kickstart is the one thing that cannot be worked around later --
  /// except that it now can, because the bundled AROS ROM is itself a
  /// Kickstart the scan will count. So this stays "can the machine boot",
  /// and [_hasRealKickstart] answers the different question of whether
  /// commercial software has a fair chance of running.
  bool get _hasRom => _index.countOf(FileCategory.roms) > 0;

  /// Kickstarts the user supplied, as opposed to the AROS pair the app
  /// installs on every launch. Counted by NAME rather than remembered in a
  /// flag, because a user who drops kick31.rom in later never comes back
  /// through here to have a flag updated.
  bool get _hasRealKickstart => _index
      .of(FileCategory.roms)
      .any((MediaFile f) => !ArosRom.fileNames.contains(f.name.toLowerCase()));

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

  /// Android's one way in: the user hands over a folder, and what it holds is
  /// copied into the app's own media folder.
  ///
  /// There is no scan option on Android any more. Scoped storage will not let
  /// this app walk shared storage, so a "scan for files" button could only
  /// ever search the app's own folder - which the user has no easy way to put
  /// anything into. Offering it was offering a button that finds nothing.
  Future<void> _importFolder() async {
    // Always ask, even when a folder is already granted: picking the wrong
    // one is easy, and a button that silently reuses the previous choice
    // leaves no way to correct it. The system picker opens where it left off,
    // so re-confirming the same folder is two taps.
    final String? picked = await MediaFolder.pick();
    if (picked == null) return; // Backed out: not an error.
    final String? shown = await MediaFolder.displayPath();
    if (mounted) setState(() => _sourceFolder = shown);

    setState(() {
      _scanning = true;
      _notice = 'Reading the folder…';
    });
    try {
      final ImportResult result = await MediaFolderImporter.importAll(
        onProgress: (int done, int total) {
          if (mounted && total > 0) {
            setState(() => _notice = 'Copying $done of $total…');
          }
        },
      );
      if (!mounted) return;
      setState(
        () => _notice = result.total == 0
            ? 'Nothing the app recognises in that folder.'
            : '${result.moved} copied, ${result.alreadyInPlace} already here'
                  '${result.failed > 0 ? ', ${result.failed} failed' : ''}.',
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = 'Import failed: $e');
      return;
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    // Index what was just copied, so the sections below fill in.
    await _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _notice = null;
    });

    // No permission gate: the library root is the app's own folder, which
    // every Android lets it read. A collection sitting somewhere else - the
    // /sdcard/Amiga a previous install filled while it still held all-files
    // access - is brought in through the folder picker on the media screens.

    try {
      // File first, then scan: a first run's media arrives as zips dropped in
      // the app's folder, and a scan that only lists them shows "none" for
      // every category with the Kickstarts sitting right there. The launch
      // import is skipped during onboarding precisely so this can run it at
      // the right moment instead.
      await StartupImport.run();
      final MediaIndex index = await MediaLibrary.scan();

      // Adopt the folder the collection already lives in, unless the user has
      // chosen one. A device that has been running the old launcher keeps its
      // library where it is, and the import then has nothing to move.
      String root = await MediaRoot.path();
      final String? suggestion = MediaRoot.adoptsExistingCollection
          ? MediaRoot.suggestFrom(index)
          : null;
      if (suggestion != null && root == await MediaRoot.defaultPath()) {
        root = suggestion;
        await MediaRoot.setPath(root);
      }

      // Any Kickstarts the scan found belong in the booter's own folder. Doing
      // it here means the setup screen's idea of "ready" matches what a game
      // will find when it starts.
      await WhdloadSupport.installKickstarts(index);

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

  bool _busyCompliance = false;

  /// Switches the app to the bundled AROS ROM and its demo disk, then
  /// finishes setup.
  ///
  /// Nothing is started for the user: the demo is a disk they open from
  /// Games like any other, which is also the only version of this that shows
  /// them how to open anything else.
  Future<void> _storeCompliance() async {
    setState(() => _busyCompliance = true);
    try {
      await ComplianceDemo.prepare();
      await AppPrefs.setComplianceMode(value: true);
      await AppPrefs.setDefaultModel(_model);
      await AppPrefs.setSetupComplete(value: true);
      await AppPrefs.rememberBuild();
      if (!mounted) return;
      widget.onFinished();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not switch to the bundled ROM: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyCompliance = false);
    }
  }

  Future<void> _finish() async {
    // Start means "my own Kickstart and my own files", so it also leaves
    // compliance mode. The flag surviving would boot the bundled ROM again
    // on the next machine, having just been asked for the opposite.
    if (await AppPrefs.complianceMode()) {
      await AppPrefs.setComplianceMode(value: false);
    }
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
                  'Retro-Amiga',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 24),

            const _SectionHeader('1', 'Find your Amiga files'),
            const SizedBox(height: 8),
            Text(
              MediaFolder.isSupported
                  ? 'Kickstart ROMs, floppies, hard drives, CD images and '
                        'WHDLoad archives. You supply your own: choose the '
                        'folder they live in - /sdcard/Amiga, a Downloads '
                        'folder, wherever - and the app copies what it '
                        'recognises into its own library.'
                  : 'Kickstart ROMs, floppies, hard drives, CD images and '
                        'WHDLoad archives. You supply your own: drop them - '
                        'zipped is fine - into this app\'s folder in the '
                        'Files app (On My iPad > Retro-Amiga), then Scan.',
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
              // One button. The app's folder is the only door - the scan
              // files whatever zips are waiting there and reports what it
              // found, exactly as C64-Retro does. A Files picker here was a
              // second road in, one that filed things by the picker's rules
              // instead of the importer's.
              MediaFolder.isSupported
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _importFolder,
                          icon: const Icon(Icons.drive_folder_upload),
                          label: Text(
                            _sourceFolder == null
                                ? 'Choose your Amiga folder'
                                : 'Choose a different folder',
                          ),
                        ),
                        if (_sourceFolder != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Reading from $_sourceFolder',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    )
                  : OutlinedButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.search),
                      label: Text(_scanned ? 'Scan again' : 'Scan for files'),
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
              // No error card for "no Kickstart" any more: the app installs
              // the AROS pair on every launch, so there is always one, and a
              // red panel saying otherwise would be untrue. The AROS section
              // below covers what that does and does not get you.
              if (!_hasRom)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No Kickstart ROM found, and the built-in AROS ROM did '
                      'not install either -- which should not happen. Check '
                      'the Logs panel, or add a Kickstart of your own.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // Android has no media-folder question to answer. The library lives
            // inside the app's own storage because that is the only place it can
            // write, and the folder the user picks in step 1 is the source. A
            // "where media lives" step could only show a path they cannot change.
            if (!Platform.isAndroid) ...<Widget>[
              const _SectionHeader('2', 'Where media lives'),
              const SizedBox(height: 8),
              Text(
                MediaRoot.canChoose
                    ? 'Everything is filed here, in a folder per kind. It can be '
                          'anywhere you can write - a collection you already have '
                          'stays put, and survives this app being uninstalled.'
                    : Platform.isAndroid
                    ? 'Filed automatically, in a folder per kind, inside the '
                          'app\'s own storage - the only place Android lets it '
                          'write without asking for a permission the Play Store '
                          'will not grant. Your own folder is left untouched.'
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

            ],
            // WHDLoad setup is Android only. The boot archive has to be found
            // on the device, and iOS gives the app nothing to search: no
            // shared storage, and the sandbox holds only what has been handed
            // to it. Rather than show a step that can only ever say "not
            // found", iOS does not offer one.
            if (Platform.isAndroid) ...<Widget>[
              const _SectionHeader('2', 'WHDLoad support'),
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
                    _whdload.ready
                        ? Icons.check_circle
                        : Icons.inventory_2_outlined,
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

            // The point of this section is that the app demonstrates itself.
            // Everything above asks the user for files; this says they do not
            // need any of it to see an Amiga boot, and is honest about the
            // limits so nobody concludes the emulator is broken when a
            // WHDLoad title refuses to run on AROS.
            _SectionHeader(_hasRealKickstart ? '✓' : 'i', 'It works already'),
            const SizedBox(height: 8),
            Text(
              _hasRealKickstart
                  ? 'You have your own Kickstart, so the app will use it -- '
                        'it is preferred over the built-in one whenever it is '
                        'present, and gives the best compatibility.'
                  : 'No Kickstart of your own? The app ships AROS, an open '
                        'reimplementation of the Amiga ROM, and has already '
                        'installed it. Finish setup and the machine boots to '
                        'a Workbench desktop with nothing else supplied.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: Icon(
                      _hasRealKickstart
                          ? Icons.check_circle
                          : Icons.memory_outlined,
                      color: _hasRealKickstart
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      _hasRealKickstart
                          ? 'Your Kickstart is in use'
                          : 'Running on AROS',
                    ),
                    subtitle: Text(
                      _hasRealKickstart
                          ? 'AROS stays installed as a fallback. Nothing to do.'
                          : 'AROS is not a Kickstart clone. Workbench, the '
                                'shell and plenty of ADFs run; many WHDLoad '
                                'titles and some games need the real thing.',
                    ),
                  ),
                  if (!_hasRealKickstart)
                    const ListTile(
                      leading: Icon(Icons.add_circle_outline),
                      title: Text('To use a real Kickstart'),
                      subtitle: Text(
                        'Put kick13.rom / kick31.rom (Amiga Forever is the '
                        'usual legitimate source) with your other files and '
                        'scan again. It is picked up automatically and used '
                        'in preference to AROS -- no setting to change.',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _SectionHeader(
              Platform.isAndroid ? '5' : '4',
              'Pick your usual Amiga',
            ),
            const SizedBox(height: 8),
            const Text('New setups start from this machine.'),
            const SizedBox(height: 12),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AmigaModel.values.length,
                separatorBuilder: (BuildContext c, int i) =>
                    const SizedBox(width: 12),
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
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Start'),
              ),
            ),
            const SizedBox(height: 12),
            // The route that needs nothing from the user at all. Named for
            // what it is for rather than what it does mechanically, because
            // it is what a store reviewer is pointed at and has to be
            // recognisable on a screen they have never seen.
            OutlinedButton(
              onPressed: _busyCompliance ? null : _storeCompliance,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Store Compliance'),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

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
              child: Align(alignment: Alignment.centerLeft, child: Text(path)),
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
