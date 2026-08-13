import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/boing_backdrop.dart';
import '../widgets/workbench_sidebar.dart';
import '../data/session.dart';
import 'about_panel.dart';
import 'configurations_screen.dart';
import 'history_screen.dart';
import 'library_panel.dart';
import 'logs_panel.dart';
import 'music_panel.dart';
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
    WidgetsBinding.instance.addObserver(_LifecycleWatch(_refreshSession));
  }

  Future<void> _refreshSession() async {
    final bool has = await Session.exists();
    if (!mounted || has == _hasSession) return;
    setState(() {
      _hasSession = has;
      // The rail entry has just gone; do not leave it selected.
      if (!has && _section == WorkbenchSection.resume) {
        _section = WorkbenchSection.setups;
      }
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
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
            Positioned.fill(child: BoingBackdrop(opacity: _idle ? 1 : 0.32)),
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
        return _Placeholder(section: _section);
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

/// Named rather than blank, so an empty panel says what will live there.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.section});

  final WorkbenchSection section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(section.icon, size: 44, color: AmigaColors.textDim),
          const SizedBox(height: 12),
          Text(
            section.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AmigaColors.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Not built yet.',
            style: TextStyle(color: AmigaColors.textDim),
          ),
        ],
      ),
    );
  }
}


/// Calls back when the app comes back to the front, so state that changed
/// while another process was in charge - the session marker, written by the
/// emulator - is re-read rather than assumed.
class _LifecycleWatch extends WidgetsBindingObserver {
  _LifecycleWatch(this.onResumed);

  final void Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
