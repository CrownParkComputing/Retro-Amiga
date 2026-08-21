import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/boing_backdrop.dart';
import '../widgets/sidebar_style.dart';
import '../widgets/workbench_sidebar.dart';
import '../data/app_prefs.dart';
import '../data/file_category.dart';
import '../data/config_store.dart';
import '../data/game_controller.dart';
import '../data/media_library.dart';
import '../data/pad_layout.dart';
import '../data/pad_layout_store.dart';
import '../data/music_picks.dart';
import '../data/music_player.dart';
import '../data/save_states.dart';
import '../data/session.dart';
import '../ffi/amiga_core.dart';
import '../widgets/amiga_keyboard_overlay.dart';
import '../widgets/amiga_screen_view.dart';
import '../widgets/pad_overlay.dart';
import '../widgets/media_chooser.dart';
import '../emulator.dart';
import '../widgets/sidebar.dart';
import 'about_panel.dart';
import 'audio_panel.dart';
import 'configurations_screen.dart';
import 'history_screen.dart';
import 'input_panel.dart';
import 'library_panel.dart';
import 'music_panel.dart';
import 'pad_designer_screen.dart';
import 'resume_panel.dart';
import 'settings_panel.dart';
import 'video_panel.dart';

/// The home screen: a nav rail and one content panel, floating over the boing
/// ball.
///
/// Left untouched for [_idleDelay] the panels fade back and the backdrop comes
/// forward, so an idle handheld shows the demo rather than a menu. Any touch
/// anywhere brings the workbench straight back - the Listener sits above
/// everything and only observes, so the tap that wakes it still reaches
/// whatever was under it.
class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  static const Duration _idleDelay = Duration(seconds: 30);

  WorkbenchSection _section = WorkbenchSection.setups;
  bool _idle = false;

  /// Whether the rail is collapsed. The status strip along the bottom owns
  /// the toggle -- it is outside the rail because it is the only way back
  /// once the rail is gone. Same arrangement as Retro-Dosbox and Retro-C64.
  bool _sidebarHidden = false;

  /// What the scan found and how many configs there are, for the scroller.
  MediaIndex _index = const MediaIndex.empty();
  int _configCount = 0;
  Timer? _idleTimer;
  StreamSubscription<MediaIndex>? _mediaChanges;

  /// Resume is only offered when a game was left running - see Session. It is
  /// re-checked whenever the workbench comes back to the front, which is what
  /// happens after quitting a game.
  bool _hasSession = false;

  // In-process session controls, shown in the status strip while the machine
  // is in the panel. Fill is AppPrefs.screenFill (remembered, and shared with
  // the Video panel); the rest resets with the session.
  bool _mouseMode = false;
  /// Starts hidden when real hardware is attached: a handheld with its own
  /// sticks should not have touch controls drawn over them. Set for real in
  /// _startSession, which asks the host before the first frame of a game.
  bool _padVisible = true;
  bool _keyboardUp = false;

  /// True once _attachPad has registered the pad with the core. Until then no
  /// pad event may be pushed in: see _padTarget.
  bool _padAttached = false;

  /// While a game runs, the rail and the strip step aside after a few
  /// seconds so the picture gets the whole screen. Any touch that is not on
  /// an on-screen control brings them back -- the controls themselves do not,
  /// because reaching for fire should never shuffle the layout mid-jump.
  bool _chromeVisible = true;
  Timer? _chromeTimer;

  void _wakeChrome() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && Emulator.playing.value) {
        setState(() => _chromeVisible = false);
      }
    });
    if (!_chromeVisible && mounted) setState(() => _chromeVisible = true);
  }
  PadLayout _layout = PadLayout.defaults;

  int get _pad => _layout.style == PadStyle.cd32 ? 2 : 1;

  /// Opens the panel the in-game rail asked for, if it asked for one.
  ///
  /// The overlay engine cannot reach the launcher's engine, so the request
  /// crosses as a file the Activity writes on the way out (see
  /// HostSupport.writeSectionRequest). It is consumed here: a stale request
  /// would hijack the next launch too.
  void _onPlayingChanged() {
    if (!mounted) return;
    setState(() {
      _mouseMode = false;
      _keyboardUp = false;
      _chromeVisible = true;
    });
    if (Emulator.playing.value) {
      _wakeChrome();
    } else {
      _chromeTimer?.cancel();
      _padAttached = false;
      // Give the buttons back to the launcher: a handheld navigates its own
      // menus with the same stick it just played with.
      unawaited(GameController.setGameRunning(false));
    }
    if (Emulator.playing.value) _startSession();
  }

  /// A session has begun in the panel: load the pad layout the designer
  /// saved and register the pad it asks for with the core.
  Future<void> _startSession() async {
    final PadLayout layout = await PadLayoutStore.load();
    // Ask before drawing: a controller already attached means the on-screen
    // pad should never appear, rather than appear and then vanish.
    final bool hasPad = await GameController.start();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _padVisible = !hasPad;
    });
    _bindPhysicalController();
    unawaited(GameController.setGameRunning(true));
    _attachPad();
  }

  /// A controller arriving or leaving mid-session.
  ///
  /// Plugging one in hides the touch pad; unplugging brings it back, because
  /// otherwise a game becomes unplayable the moment a battery dies.
  void _onControllerChanged() {
    if (!mounted || !Emulator.playing.value) return;
    setState(() => _padVisible = !GameController.connected.value);
    _attachPad();
  }

  void _attachPad() {
    final AmigaCore? core = Emulator.inProcessCore;
    if (core == null || !core.isRunning) return;
    // Attached even when nothing is drawn. The pad is the DEVICE bound to
    // port 1, not the picture: detaching it because a real controller is
    // present would leave the port with nothing driving it, which is exactly
    // what made a physical pad do nothing at all.
    core.padAttach(_pad);
    core.setPortMode(_layout.style == PadStyle.cd32 ? 7 : 3);
    core.setOnscreenController(_padVisible ? _pad : 0);
    _padAttached = true;
  }

  /// Routes a physical controller into the same pad the touch controls drive.
  ///
  /// The core cannot see the hardware itself on this path: SDL learns about
  /// Android controllers through SDLActivity's callbacks, and the in-process
  /// core is a thread in the Flutter activity rather than an SDLActivity. So
  /// the host forwards the events and they are pushed in here.
  void _bindPhysicalController() {
    GameController.onDirection = (bool l, bool r, bool u, bool d) {
      final AmigaCore? core = _padTarget();
      if (core == null) return;
      core.padDirection(_pad, u, d, l, r);
    };
    GameController.onButton = (int button, bool pressed) {
      final AmigaCore? core = _padTarget();
      if (core == null) return;
      core.padButton(_pad, button, pressed);
    };
  }

  /// The core to push pad input into, or null if now is not the time.
  ///
  /// [_padAttached] is the load-bearing part. These calls reach the core's
  /// input-device table, which registers a virtual pad on first use, and they
  /// arrive on the platform thread while the emulator runs on its own. During
  /// startup the core is building that table and parsing config through the
  /// same string maps, and a pad event landing in the middle corrupted the
  /// heap: an unordered_map::find on a half-built table, then SIGABRT out of
  /// Scudo. Waiting until _attachPad has registered the device means the table
  /// is built before anything else touches it.
  AmigaCore? _padTarget() {
    if (!_padAttached || !Emulator.playing.value) return null;
    final AmigaCore? core = Emulator.inProcessCore;
    if (core == null || !core.isRunning) return null;
    return core;
  }

  Future<void> _adoptRequestedSection() async {
    try {
      final File request =
          File('\${await HostPaths.appSupport()}/workbench_section');
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
    AppPrefs.screenFill.addListener(_onPlayingChanged);
    // The panel swaps to the machine when a session starts, and back when it
    // ends, without anything else having to know.
    Emulator.playing.addListener(_onPlayingChanged);
    _restartIdleTimer();
    _refreshSession();
    _startMusic();
    _mediaChanges = MediaLibrary.changes.listen((MediaIndex index) {
      if (mounted) setState(() => _index = index);
    });
    WidgetsBinding.instance.addObserver(_watch);
    GameController.connected.addListener(_onControllerChanged);
    // Bound once, not per session. These no-op unless a core is running, and
    // binding them only when a game starts meant any path that reached the
    // panel without going through _startSession left a controller doing
    // nothing at all.
    _bindPhysicalController();
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
    AppPrefs.screenFill.removeListener(_onPlayingChanged);
    WidgetsBinding.instance.removeObserver(_watch);
    GameController.connected.removeListener(_onControllerChanged);
    GameController.onDirection = null;
    GameController.onButton = null;
    unawaited(GameController.setGameRunning(false));
    _mediaChanges?.cancel();
    _idleTimer?.cancel();
    _chromeTimer?.cancel();
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
    final List<SavedConfig> configs = await ConfigStore.list();
    if (mounted) {
      setState(() {
        _index = index;
        _configCount = configs.length;
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
                    padding: EdgeInsets.all(_hideChrome ? 0 : AmigaMetrics.gutter),
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
                              if (!_sidebarHidden && !_hideChrome) ...<Widget>[
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: amigaSidebarStyle.maxWidth(width),
                                  ),
                                  child: Sidebar(
                                    destinations: <SidebarDestination>[
                                      for (final WorkbenchSection s in _sections)
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
                                  padding:
                                      EdgeInsets.all(_hideChrome ? 0 : 10),
                                  decoration: _hideChrome
                                      ? const BoxDecoration(
                                          color: AmigaColors.panel,
                                        )
                                      : BoxDecoration(
                                          color: AmigaColors.panel,
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                        if (!_hideChrome) _statusBar(),
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
  bool get _hideChrome =>
      Emulator.inProcessCore != null &&
      Emulator.playing.value &&
      !_chromeVisible;

  /// The bottom strip, outside both the rail and the content panel: the
  /// show/hide toggle and what is loaded. It always renders, even with the
  /// rail hidden -- the toggle is the only way back once the rail is gone, so
  /// it cannot live inside the rail it controls.
  Widget _statusBar() {
    final bool inGame =
        Emulator.inProcessCore != null && Emulator.playing.value;
    return SizedBox(
      // A little taller while the machine is running - the buttons are still
      // finger sized - but only a little: every pixel this strip takes is a
      // pixel the picture does not get.
      height: inGame ? 36 : 28,
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () {
              _wake();
              setState(() => _sidebarHidden = !_sidebarHidden);
            },
            icon: Icon(
              _sidebarHidden ? Icons.menu : Icons.menu_open,
              size: 18,
            ),
            color: AmigaColors.textDim,
            tooltip: _sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          // No label here. The rail already shows which section is selected,
          // in the same words, a few pixels away -- and when the rail is
          // hidden the panel's own heading says it. A third copy was just
          // noise next to the toggle.
          const Spacer(),
          if (inGame) ..._sessionTools(Emulator.inProcessCore!),
        ],
      ),
    );
  }

  /// The in-game toolbar: the C64 strip's shape -- small round buttons the
  /// size of a fingertip, laid out from the right-hand edge -- under the panel
  /// where the rail's toggle already lives.
  List<Widget> _sessionTools(AmigaCore core) {
    const Color idle = Color(0xFF24292E);
    const Color lit = Color(0xFF4040E0);
    // Compact, not FAB-sized: the strip sits under the picture, and a row of
    // 40px buttons was costing the Amiga a border's worth of height. 32px is
    // still a comfortable target with the strip's own padding around it.
    Widget tool({
      required String tag,
      required IconData icon,
      required String tip,
      required VoidCallback onPressed,
      bool active = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Material(
          color: active ? lit : idle,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Tooltip(
            message: tip,
            child: InkWell(
              onTap: () {
                _wake();
                _wakeChrome();
                onPressed();
              },
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(icon, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      );
    }

    return <Widget>[
      // Right-to-left in the C64's order: keyboard nearest the hand, then
      // the pad, then the rest. No stop -- the rail is the way out.
      tool(
        tag: 'pauseFab',
        icon: Icons.pause,
        tip: 'Pause and keep your place',
        onPressed: () async {
          // Pause leaves the machine, the way the C64 front end's does. It
          // used to stop the picture in place, which meant the paused state
          // lived only in this session: nothing on the Resume shelf, and a
          // machine still loaded behind whatever the user did next.
          //
          // stopInProcess writes the snapshot BEFORE the core goes down -
          // that ordering matters, because the save is serviced by the core's
          // own thread - so what comes back on Resume is the exact moment
          // they stepped away.
          Emulator.forgetBackgroundPause();
          Emulator.stopInProcess();
          await _refreshSession();
          if (!mounted) return;
          setState(() {
                  // Land on Resume, not the shelf: what the user wants in front of
            // them after pausing is the way back in.
            _sidebarHidden = false;
            _section = WorkbenchSection.resume;
          });
        },
      ),
      tool(
        tag: 'layoutFab',
        icon: Icons.open_with,
        tip: 'Move or add on-screen controls',
        onPressed: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const PadDesignerScreen(),
            ),
          );
          // Whatever was arranged is the pad now.
          final PadLayout layout = await PadLayoutStore.load();
          if (!mounted) return;
          setState(() => _layout = layout);
          _attachPad();
        },
      ),
      tool(
        tag: 'fillFab',
        icon: AppPrefs.screenFill.value ? Icons.fit_screen : Icons.aspect_ratio,
        tip: AppPrefs.screenFill.value
            ? 'Keep the Amiga\'s shape'
            : 'Fill the screen (16:9)',
        active: AppPrefs.screenFill.value,
        onPressed: () =>
            AppPrefs.setScreenFill(value: !AppPrefs.screenFill.value),
      ),
      tool(
        tag: 'swapFab',
        icon: Icons.swap_horiz,
        tip: 'Swap disk',
        onPressed: () => _swapDisk(core),
      ),
      tool(
        tag: 'mouseFab',
        icon: Icons.mouse,
        tip: _mouseMode ? 'Touch is the mouse' : 'Use touch as the mouse',
        active: _mouseMode,
        onPressed: () {
          setState(() => _mouseMode = !_mouseMode);
          // Leaving the mode with a button held would leave the Amiga
          // holding it.
          if (!_mouseMode) {
            core.mouseButton(0, false);
            core.mouseButton(1, false);
          }
        },
      ),
      tool(
        tag: 'padFab',
        icon: Icons.videogame_asset,
        tip: _padVisible ? 'Hide the on-screen pad' : 'Show the on-screen pad',
        active: _padVisible,
        onPressed: () {
          setState(() => _padVisible = !_padVisible);
          if (!_padVisible) core.padReleaseAll(_pad);
          core.setOnscreenController(_padVisible ? _pad : 0);
        },
      ),
      tool(
        tag: 'keyboardFab',
        icon: Icons.keyboard,
        tip: _keyboardUp ? 'Keyboard shown' : 'Keyboard hidden',
        active: _keyboardUp,
        onPressed: () {
          setState(() => _keyboardUp = !_keyboardUp);
          if (_keyboardUp) core.padReleaseAll(_pad);
        },
      ),
    ];
  }

  /// Asks which drive when there is more than one, then which disk.
  Future<void> _swapDisk(AmigaCore core) async {
    final int drives = core.floppyCount;
    int drive = 0;
    if (drives > 1) {
      final int? picked = await showDialog<int>(
        context: context,
        builder: (BuildContext context) => SimpleDialog(
          backgroundColor: AmigaColors.panel,
          title: const Text('Swap disk in', style: TextStyle(fontSize: 16)),
          children: <Widget>[
            for (int i = 0; i < drives; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(i),
                child: Text('DF$i'),
              ),
          ],
        ),
      );
      if (picked == null) return;
      drive = picked;
    }
    if (!mounted) return;
    final String? path = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AmigaColors.panel,
      builder: (BuildContext sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheet).size.height * 0.7,
          child: MediaChooser(
            category: FileCategory.floppies,
            selected: '',
            onSelected: (String p) => Navigator.of(sheet).pop(p),
            emptyHint: 'No floppy images found.',
          ),
        ),
      ),
    );
    if (path != null) core.insertFloppy(drive, path);
  }

  Widget _panel() {
    // A live in-process session IS the panel's content: the machine renders
    // here, in the same box every other section uses, with the rail and the
    // status strip still on screen. That is the whole reason the core moved
    // into this process.
    final AmigaCore? core = Emulator.inProcessCore;
    if (core != null && Emulator.playing.value) {
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: AmigaScreenView(
              core: core,
              fill: AppPrefs.screenFill.value,
              mouseMode: _mouseMode,
            ),
          ),
          // The chrome's wake-up call. UNDER the pad and the keyboard, so a
          // touch they claim - a stick move, a fire press, a key - never
          // reaches it, and only a touch on the picture itself brings the
          // rail and the strip back. Translucent, so the same touch still
          // works as the mouse when the mouse mode is on.
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _wakeChrome(),
            ),
          ),
          // The pad steps aside while the keyboard is up: both live along
          // the bottom, and a stick drawn over the letters makes both
          // unusable.
          if (_padVisible && !_keyboardUp)
            Positioned.fill(
              child: PadOverlay(
                layout: _layout,
                onDirections: (bool up, bool down, bool left, bool right) =>
                    core.padDirection(_pad, up, down, left, right),
                onButton: (int button, bool pressed) =>
                    core.padButton(_pad, button, pressed),
                onKey: core.sendKey,
              ),
            ),
          if (_keyboardUp)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AmigaKeyboardOverlay(
                onKey: core.sendKey,
                onClose: () => setState(() => _keyboardUp = false),
              ),
            ),
        ],
      );
    }
    switch (_section) {
      case WorkbenchSection.files:
        return const LibraryPanel();
      case WorkbenchSection.setups:
        return const ConfigurationsScreen(embedded: true);
      case WorkbenchSection.history:
        return const HistoryScreen();
      case WorkbenchSection.about:
        return const AboutPanel();
      case WorkbenchSection.music:
        return const MusicPanel();
      case WorkbenchSection.settings:
        return const SettingsPanel();
      case WorkbenchSection.video:
        return const VideoPanel();
      case WorkbenchSection.input:
        return const InputPanel();
      case WorkbenchSection.audio:
        return const AudioPanel();
      case WorkbenchSection.resume:
        return const ResumePanel();
    }
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
