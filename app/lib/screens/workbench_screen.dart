import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/boing_backdrop.dart';
import '../widgets/sidebar_style.dart';
import '../widgets/workbench_sidebar.dart';
import '../data/amiga_system.dart';
import 'emulator_screen.dart';
import '../data/app_log.dart';
import '../data/app_prefs.dart';
import '../data/file_category.dart';
import '../data/config_store.dart';
import '../data/game_controller.dart';
import '../data/media_library.dart';
import '../data/music_picks.dart';
import '../data/music_player.dart';
import '../data/save_states.dart';
import '../data/session.dart';
import '../ffi/amiga_core.dart';
import '../emulator.dart';
import '../widgets/sidebar.dart';
import 'about_panel.dart';
import 'compliance_panel.dart';
import 'av_panel.dart';
import 'configurations_screen.dart';
import 'history_screen.dart';
import 'input_panel.dart';
import 'library_panel.dart';
import 'music_panel.dart';
import 'resume_panel.dart';
import 'settings_panel.dart';

/// The home screen: a nav rail and one content panel, floating over the boing
/// ball.
///
/// Left untouched for [_idleDelay] the panels fade back and the backdrop comes
/// forward, so an idle handheld shows the demo rather than a menu. Any touch
/// anywhere brings the workbench straight back - the Listener sits above
/// everything and only observes, so the tap that wakes it still reaches
/// whatever was under it.
class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key, this.onRerunSetup});

  /// Reopens the walkthrough. Owned by main(), which holds the setup flag.
  final VoidCallback? onRerunSetup;

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  static const Duration _idleDelay = Duration(seconds: 30);

  WorkbenchSection _section = WorkbenchSection.setups;
  bool _idle = false;


  /// What the scan found and how many configs there are, for the scroller.
  MediaIndex _index = const MediaIndex.empty();
  int _configCount = 0;

  /// The systems on this device — AGS, AmigaVision, PiMiga, a WHDLoad pack, a
  /// folder of Amiga files — each with a config already written for it.
  ///
  /// They sit on the rail as entries of their own. Before this, getting into
  /// one meant the full wizard: choose a mode, pick the folder, answer
  /// questions about a machine you have no basis for answering, save, then
  /// find it in a list — when every one of those answers was knowable from
  /// the folder the moment it was scanned.
  List<AmigaSystem> _systems = const <AmigaSystem>[];

  Timer? _idleTimer;
  StreamSubscription<MediaIndex>? _mediaChanges;

  /// Resume is only offered when a game was left running - see Session. It is
  /// re-checked whenever the workbench comes back to the front, which is what
  /// happens after quitting a game.
  bool _hasSession = false;


  /// Redraws for the Fill toggle, and does nothing else.
  ///
  /// This used to be wired straight to [_onPlayingChanged], which is a
  /// different event entirely, and the consequences were the two worst
  /// reports on the last release. Toggling Fill mid-game ran the whole
  /// start-of-session path again: it reset the mouse mode, dropped the
  /// keyboard, brought the chrome back -- the "it switches between the large
  /// screen and the settings view on its own" complaint -- and then called
  /// _startSession a second time, which re-registers the pad with a core that
  /// is already running. That last part is the exact re-entry into the input
  /// device table that _padTarget exists to prevent, and it aborts out of
  /// Scudo, so it is a strong candidate for the crashes too.
  ///
  /// A remembered preference changing is a repaint. Nothing more.
  void _onScreenFillChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the panel the in-game rail asked for, if it asked for one.
  ///
  /// The overlay engine cannot reach the launcher's engine, so the request
  /// crosses as a file the Activity writes on the way out (see
  /// HostSupport.writeSectionRequest). It is consumed here: a stale request
  /// would hijack the next launch too.
  void _onPlayingChanged() {
    if (!mounted) return;
    if (Emulator.playing.value) {
      unawaited(_openEmulator());
      return;
    }
    // Give the buttons back to the launcher: a handheld navigates its own
    // menus with the same stick it just played with. EmulatorScreen does this
    // too when it is disposed; doing it here as well covers a session that
    // ended without the screen being popped.
    unawaited(GameController.setGameRunning(false));
  }

  /// True while the emulator's screen is on top, so a second launch does not
  /// stack a second one over it.
  bool _emulatorOpen = false;

  /// Hands the session its own screen.
  ///
  /// Every launch path -- Collections, Games, Resume, the wizard, the library
  /// -- ends up setting Emulator.playing, so this is the one place that has
  /// to know, rather than six.
  Future<void> _openEmulator() async {
    if (_emulatorOpen) return;
    final AmigaCore? core = Emulator.inProcessCore;
    if (core == null) return;
    _emulatorOpen = true;
    AppLog.info('session', 'opening the emulator screen');
    try {
      final EmulatorExit? how = await Navigator.of(context).push<EmulatorExit>(
        MaterialPageRoute<EmulatorExit>(
          fullscreenDialog: true,
          builder: (BuildContext context) =>
              EmulatorScreen(core: core, title: Emulator.playingTitle),
        ),
      );
      if (!mounted) return;
      await _refreshSession();
      if (!mounted) return;
      setState(() {
        // Pausing means coming back to it, so land on the shelf that offers
        // it. Closing means done, so land where the games are.
        _section = how == EmulatorExit.paused
            ? WorkbenchSection.resume
            : WorkbenchSection.collections;
      });
    } finally {
      _emulatorOpen = false;
      AppLog.info('session', 'emulator screen closed');
    }
  }



  /// Held rather than rebuilt: see the note where it is used.
  CompliancePanel? _compliancePanel;

  Future<void> _adoptRequestedSection() async {
    try {
      final File request = File(
        '\${await HostPaths.appSupport()}/workbench_section',
      );
      if (!request.existsSync()) return;
      final String name = request.readAsStringSync().trim();
      request.deleteSync();
      for (final WorkbenchSection s in WorkbenchSection.values) {
        if (s.title == name && mounted) {
          setState(() => _section = s);
          return;
        }
      }
    } catch (_) {
      // Landing where the launcher last was is a fine outcome.
    }
  }

  List<WorkbenchSection> get _sections => WorkbenchSection.values
      .where(
        (WorkbenchSection s) => s != WorkbenchSection.resume || _hasSession,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _adoptRequestedSection();
    AppPrefs.loadScreenFill();
    // Read once at startup so the emulator screen and the A/V page agree
    // from the first frame rather than after the first change.
    AppPrefs.loadShowPad();
    AppPrefs.loadShowKeyboard();
    AppPrefs.screenFill.addListener(_onScreenFillChanged);
    // The panel swaps to the machine when a session starts, and back when it
    // ends, without anything else having to know.
    Emulator.playing.addListener(_onPlayingChanged);
    _restartIdleTimer();
    _refreshSession();
    _startMusic();
    _mediaChanges = MediaLibrary.changes.listen((MediaIndex index) {
      if (mounted) setState(() => _index = index);
      // A rescan can turn up a system that was not there before -- a card
      // swapped in, a pack finished copying -- so the rail is rebuilt with
      // the library rather than only at startup.
      unawaited(_configureSystems());
    });
    unawaited(_configureSystems());
    WidgetsBinding.instance.addObserver(_watch);
    GameController.onAudioFocusChanged = (AudioFocus focus) {
      switch (focus) {
        case AudioFocus.gain:
          Emulator.resumeIfSuspended();
        case AudioFocus.loss:
          Emulator.suspend();
        case AudioFocus.duck:
          // Deliberately nothing. The system is lowering our volume for a
          // notification, not asking the machine to stop, and stopping it
          // here froze the game every time a message arrived.
          break;
      }
    };
    unawaited(GameController.start());
  }

  // Session state only. Suspending and resuming the music belongs to the app
  // root, which is underneath every screen - this one used to own it, so
  // leaving from the music screen left the tune playing.
  late final _LifecycleWatch _watch = _LifecycleWatch(
    onResumed: _refreshSession,
    onPaused: () {},
  );

  @override
  void dispose() {
    Emulator.playing.removeListener(_onPlayingChanged);
    AppPrefs.screenFill.removeListener(_onScreenFillChanged);
    WidgetsBinding.instance.removeObserver(_watch);
    GameController.onDirection = null;
    GameController.onButton = null;
    GameController.onAudioFocusChanged = null;
    unawaited(GameController.setGameRunning(false));
    _mediaChanges?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Puts a tune on while the workbench is up, and takes the count of what is
  /// on the device for the scroller while the index is in hand.
  Future<void> _startMusic() async {
    await MusicPlayer.setVolume(await AppPrefs.musicVolume());
    MediaIndex index = await MediaLibrary.cached();
    if (index.files.isEmpty) index = await MediaLibrary.scan();
    final List<String> tunes = index.files
        .where(
          (MediaFile f) =>
              f.category == FileCategory.music &&
              MusicPicks.all.any((MusicPick p) => p.matches(f.name)),
        )
        .map((MediaFile f) => f.path)
        .toList();
    // Counted as the user's own setups, matching what Games shows.
    final int made = (await ConfigStore.list())
        .where((SavedConfig c) => !c.isCollection)
        .length;
    if (mounted) {
      setState(() {
        _index = index;
        _configCount = made;
      });
    }
    await MusicPlayer.playRandom(tunes);
  }

  /// What the scroller says.
  ///
  /// A demo scroller with nothing to say is filler; one that says what is on
  /// the machine is the shelf reading itself out, which is what these always
  /// did. Read fresh each time the screensaver comes up, because a count that
  /// is out of date is worse than none.
  @visibleForTesting
  String get scrollTextForTest => _scrollText;

  String get _scrollText {
    final StringBuffer text = StringBuffer('AMIGA-RETRO  ***  ');
    text.write('$_configCount CONFIG${_configCount == 1 ? '' : 'S'}  ***  ');
    for (final FileCategory category in <FileCategory>[
      FileCategory.floppies,
      FileCategory.whdloadGames,
      FileCategory.hardDrives,
      FileCategory.cdImages,
      FileCategory.roms,
      FileCategory.music,
    ]) {
      final int count = _index.of(category).length;
      // A category with nothing in it is not a statistic, it is a blank.
      if (count == 0) continue;
      text.write('$count ${category.displayName.toUpperCase()}  ***  ');
    }
    final MusicState music = MusicPlayer.state;
    if (music.playing && music.title.isNotEmpty) {
      text.write('NOW PLAYING ${music.title.toUpperCase()}  ***  ');
    }
    text.write('KICKSTART YOUR MEMORY  ***  ');
    return text.toString();
  }

  /// Writes a config for every system on the device, once, and puts them on
  /// the rail.
  ///
  /// Cheap on the common path: [AmigaSystems.configure] only writes where a
  /// config is missing, so the usual startup is a directory listing and a
  /// compare.
  Future<void> _configureSystems() async {
    try {
      AppLog.info('systems', 'looking for collections');
      final MediaIndex index = await MediaLibrary.cached();
      final List<AmigaSystem> systems = await AmigaSystems.configure(
        index: index,
        // The real pixels, not logical ones: an RTG screen is measured in
        // the display's own pixels, and on a handheld the two differ by a
        // factor of two or more.
        screen: mounted ? View.of(context).physicalSize : null,
      );
      if (!mounted) return;
      setState(() => _systems = systems);
    } on Object catch (e) {
      // A library that cannot be read is the scan's problem to report, not
      // this one's; the rail simply has no systems on it.
      AppLog.warn('systems', 'could not configure: $e');
    }
  }


  Future<void> _refreshSession() async {
    // Something to resume is either a game still running or a save state from
    // one that was left. Both mean the same thing to the user.
    final List<SaveState> states = await SaveStates.list();
    final bool has = states.isNotEmpty || await Session.exists();
    if (!mounted || has == _hasSession) return;
    setState(() {
      _hasSession = has;
      // The rail entry has just gone; do not leave it selected.
      if (!has && _section == WorkbenchSection.resume) {
        _section = WorkbenchSection.setups;
      }
    });
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, () {
      if (mounted) setState(() => _idle = true);
    });
  }

  void _wake() {
    if (_idle) setState(() => _idle = false);
    _restartIdleTimer();
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: AmigaColors.root,
      body: Listener(
        // Observe only: this must not consume the wake-up tap.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _wake(),
        onPointerSignal: (_) => _wake(),
        child: Stack(
          children: <Widget>[
            // The demo is the screensaver, not wallpaper: behind a panel in
            // use it is motion competing with the thing being read.
            // Never over a running game: the demo is the screensaver for an
            // IDLE workbench, and with the machine rendering in the panel
            // "idle" no longer means "nothing is happening".
            if (_idle && !Emulator.playing.value)
              Positioned.fill(child: BoingBackdrop(scrollText: _scrollText)),
            // The logos belong to the demo, not to every screen: a masthead
            // repeated above every panel is a band of chrome doing nothing,
            // and the space is worth more to the panel underneath. They fade
            // in with the backdrop when the workbench goes idle.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: (_idle && !Emulator.playing.value) ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: const SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: _DemoMasthead(),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: (_idle && !Emulator.playing.value) ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              child: IgnorePointer(
                ignoring: _idle && !Emulator.playing.value,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AmigaMetrics.gutter),
                    // The shell every Retro-* front end composes the same
                    // way: root padding, the rail in a width-capped box, one
                    // content panel at radius 8 with 10px of padding, and a
                    // status strip along the bottom that owns the rail's
                    // show/hide. The rail itself is now the shared
                    // widgets/sidebar.dart -- this app's own WorkbenchSidebar
                    // was a fourth implementation of the same thing, so a fix
                    // to any of them was a fix to one of four.
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              ...<Widget>[
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: amigaSidebarStyle.maxWidth(width),
                                  ),
                                  child: Sidebar(
                                    destinations: <SidebarDestination>[
                                      // Systems are named for what they are
                                      // -- AGS, PiMiga -- because that is
                                      // what the user came for; the folder
                                      // they live in is detail.
                                      for (final WorkbenchSection s
                                          in _sections)
                                        SidebarDestination(
                                          s.title,
                                          icon: s.icon,
                                          group: s.group,
                                        ),
                                    ],
                                    selectedIndex: _sections.indexOf(_section),
                                    onSelected: (int i) {
                                      _wake();
                                      // While the machine is in the panel,
                                      // picking a rail entry is how you leave
                                      // it -- the C64 rail works the same
                                      // way, and it is why the strip needs no
                                      // pause or stop of its own.
                                      Emulator.stopInProcess();
                                      setState(() => _section = _sections[i]);
                                    },
                                    style: amigaSidebarStyle,
                                    pinLastGroupToBottom: true,
                                  ),
                                ),
                                const SizedBox(width: AmigaMetrics.gutter),
                              ],
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                          color: AmigaColors.panel,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: AmigaColors.panelBorder,
                                          ),
                                        ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _panel(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Whether the machine has the whole screen right now.
  Widget _panel() {
    // The machine is no longer here.
    //
    // It has a screen of its own -- see EmulatorScreen, pushed from
    // _onPlayingChanged. Hosting it in this panel put the in-game controls in
    // a strip outside the picture, which auto-hid and which the pad overlay
    // could cover, so the way out of a game was unreachable exactly when it
    // was wanted. Building it here as well would also mean two
    // AmigaScreenViews and two external textures for one Amiga.
    switch (_section) {
      case WorkbenchSection.collections:
        return _collectionsPage();
      case WorkbenchSection.files:
        return const LibraryPanel();
      case WorkbenchSection.setups:
        return const ConfigurationsScreen(embedded: true);
      case WorkbenchSection.history:
        return const HistoryScreen();
      case WorkbenchSection.compliance:
        // Held rather than rebuilt. Every other case here is `const`, so
        // Flutter sees the identical widget on a rebuild and skips the
        // subtree entirely; this one allocated a fresh instance on each of
        // the nineteen setState calls in this screen -- including the
        // three-second chrome timer -- and so was the only panel actually
        // being rebuilt for reasons that had nothing to do with it.
        return _compliancePanel ??= CompliancePanel(
          onRerunSetup: widget.onRerunSetup,
        );
      case WorkbenchSection.about:
        return const AboutPanel();
      case WorkbenchSection.music:
        return const MusicPanel();
      case WorkbenchSection.settings:
        return const SettingsPanel();
      case WorkbenchSection.av:
        return const AvPanel();
      case WorkbenchSection.input:
        return const InputPanel();
      case WorkbenchSection.resume:
        return const ResumePanel();
    }
  }
}

/// Everything on this device that is ready to run, and a Play button each.
///
/// One page rather than a rail entry per system. The rail is a fixed set of
/// places; a row that appears when a card is plugged in and vanishes when it
/// is pulled out is not a place, it is content — and a rail that grows a row
/// per collection stops being navigable on a handheld.
///
/// Each row is backed by a real config, written when the system was found, so
/// anything here can also be opened and edited from Games like any other
/// setup. Nothing about these is a special case except that nobody had to
/// build them.
extension _CollectionsPage on _WorkbenchScreenState {
  Widget _collectionsPage() {
    if (_systems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('🗂️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 14),
              Text(
                'No collections yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Put AGS, AmigaVision, PiMiga, a WHDLoad pack — or just a '
                'folder of Amiga files — in its own folder under HardDrives, '
                'then rescan on the Files page. Each one found is set up with '
                'the machine it needs and appears here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AmigaColors.textDim, height: 1.45),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _systems.length,
      separatorBuilder: (BuildContext context, int i) =>
          const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) {
        final AmigaSystem system = _systems[i];
        return Card(
          color: AmigaColors.card,
          child: ListTile(
            leading: Text(system.icon, style: const TextStyle(fontSize: 28)),
            title: Text(system.name),
            subtitle: Text(
              '${system.machineSummary}'
              '${system.accurate ? ' · accurate' : ''}\n'
              '${system.isFolder ? 'Folder as DH0' : '${system.set.driveCount} drive(s)'}'
              ' · ${system.set.name}',
              style: const TextStyle(fontSize: 11),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Fast (JIT, full CPU speed) or accurate (neither), per
                // collection. A bolt rather than words: it sits on every
                // row, and its tooltip carries the explanation.
                IconButton(
                  icon: Icon(
                    system.accurate ? Icons.speed_outlined : Icons.bolt,
                    color: system.accurate ? AmigaColors.textDim : null,
                  ),
                  tooltip: system.accurate
                      ? 'Accurate: JIT off, real speed — tap for fast'
                      : 'Fast: JIT on, full speed — tap for accurate',
                  onPressed: () async {
                    await AmigaSystems.setSpeed(
                      system,
                      accurate: !system.accurate,
                    );
                    // Regenerates the config with the new speed.
                    await _configureSystems();
                  },
                ),
                FilledButton.icon(
                  onPressed: () => _playSystem(system),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _playSystem(AmigaSystem system) async {
    // Repaired first, exactly as Resume does it.
    //
    // repairConfigFile fills in a Kickstart the config was written without,
    // and that is not a theoretical case here: a config generated before the
    // ROM was chosen names none, and a machine with no ROM does not report an
    // error -- it starts, maps nothing and shows a black screen, which reads
    // as the emulator being broken rather than the setup being incomplete.
    // It also re-points paths at this install, which matters on a card that
    // may have been moved between devices.
    await ConfigStore.repairConfigFile(system.configPath);
    await Emulator.launch(<String>[
      '--rescan-roms',
      '--config',
      system.configPath,
      '-G',
    ]);
  }
}

/// Logo, wordmark and tick, shown over the demo while the workbench is idle.
class _DemoMasthead extends StatelessWidget {
  const _DemoMasthead();

  @override
  Widget build(BuildContext context) {
    // Sized off the screen rather than fixed: this is the title card of a
    // demo, so it should fill the width the way one did, and a handheld and an
    // iPad want very different numbers for that.
    final double width = MediaQuery.sizeOf(context).width;
    final double logo = (width * 0.20).clamp(90.0, 260.0);
    final double tick = logo * 0.52;
    final double wordmark = logo * 0.40;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Image.asset(
          'assets/images/retro_recomp_logo.png',
          height: logo,
          filterQuality: FilterQuality.medium,
        ),
        SizedBox(height: logo * 0.10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AmigaLogo(height: tick),
            SizedBox(width: tick * 0.28),
            Text(
              'Retro-Amiga',
              style: TextStyle(
                fontSize: wordmark,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: AmigaColors.text,
                shadows: const <Shadow>[
                  Shadow(color: Color(0xCC000000), blurRadius: 12),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Calls back when the app comes back to the front, so state that changed
/// while another process was in charge - the session marker, written by the
/// emulator - is re-read rather than assumed.
class _LifecycleWatch extends WidgetsBindingObserver {
  _LifecycleWatch({required this.onResumed, required this.onPaused});

  final void Function() onResumed;
  final void Function() onPaused;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        onPaused();
      case AppLifecycleState.inactive:
        // Transient - a notification shade, a permission dialog - and
        // silencing on it makes the music stutter every time one appears.
        break;
    }
  }
}
