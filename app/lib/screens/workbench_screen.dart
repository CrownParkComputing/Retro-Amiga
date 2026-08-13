import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/boing_backdrop.dart';
import '../widgets/workbench_sidebar.dart';
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

  @override
  void initState() {
    super.initState();
    _restartIdleTimer();
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Image.asset(
          'assets/images/retro_recomp_logo.png',
          height: 40,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(width: 14),
        const AmigaLogo(height: 26),
        const SizedBox(width: 8),
        const Text(
          'Amiga-Retro',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AmigaColors.text,
          ),
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
