import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/amiga_collections.dart';
import '../data/amiga_model.dart';
import '../data/app_prefs.dart';
import '../theme/amiga_theme.dart';
import 'getting_started.dart';
import '../data/compliance_demo.dart';
import '../data/aros_rom.dart';
import '../data/file_category.dart';
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
  /// Hello. The logo, one sentence, one button.
  ///
  /// A first run used to open on "Two ways in" -- a choice, before anything
  /// had said what the app was or what it was about to ask for. Someone who
  /// has never run an emulator has no basis for answering it. So the app
  /// introduces itself first, explains what an Amiga needs and where this
  /// platform lets files live, and only then asks.
  welcome,

  /// The two teaching pages, on the main path rather than behind a button.
  primer,

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

  late _Phase _phase = widget.verifyOnly ? _Phase.scanning : _Phase.welcome;

  /// The running count and the folder being walked.
  ///
  /// A notifier rather than widget state: the walk reports per directory, and
  /// a setState each time would rebuild the whole screen a few hundred times
  /// over for one progress line.
  final ValueNotifier<({int found, String folder})> _progress =
      ValueNotifier<({int found, String folder})>((found: 0, folder: ''));

  /// What the scan is doing right now.
  ///
  /// The count alone was not enough to look like anything was happening: the
  /// folder listing is a single call into the platform that returns
  /// everything at once, so on a large card the number sat at zero for the
  /// part of the scan that takes the longest. Naming the stage is what makes
  /// the wait legible.
  final ValueNotifier<String> _stage = ValueNotifier<String>('');

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
    _stage.dispose();
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

  /// Android's one way in: the user hands over a folder through the system
  /// picker, and what it holds is copied into the app's own media folder.
  /// Scoped storage will not let this app walk shared storage in place, and
  /// the permission that would - all-files access - is one Play gates behind
  /// a review this app does not ask for.
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
      _scanned = false;
      _index = const MediaIndex.empty();
      _phase = _Phase.scanning;
      _notice = 'Reading the folder…';
    });
    _progress.value = (found: 0, folder: shown ?? '');
    try {
      final ImportResult result = await MediaFolderImporter.importAll(
        onProgress: (int done, int total) {
          _stage.value = 'Copying your collection…';
          _progress.value = (found: done, folder: 'Copying $done of $total…');
        },
      );
      await _scan();
      if (!mounted) return;
      setState(
        () => _notice = result.usedInPlace
            ? 'Using the collection where it is. Nothing was copied.'
            : result.total == 0
            ? 'Nothing the app recognises in that folder.'
            : '${result.moved} copied, ${result.alreadyInPlace} already here'
                  '${result.failed > 0 ? ', ${result.failed} failed' : ''}.',
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
    // Index what was just copied, so the sections below fill in.
    await _scan();
  }

  /// [importMedia] false files the Kickstart and nothing else. The
  /// automatic pass on entry uses it: opening the zips in the app's folder
  /// and filing what is inside is a decision the user makes by pressing
  /// Scan, not something a walkthrough does to their collection while they
  /// are still reading the first screen.
  Future<void> _scan({bool importMedia = true}) async {
    // Always the scanning page, wherever the scan was asked for.
    //
    // "Scan again" used to leave the user on the results page with a hairline
    // progress bar over numbers that were about to change, which reads as
    // nothing happening at all. A scan is a thing the user asked for and
    // waits on; it gets a screen.
    setState(() {
      _scanning = true;
      _notice = null;
      _phase = _Phase.scanning;
    });
    _progress.value = (found: 0, folder: '');
    _stage.value = 'Looking for your Amiga folder…';
    // A fast scan is still a scan, and one that flashes past leaves the user
    // unsure it ran. Not padding for its own sake: the screen it would
    // otherwise flicker through is the only place the folder being read is
    // named.
    final Stopwatch elapsed = Stopwatch()..start();

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
      _stage.value = 'Reading the folder listing…';
      await StartupImport.run(includeMedia: importMedia);
      final MediaIndex index = await MediaLibrary.scan(
        onProgress: (int found, String folder) {
          if (!mounted) return;
          _progress.value = (found: found, folder: folder);
          _stage.value = 'Indexing what is in the folder…';
        },
      );

      // The granted folder is shown as the SOURCE, but it is never adopted
      // as the media root. It used to be, back when all-files access let the
      // core read it in place; without that permission the shared folder is
      // read-only at best, and a root that cannot be written means every
      // import fails and Compliance/ cannot even be created - the
      // "FileSystemException: Creation failed" on an external card. The
      // library lives in the app's own folder; the grant only feeds copies
      // into it.
      final String? grantedFolder = await MediaFolder.displayPath();
      if (grantedFolder != null && grantedFolder.isNotEmpty && mounted) {
        setState(() => _sourceFolder = grantedFolder);
      }

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
      _stage.value = 'Checking Kickstarts and WHDLoad support…';
      await WhdloadSupport.installFromBundle();
      await WhdloadSupport.installKickstarts(index);
      final WhdloadStatus whdload = await WhdloadSupport.status();

      const Duration visible = Duration(milliseconds: 700);
      if (elapsed.elapsed < visible) {
        await Future<void>.delayed(visible - elapsed.elapsed);
      }

      if (mounted) {
        setState(() {
          _index = index;
          _root = root;
          _whdload = whdload;
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
          _Phase.welcome => _welcomeView(),
          _Phase.primer => _primerView(),
          _Phase.gate => _gateView(),
          _Phase.scanning => _scanningView(),
          _Phase.results => _resultsView(),
          _Phase.details => _detailsView(),
        },
      ),
    );
  }

  /// Hello: the logo, one sentence, one button.
  ///
  /// Deliberately almost empty. It is the first thing a new install shows and
  /// its whole job is to say what this is and give one obvious way forward --
  /// not to ask anything, because at this point the reader has no basis for
  /// answering. The way out for someone who has done this before is there,
  /// quietly, underneath.
  Widget _welcomeView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The app's own icon, which is what the user tapped to get
            // here. A generic Amiga tick on the first screen of a first run
            // does not confirm they opened the thing they meant to.
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  height: 104,
                  width: 104,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder:
                      (BuildContext c, Object e, StackTrace? s) =>
                          const AmigaLogo(height: 72),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Retro-Amiga',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'An Amiga, running on this device. Setup takes a couple of '
              'minutes, and you do not need any files of your own to start.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AmigaColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => setState(() => _phase = _Phase.primer),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Get started'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _phase = _Phase.gate),
              child: const Text('I have done this before'),
            ),
          ],
        ),
      ),
    );
  }

  /// The two pages that teach, before the first question.
  ///
  /// What an Amiga needs, and where this platform lets files live. Both used
  /// to be optional reading behind a button on the results page -- which is
  /// after the folder has been chosen, so the page explaining how to choose a
  /// folder could only be found by someone who had already managed it.
  Widget _primerView() {
    return GettingStartedGuide(
      steps: <GuideStep>[
        GettingStartedSteps.whatYouNeed(),
        GettingStartedSteps.whereFilesGo(),
      ],
      closeLabel: 'Choose how to start',
      onClose: () => setState(() => _phase = _Phase.gate),
      onBack: () => setState(() => _phase = _Phase.welcome),
    );
  }

  /// One choice, and nothing under it to scroll past.
  Widget _gateView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: <Widget>[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    height: 44,
                    width: 44,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder:
                        (BuildContext c, Object e, StackTrace? s) =>
                            const AmigaLogo(height: 30),
                  ),
                ),
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
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: _stage,
              builder: (BuildContext context, String stage, Widget? child) =>
                  Text(
                    stage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AmigaColors.textDim),
                  ),
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
    // Arriving here means "show me what is there", so if nothing has been
    // counted yet, count it now rather than presenting a page of zeroes and
    // waiting to be asked. Posted after the frame because it is a setState
    // and this is a build.
    if (!_scanned && !_scanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_scanned && !_scanning) {
          unawaited(_scan(importMedia: false));
        }
      });
    }
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
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
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
              // The way back to the picker. Without it the folder chosen at
              // the gate was final: a wrong choice, or a card that was not in
              // the device at the time, could only be corrected by clearing
              // the app's data. It is also what the new-build re-check needs,
              // where the whole point is to confirm the folder or change it.
              if (MediaFolder.isSupported) ...<Widget>[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _scanning ? null : _chooseFolder,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Choose folder…'),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => setState(() => _phase = _Phase.details),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  // Named for what a first-timer is looking for. "Setup
                  // details" reads as small print you can skip, which is
                  // exactly what the people who most needed it did.
                  child: Text('How do I…?'),
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

  /// The right column: what was actually found, named.
  ///
  /// This used to be two lists. "Known collections" ticked off all four packs,
  /// found or not; "Drive sets" listed the folders the scan had found, tagged
  /// AGS or Zeb. They were the same information written twice -- and the pair
  /// disagreed the moment one recognised something the other did not, which
  /// is worse than either alone.
  ///
  /// One list now, of the setups that are really there, each named for what
  /// it is and what it will be configured as. Nothing found says so in one
  /// line, which is the answer that was worth keeping from the old list: it
  /// is the difference between "the app cannot see my card" and "the app can
  /// see my card and the pack is not on it".
  List<Widget> _collectionRows() {
    return <Widget>[
      Text('What was found', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      if (_hardDriveSetups.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            _index.countOf(FileCategory.hardDrives) > 0
                ? 'Hard-drive images, but no complete setup. Keep each pack in '
                      'its own folder under HardDrives.'
                : 'No hard-drive setups. Put AGS, AmigaVision, PiMiga or a '
                      'WHDLoad pack in its own folder under HardDrives and '
                      'scan again.',
            style: const TextStyle(fontSize: 11, color: AmigaColors.textDim),
          ),
        ),
      for (final HardDriveSet setup in _hardDriveSetups)
        _foundRow(setup),
    ];
  }

  Widget _foundRow(HardDriveSet setup) {
    final AmigaCollection? known = AmigaCollection.detect(setup);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        setup.directoryMount
            ? Icons.folder_open
            : known == null
            ? Icons.storage
            : Icons.check_circle,
        size: 20,
        color: known == null ? null : const Color(0xFF00E28A),
      ),
      title: Text(
        known?.displayName ?? setup.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        known != null
            ? '${setup.name} · ${known.machineBlurb}'
            : setup.directoryMount
            ? 'Folder mounted as a drive'
            : '${setup.driveCount} drive(s)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    );
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
  List<GuideStep> _detailPages() {
    return <GuideStep>[
      // The three that explain the machine, the platform's file rules and
      // how to actually start a game. They come first because they are what
      // someone who has never run an emulator needs, and they used to be
      // missing entirely -- the guide opened on a folder path.
      GettingStartedSteps.whatYouNeed(hasRealKickstart: _hasRealKickstart),
      GettingStartedSteps.whereFilesGo(),
      if (!Platform.isAndroid)
        GuideStep(
          title: 'Where media lives',
          icon: Icons.folder_outlined,
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
        GuideStep(
          title: 'WHDLoad support',
          icon: Icons.inventory_2_outlined,
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
      GuideStep(
        title: 'It works already',
        icon: Icons.check_circle_outline,
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
      GuideStep(
        title: 'Pick your usual Amiga',
        icon: Icons.computer,
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
      GettingStartedSteps.firstGame(),
    ];
  }

  Widget _detailsView() {
    final List<GuideStep> pages = _detailPages();
    if (pages.isEmpty) return _resultsView();
    return GettingStartedGuide(
      steps: pages,
      closeLabel: 'Back to what was found',
      onClose: () => setState(() => _phase = _Phase.results),
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
