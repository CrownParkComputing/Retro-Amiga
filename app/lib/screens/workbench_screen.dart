import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/boing_backdrop.dart';
import '../widgets/workbench_sidebar.dart';
import '../data/file_category.dart';
import '../data/config_store.dart';
import '../data/media_library.dart';
import '../data/music_player.dart';
import '../data/save_states.dart';
import '../data/session.dart';
import 'about_panel.dart';
import 'configurations_screen.dart';
import 'history_screen.dart';
import 'library_panel.dart';
import 'logs_panel.dart';
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
  const WorkbenchScreen({super.key});

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
  Timer? _idleTimer;

  /// Resume is only offered when a game was left running - see Session. It is
  /// re-checked whenever the workbench comes back to the front, which is what
  /// happens after quitting a game.
  bool _hasSession = false;

  List<WorkbenchSection> get _sections => WorkbenchSection.values
      .where((WorkbenchSection s) =>
          s != WorkbenchSection.resume || _hasSession)
      .toList();

  @override
  void initState() {
    super.initState();
    _restartIdleTimer();
    _refreshSession();
    _startMusic();
    WidgetsBinding.instance.addObserver(_watch);
  }

  late final _LifecycleWatch _watch = _LifecycleWatch(
    onResumed: () {
      _refreshSession();
      MusicPlayer.resumeIfSuspended();
    },
    // Minimising should be silent: the launcher's music playing out of a
    // pocket while the app is not on screen is nobody's idea of a feature.
    onPaused: MusicPlayer.suspend,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_watch);
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Puts a tune on while the workbench is up, and takes the count of what is
  /// on the device for the scroller while the index is in hand.
  Future<void> _startMusic() async {
    final MediaIndex index = await MediaLibrary.cached();
    final List<String> tunes = index.files
        .where((MediaFile f) => f.category == FileCategory.music)
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
            if (_idle)
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
                  opacity: _idle ? 1 : 0,
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
              opacity: _idle ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              child: IgnorePointer(
                ignoring: _idle,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AmigaMetrics.gutter),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              WorkbenchSidebar(
                                selected: _section,
                                available: width,
                                sections: _sections,
                                onSelected: (WorkbenchSection s) {
                                  _wake();
                                  setState(() => _section = s);
                                },
                              ),
                              const SizedBox(width: AmigaMetrics.gutter),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AmigaColors.panel,
                                    borderRadius: BorderRadius.circular(
                                      AmigaMetrics.panelRadius,
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

  Widget _panel() {
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
      case WorkbenchSection.logs:
        return const LogsPanel();
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
              'Amiga-Retro',
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
