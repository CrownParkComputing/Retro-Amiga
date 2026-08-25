import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/amiga_collections.dart';
import '../data/amiga_model.dart';
import '../data/app_prefs.dart';
import '../theme/amiga_theme.dart';
import '../data/compliance_demo.dart';
import '../data/aros_rom.dart';
import '../data/file_category.dart';
import '../data/host_paths.dart';
import '../data/hard_drive_set.dart';
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
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.verifyOnly = false,
  });

  final VoidCallback onFinished;

  /// Skip the choice and go straight to re-checking the folder already set.
  ///
  /// Used when a new build is installed. The question of compliance-or-my-own
  /// files has already been answered, and asking it again would suggest the
  /// answer had been lost; what is wanted is confirmation that the folder
  /// still reads and still holds what it did.
  final bool verifyOnly;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Where the walkthrough is up to.
///
/// The screen used to be one long page with the choice, the scan button and
/// Start all visible at once, so Start could be pressed before a folder had
/// been picked or a single file counted -- and on a new build it was never
/// shown at all. These are the three things that actually happen, in order.
enum _Phase {
  /// Compliance, or your own folder. Nothing else on screen.
  gate,

  /// Walking the folder, counting as it goes.
  scanning,

  /// What was found, and only now a Start button.
  results,

  /// The walkthrough: folders, WHDLoad, what AROS does. Reached from the
  /// results rather than sitting underneath them.
  details,
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  MediaIndex _index = const MediaIndex.empty();
  AmigaModel _model = AmigaModel.a500;
  bool _scanning = false;
  bool _scanned = false;

  late _Phase _phase = widget.verifyOnly ? _Phase.scanning : _Phase.gate;

  /// Which walkthrough page is showing. See _detailPages.
  int _detailsPage = 0;

  /// The running count and the folder being walked.
  ///
  /// A notifier rather than widget state: the walk reports per directory, and
  /// a setState each time would rebuild the whole screen a few hundred times
  /// over for one progress line.
  final ValueNotifier<({int found, String folder})> _progress =
      ValueNotifier<({int found, String folder})>((found: 0, folder: ''));

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

  /// Which known packs the scan recognised, and where. See AmigaCollection.
  Map<AmigaCollection, String> _collections = <AmigaCollection, String>{};

  List<HardDriveSet> get _hardDriveSetups => _root.isEmpty
      ? const <HardDriveSet>[]
      : HardDriveSet.discoverIn(_index, '$_root/HardDrives');

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
    // Nothing is scanned on the way in any more. The gate is the first thing
    // on screen, and a scan is what the user asks for by choosing a folder --
    // walking their storage while they are still reading the first sentence
    // was work done before anyone had said which folder to do it in.
    //
    // A new build is the exception: the folder is already known, and
    // re-checking it is the whole reason the wizard is being shown.
    // importMedia false: a re-check counts what is there, it does not open
    // the user's zips and file what is inside. That stays a deliberate act,
    // for the same reason it always was -- see _scan.
    if (widget.verifyOnly) unawaited(_scan(importMedia: false));
    WhdloadSupport.status().then((WhdloadStatus status) {
      if (mounted) setState(() => _whdload = status);
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// The gate's second door: pick a folder, or on a platform with no picker
  /// simply scan the one folder the app can read.
  Future<void> _chooseFolder() async {
    if (MediaFolder.isSupported) {
      await _importFolder();
    } else {
      await _scan();
    }
  }

  /// Android's one way in: the user grants a shared folder, which both the
  /// launcher and native core then read in place.
  Future<void> _importFolder() async {
    // Always ask, even when a folder is already granted: picking the wrong
    // one is easy, and a button that silently reuses the previous choice
    // leaves no way to correct it. The system picker opens where it left off,
    // so re-confirming the same folder is two taps.
    final String? picked = await MediaFolder.pick();
    if (picked == null) return; // Backed out: not an error.
    final String? shown = await MediaFolder.displayPath();
    if (!mounted) return;
    setState(() => _sourceFolder = shown);

    // The screen IS the progress now, so there is no dialog. A modal over a
    // wizard step that has nothing else on it was a second progress indicator
    // covering the first.
    setState(() {
      _scanning = true;
      _phase = _Phase.scanning;
      _notice = 'Reading the folder…';
    });
    _progress.value = (found: 0, folder: shown ?? '');
    try {
      final ImportResult result = await MediaFolderImporter.importAll(
        onProgress: (int done, int total) {
          _progress.value = (found: done, folder: 'Indexing $done of $total…');
        },
      );
      await _scan();
      if (!mounted) return;
      setState(
        () => _notice = result.failed > 0
            ? '${result.failed} files could not be read.'
            : 'Using this library in place. No media was copied.',
      );
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _notice = 'Import failed: $e';
          _phase = _Phase.results;
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// [importMedia] false files the Kickstart and nothing else. The
  /// automatic pass on entry uses it: opening the zips in the app's folder
  /// and filing what is inside is a decision the user makes by pressing
  /// Scan, not something a walkthrough does to their collection while they
  /// are still reading the first screen.
  Future<void> _scan({bool importMedia = true}) async {
    setState(() {
      _scanning = true;
      _notice = null;
      if (_phase == _Phase.gate) _phase = _Phase.scanning;
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
      //
      // On entry that is the Kickstart alone -- enough for the walkthrough to
      // report a ROM and for the machine to boot. Pressing Scan is what takes
      // the floppies and music out of their zips.
      await StartupImport.run(includeMedia: importMedia);
      final MediaIndex index = await MediaLibrary.scan(
        onProgress: (int found, String folder) {
          if (mounted) _progress.value = (found: found, folder: folder);
        },
      );

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

      // Do this after shared access and the real scan. main() also attempts it
      // early, but on a new Android install that happens before the one-time
      // storage grant and cannot possibly see Zeb's/other WHDLoad Kickstarts.
      // The support files and renamed ROM aliases live under the shared Amiga
      // root, never Android/data.
      await WhdloadSupport.installFromBundle();
      await WhdloadSupport.installKickstarts(index);
      final WhdloadStatus whdload = await WhdloadSupport.status();

      if (mounted) {
        setState(() {
          _index = index;
          _root = root;
          _whdload = whdload;
          _collections = AmigaCollection.findIn(index);
          _scanning = false;
          _scanned = true;
          _phase = _Phase.results;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          // Straight to the results, which will say what went wrong. Leaving
          // the user on a progress bar that has stopped moving is the one
          // outcome with no way forward.
          _phase = _Phase.results;
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
      if (MediaFolder.isSupported &&
          !await HostPaths.hasSharedStorageAccess() &&
          !await HostPaths.requestSharedStorageAccess()) {
        return;
      }
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_phase) {
          _Phase.gate => _gateView(),
          _Phase.scanning => _scanningView(),
          _Phase.results => _resultsView(),
          _Phase.details => _detailsView(),
        },
      ),
    );
  }

  /// One choice, and nothing under it to scroll past.
  Widget _gateView() {
    return ListView(
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

            // The choice, before the walkthrough rather than after it.
            //
            // Store Compliance used to sit at the bottom, past four sections
            // about finding files and choosing folders -- so the one route
            // that needs nothing from the user was the one they had to read
            // the most to find. A reviewer with no Kickstart and no Amiga to
            // take one from should not have to scroll through instructions
            // aimed at somebody else.
            //
            // The sections stay: they are the other route, and they are what
            // someone setting up their own machine came for.
            Card(
              color: AmigaColors.panel,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AmigaColors.panelBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Two ways in',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'JUST SHOW ME IT WORKING\n'
                      'The app ships AROS -- an open reimplementation of the '
                      'Amiga ROM -- and a demo disk of our own. Nothing is '
                      'needed from you: no Kickstart, no files, no network.',
                      style: TextStyle(color: AmigaColors.textDim, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busyCompliance ? null : _storeCompliance,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('Store Compliance'),
                      ),
                    ),
                    const Divider(height: 28, color: AmigaColors.panelBorder),
                    Text(
                      MediaFolder.isSupported
                          ? 'SET UP MY OWN AMIGA\n'
                                'Your Kickstart, your disks and your WHDLoad '
                                'games. Choose the folder they live in and it '
                                'is read in place -- nothing is copied or '
                                'moved. You see what was found before '
                                'anything starts.'
                          : 'SET UP MY OWN AMIGA\n'
                                'Your Kickstart, your disks and your WHDLoad '
                                'games. Drop them -- zipped is fine -- into '
                                'this app\'s folder in the Files app, then '
                                'scan. You see what was found before anything '
                                'starts.',
                      style: const TextStyle(
                        color: AmigaColors.textDim,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // No Start in this card. It used to sit here, above every
                    // step, so it could be pressed before a folder had been
                    // chosen or a single file counted. Start belongs after the
                    // totals, where it means "yes, that is my collection".
                    FilledButton(
                      onPressed: _scanning ? null : _chooseFolder,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          MediaFolder.isSupported
                              ? 'Choose my Amiga folder…'
                              : 'Scan my Amiga files',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// The walk, counting as it goes.
  Widget _scanningView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const AmigaLogo(height: 40),
            const SizedBox(height: 28),
            Text(
              widget.verifyOnly
                  ? 'Re-checking your Amiga folder'
                  : 'Reading your Amiga folder',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
            const SizedBox(height: 20),
            ValueListenableBuilder<({int found, String folder})>(
              valueListenable: _progress,
              builder:
                  (
                    BuildContext context,
                    ({int found, String folder}) value,
                    Widget? child,
                  ) {
                    return Column(
                      children: <Widget>[
                        Text(
                          '${value.found} files found',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          value.folder,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AmigaColors.textDim,
                          ),
                        ),
                      ],
                    );
                  },
            ),
          ],
        ),
      ),
    );
  }

  /// Everything the scan found, on one page.
  ///
  /// It used to be the whole walkthrough in one column: totals, then four
  /// sections about folders and WHDLoad and what AROS does, with Start at the
  /// foot of all of it. On a handheld that is a lot of scrolling to answer one
  /// question -- did it find my collection? -- so the answer is the page now,
  /// two columns of it, and the walkthrough moved to a page of its own behind
  /// a button.
  Widget _resultsView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _hasRom ? Icons.check_circle : Icons.error_outline,
                color: _hasRom ? const Color(0xFF00E28A) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _index.isEmpty
                      ? 'Nothing found in the selected folder'
                      : 'Found in ${_sourceFolder ?? _root}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _notice!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AmigaColors.textDim,
                ),
              ),
            ),
          const Divider(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Two columns wherever there is room for them, which on a
                // handheld in landscape there always is. A phone held upright
                // gets the same content stacked rather than squeezed.
                final bool wide = constraints.maxWidth >= 640;
                if (!wide) {
                  return ListView(
                    children: <Widget>[
                      ..._mediaTotals(),
                      const SizedBox(height: 12),
                      ..._collectionRows(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: ListView(children: _mediaTotals())),
                    const SizedBox(width: 24),
                    Expanded(child: ListView(children: _collectionRows())),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 20),
          if (!_hasRom)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No Kickstart was found, so nothing can boot yet. Setup '
                'details says where to put one.',
                style: TextStyle(color: AmigaColors.textDim, fontSize: 12),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: (_scanned && _hasRom && !_scanning)
                      ? _finish
                      : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Start'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _scanning ? null : _scan,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Scan again'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => setState(() {
                  _detailsPage = 0;
                  _phase = _Phase.details;
                }),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Setup details'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The left column: how much of each kind was found.
  List<Widget> _mediaTotals() {
    return <Widget>[
      Text('Media', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      ..._shown.map((FileCategory category) {
        final int count = _index.countOf(category);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: SizedBox(
            width: 40,
            height: 28,
            child: Image.asset(
              _artworkFor(category),
              fit: BoxFit.contain,
              errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                  const AmigaLogo(height: 16),
            ),
          ),
          title: Text(category.displayName),
          trailing: Text(
            count == 0 ? 'none' : '$count',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
      }),
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: const SizedBox(width: 40, child: Icon(Icons.music_note)),
        title: Text(FileCategory.music.displayName),
        trailing: Text(
          _index.countOf(FileCategory.music) == 0
              ? 'none'
              : '${_index.countOf(FileCategory.music)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: SizedBox(
          width: 40,
          child: Icon(
            _whdload.ready ? Icons.check_circle : Icons.info_outline,
            color: _whdload.ready ? const Color(0xFF00E28A) : null,
          ),
        ),
        title: const Text('WHDLoad support'),
        trailing: Text(
          _whdload.ready ? 'ready' : 'not ready',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ];
  }

  /// The right column: the packs by name, then any drive set that was found.
  List<Widget> _collectionRows() {
    return <Widget>[
      Text('Known collections', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      ...AmigaCollection.values.map((AmigaCollection collection) {
        final String? where = _collections[collection];
        final bool found = where != null;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            found ? Icons.check_circle : Icons.remove_circle_outline,
            size: 20,
            color: found ? const Color(0xFF00E28A) : AmigaColors.textDim,
          ),
          title: Text(collection.displayName),
          subtitle: Text(
            found ? where : collection.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: found ? null : AmigaColors.textDim,
            ),
          ),
          trailing: Text(
            found ? 'found' : 'not found',
            style: TextStyle(
              color: found ? null : AmigaColors.textDim,
              fontSize: 12,
            ),
          ),
        );
      }),
      if (_hardDriveSetups.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text('Drive sets', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final HardDriveSet setup in _hardDriveSetups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              setup.looksLikeAgs ? Icons.grid_view : Icons.storage,
              size: 20,
            ),
            title: Text(setup.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${setup.driveCount} drive(s)'
              '${setup.looksLikeAgs ? ' · AGS/RTG' : ''}'
              '${setup.looksLikeZebWhdload ? ' · Zeb WHDLoad' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    ];
  }

  /// The walkthrough, on its own page rather than under the answer.
  /// The walkthrough, as pages rather than one long scroll.
  ///
  /// It was four sections stacked in a single column under the results, so
  /// the answer to "did it find my collection" sat above several screens of
  /// reference material about folders and AROS. One subject per page, with a
  /// step count, so it can be read or skipped a page at a time.
  ///
  /// Which pages exist depends on the platform: iOS has no WHDLoad step
  /// because it has nowhere to search for the boot archive, and Android has
  /// no "where media lives" step because the answer is not the user's to
  /// change.
  List<({String title, List<Widget> body})> _detailPages() {
    return <({String title, List<Widget> body})>[
      if (!Platform.isAndroid)
        (
          title: 'Where media lives',
          body: <Widget>[
            // Android has no media-folder question to answer. The library lives
            // inside the app's own storage because that is the only place it can
            // write, and the folder the user picks in step 1 is the source. A
            // "where media lives" step could only show a path they cannot change.
            if (!Platform.isAndroid) ...<Widget>[
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
          ],
        ),
      if (Platform.isAndroid)
        (
          title: 'WHDLoad support',
          body: <Widget>[
            // WHDLoad setup is Android only. The boot archive has to be found
            // on the device, and iOS gives the app nothing to search: no
            // shared storage, and the sandbox holds only what has been handed
            // to it. Rather than show a step that can only ever say "not
            // found", iOS does not offer one.
            if (Platform.isAndroid) ...<Widget>[
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
          ],
        ),
      (
        title: 'It works already',
        body: <Widget>[

            // The point of this section is that the app demonstrates itself.
            // Everything above asks the user for files; this says they do not
            // need any of it to see an Amiga boot, and is honest about the
            // limits so nobody concludes the emulator is broken when a
            // WHDLoad title refuses to run on AROS.
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

        ],
      ),
      (
        title: 'Pick your usual Amiga',
        body: <Widget>[
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
        ],
      ),
    ];
  }

  Widget _detailsView() {
    final List<({String title, List<Widget> body})> pages = _detailPages();
    if (pages.isEmpty) return _resultsView();
    final int at = _detailsPage.clamp(0, pages.length - 1);
    final ({String title, List<Widget> body}) page = pages[at];
    final bool last = at == pages.length - 1;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Back to what was found',
                onPressed: () => setState(() => _phase = _Phase.results),
              ),
              Expanded(
                child: Text(
                  page.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'Step ${at + 1} of ${pages.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AmigaColors.textDim,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 20),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: page.body,
          ),
        ),
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: at == 0
                    ? () => setState(() => _phase = _Phase.results)
                    : () => setState(() => _detailsPage = at - 1),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: last
                      ? () => setState(() => _phase = _Phase.results)
                      : () => setState(() => _detailsPage = at + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(last ? 'Done' : 'Next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
