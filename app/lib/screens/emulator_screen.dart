import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_log.dart';
import '../data/app_prefs.dart';
import '../data/file_category.dart';
import '../data/game_controller.dart';
import '../data/pad_layout.dart';
import '../data/pad_layout_store.dart';
import '../emulator.dart';
import '../ffi/amiga_core.dart';
import '../theme/amiga_theme.dart';
import '../widgets/amiga_keyboard_overlay.dart';
import '../widgets/media_chooser.dart';
import '../widgets/amiga_screen_view.dart';
import '../widgets/pad_overlay.dart';
import 'pad_designer_screen.dart';

/// The machine, with the whole screen and its own controls.
///
/// The panel this replaces put the Amiga inside the workbench, beside the rail
/// and above a status strip that carried the in-game buttons. That strip was
/// the problem. It lived OUTSIDE the picture, it hid itself after a few
/// seconds to stop stealing pixels, and the pad overlay -- which covers most
/// of a handheld's screen -- sat on top of the only region whose touches
/// brought it back. So the controls for leaving a game were unreachable
/// exactly when a game most needed leaving, and no amount of adjusting
/// timeouts fixed the shape of it.
///
/// Here the controls are ON the picture. Nothing else is competing for that
/// space, there is no layout in which the pad can cover them, and the picture
/// gets the whole screen instead of paying for the rail and the strip on
/// every frame.
///
/// Two ways out, and they mean different things:
///
///   * **Pause** writes the snapshot and leaves. The session goes on the
///     Resume shelf and comes back at the exact moment it was left.
///   * **Close** ends it. Nothing is written -- a snapshot is a full memory
///     dump, and filling the shelf with sessions nobody asked to keep is not
///     a kindness.
class EmulatorScreen extends StatefulWidget {
  const EmulatorScreen({super.key, required this.core, required this.title});

  final AmigaCore core;

  /// What is running, shown while the controls are up.
  final String title;

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  PadLayout _layout = const PadLayout();
  /// The on-screen pad is drawn unless real hardware is attached: a handheld
  /// with its own sticks should not have touch controls over them. No longer
  /// a toggle -- there is nothing to decide, and a button for it was a button
  /// spent on a question the app can answer.
  bool _padVisible = true;
  /// The keyboard is offered when the preference asks for it -- see the A/V
  /// page. It closes itself with its own button, so it needs no rail entry.
  bool _keyboardUp = false;
  /// Touch drives the mouse, always.
  ///
  /// It used to be a mode you turned on, which is the wrong shape: the mouse
  /// is plugged into one of the two ports whichever way round they are, so it
  /// is always live and a finger on the picture is always pointing at
  /// something. The pad overlay sits on top and takes the touches inside its
  /// own controls, so the stick and the pointer coexist rather than trading
  /// places through a button.
  static const bool _mouseMode = true;

  /// Whether the controls are showing. They start up so the way out is known
  /// before it is needed, then get out of the way.
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  /// The menu: controls pinned up, machine stopped behind them.
  ///
  /// Distinct from the controls merely being visible. Those fade after a few
  /// seconds, which is right when you have tapped the screen to check
  /// something and wrong when you have deliberately asked for the menu --
  /// especially from a controller, where there is no finger on the glass to
  /// keep them awake and the game carries on being played while you read.
  ///
  /// So this pauses the Amiga and stays up until it is dismissed.
  bool _menuOpen = false;

  int _padPort = 1;
  Timer? _portPollTimer;

  /// Whether the Amiga's right mouse button is being held down for us.
  ///
  /// Amiga menus are not a click, they are a hold: you press the right button,
  /// the menu bar appears, you move the pointer onto the item you want, and
  /// you release. A long-press that clicks and lets go immediately can open a
  /// menu and cannot choose anything from it, which is why the right button
  /// has been effectively unusable on touch.
  ///
  /// So this latches. Press once and the button stays down while you drag the
  /// pointer wherever you like; press again to let go, which is what picks
  /// the item under it.
  bool _rightHeld = false;


  int get _pad => _layout.style == PadStyle.cd32 ? 2 : 1;

  @override
  void initState() {
    super.initState();
    _start();
    _restartControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _portPollTimer?.cancel();
    GameController.onDirection = null;
    GameController.onButton = null;
    GameController.onMenu = null;
    unawaited(GameController.setGameRunning(false));
    super.dispose();
  }

  Future<void> _start() async {
    final PadLayout layout = await PadLayoutStore.load();
    // Ask before drawing: a controller already attached means the on-screen
    // pad should never appear, rather than appear and then vanish.
    final bool hasPad = await GameController.start();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _padVisible = AppPrefs.showPad.value && !hasPad;
      // Up from the start when asked for; the rail's Keys tool (and the
      // keyboard's own CLOSE key) toggle it from there.
      _keyboardUp = AppPrefs.showKeyboard.value;
      // Read, not assumed: the label claims to show how the machine is wired,
      // so it has to ask the machine rather than start from a guess that
      // happens to be right most of the time.
      _padPort = widget.core.padPort;
    });
    _bindController();
    GameController.onMenu = _toggleMenu;
    unawaited(GameController.setGameRunning(true));
    _attachPad();
  }

  void _bindController() {
    GameController.onDirection = (bool l, bool r, bool u, bool d) =>
        widget.core.padDirection(_pad, u, d, l, r);
    GameController.onButton = (int button, bool pressed) =>
        widget.core.padButton(_pad, button, pressed);
  }

  void _attachPad() {
    if (!widget.core.isRunning) return;
    // Attached even when nothing is drawn: the pad is the DEVICE bound to the
    // port, not the picture.
    widget.core.padAttach(_pad);
    widget.core.setPortMode(_layout.style == PadStyle.cd32 ? 7 : 3);
    widget.core.setOnscreenController(_padVisible ? _pad : 0);
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (_menuOpen) return; // already up, and pinned
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _restartControlsTimer();
  }

  /// Opens or closes the pause menu.
  void _toggleMenu() {
    final bool open = !_menuOpen;
    _controlsTimer?.cancel();
    // The user's own pause outranks the app's: coming back from the menu
    // should not be undone by a background-resume deciding for them.
    Emulator.forgetBackgroundPause();
    widget.core.setPaused(open);
    // Nothing held while the machine is stopped, or it is still held when it
    // starts again.
    if (open) widget.core.padReleaseAll(_pad);
    setState(() {
      _menuOpen = open;
      _controlsVisible = true;
    });
    if (!open) _restartControlsTimer();
  }

  /// Leaves, keeping the exact moment. See the class comment.
  Future<void> _pause() async {
    _releaseHeld();
    Emulator.forgetBackgroundPause();
    Emulator.stopInProcess();
    if (mounted) Navigator.of(context).pop(EmulatorExit.paused);
  }

  /// Leaves, keeping nothing.
  /// Lets go of anything the Amiga is being told to hold.
  void _releaseHeld() {
    if (_rightHeld) {
      _rightHeld = false;
      widget.core.mouseButton(1, false);
    }
  }

  Future<void> _close() async {
    _releaseHeld();
    Emulator.forgetBackgroundPause();
    Emulator.closeInProcess();
    if (mounted) Navigator.of(context).pop(EmulatorExit.closed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back is a way out of the game, not a way to leave it running behind
      // the launcher with no picture and no controls.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The picture, filling the screen. Any touch that is not the pad
            // and not a control wakes the controls; Listener observes without
            // consuming, so the Amiga still gets the same touch.
            // No gesture wakes the controls any more: the corner button is
            // the one way in. Two fingers now BELONGS TO THE AMIGA -- it is
            // the mouse's hold-and-drag, which is how a Workbench window gets
            // resized -- and a single touch is the pointer. A gesture that
            // sometimes opened the menu and sometimes grabbed a window edge
            // would be wrong every time it guessed.
            AmigaScreenView(
                core: widget.core,
                fill: AppPrefs.screenFill.value,
                mouseMode: _mouseMode,
              ),
            if (_padVisible && !_keyboardUp)
              PadOverlay(
                layout: _layout,
                onDirections: (bool up, bool down, bool left, bool right) =>
                    widget.core.padDirection(_pad, up, down, left, right),
                onButton: (int button, bool pressed) =>
                    widget.core.padButton(_pad, button, pressed),
                onKey: widget.core.sendKey,
              ),
            if (_keyboardUp)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AmigaKeyboardOverlay(
                  onKey: widget.core.sendKey,
                  onClose: () => setState(() => _keyboardUp = false),
                ),
              ),
            // While the menu is up the machine is stopped, so the picture is
            // a still. Dimming it says so, and gives the controls something
            // to sit against.
            if (_menuOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleMenu,
                  child: Container(
                    color: const Color(0x99000000),
                    alignment: Alignment.center,
                    // Resume lives HERE, not in the rail.
                    //
                    // It was a rail entry that appeared only while paused,
                    // which pushed every icon below it down a slot -- so the
                    // act of pausing moved the control you were reaching for.
                    // A rail that rearranges itself is worse than one item
                    // short. In the middle it is also simply easier to hit,
                    // which suits the one thing you most often want from a
                    // pause menu.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _ResumeButton(onPressed: _toggleMenu),
                        const SizedBox(height: 14),
                        // Leaving with your place kept.
                        //
                        // This was a Pause icon on the rail, which was the
                        // wrong place twice over: it sat next to Close doing
                        // something quite different, and the rail is for
                        // things you do WHILE playing. Stopping the machine
                        // and deciding what to do with it is one decision,
                        // and it belongs on the screen that stopped it.
                        _MenuChoice(
                          icon: Icons.bookmark_add_outlined,
                          label: 'Save and exit',
                          detail: 'Comes back here on the Resume shelf',
                          onPressed: _pause,
                        ),
                        const SizedBox(height: 8),
                        _MenuChoice(
                          icon: Icons.close,
                          label: 'Close without saving',
                          detail: 'Ends the session',
                          onPressed: _close,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _controls(),
            // The same door for a player with no controller: one handle in
            // one corner, always there, never covered. The two-finger gesture
            // still works and is quicker once known, but a gesture nobody is
            // told about is not a way out.
            _menuHandle(),
          ],
        ),
      ),
    );
  }

  /// The one control that is always on screen, in the same corner, whatever
  /// the machine is doing.
  ///
  /// It used to hide itself while the menu was open, with a Resume button
  /// appearing in the middle instead -- so the same toggle lived in two
  /// places and wore two faces, and pressing it a second time looked like the
  /// button had been replaced rather than flipped. One button, one place: a
  /// hamburger while the game runs, a play arrow while it is stopped.
  Widget _menuHandle() {
    return Align(
      alignment: Alignment.topLeft,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Opacity(
            opacity: _controlsVisible || _menuOpen ? 1 : 0.35,
            child: Material(
              color: _menuOpen
                  ? const Color(0xF24040E0)
                  : const Color(0xCC12151A),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _toggleMenu,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    _menuOpen ? Icons.play_arrow : Icons.menu,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return AnimatedOpacity(
      opacity: _controlsVisible || _menuOpen ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible && !_menuOpen,
        // Down the right-hand edge, not across the top.
        //
        // A horizontal bar has to be as wide as the number of buttons, which
        // on a phone means it either crowds the picture or the buttons get
        // too small to hit. A column costs one button's width and the picture
        // keeps its full height -- and the right edge is where a thumb
        // already is, without being where the pad's stick and fire buttons
        // live.
        child: Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: const Color(0xCC12151A),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  // Scrollable, because nine buttons is taller than a
                  // handheld in landscape. The Retroid Flip2 is 456dp tall
                  // that way round, and a fixed column that overruns it does
                  // not shrink -- it throws an overflow and paints nothing,
                  // which would take the controls away again.
                  child: SingleChildScrollView(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _tool(
                        icon: Icons.close,
                        label: 'Close',
                        tip: 'Close the game',
                        onPressed: _close,
                      ),
                      _tool(
                        icon: AppPrefs.screenFill.value
                            ? Icons.fit_screen
                            : Icons.aspect_ratio,
                        label: AppPrefs.screenFill.value ? 'Shape' : 'Fill',
                        tip: AppPrefs.screenFill.value
                            ? "Keep the Amiga's shape"
                            : 'Fill the screen',
                        active: AppPrefs.screenFill.value,
                        onPressed: () => setState(
                          () => AppPrefs.setScreenFill(
                            value: !AppPrefs.screenFill.value,
                          ),
                        ),
                      ),
                      _tool(
                        icon: Icons.keyboard,
                        label: 'Keys',
                        tip: _keyboardUp
                            ? 'Hide the Amiga keyboard'
                            : 'Show the Amiga keyboard',
                        active: _keyboardUp,
                        onPressed: () =>
                            setState(() => _keyboardUp = !_keyboardUp),
                      ),
                      _tool(
                        icon: Icons.videogame_asset,
                        label: 'Pad',
                        tip: _padVisible
                            ? 'Hide the on-screen pad'
                            : 'Show the on-screen pad',
                        active: _padVisible,
                        onPressed: () {
                          setState(() => _padVisible = !_padVisible);
                          widget.core
                              .setOnscreenController(_padVisible ? _pad : 0);
                        },
                      ),
                      _tool(
                        icon: Icons.open_with,
                        label: 'Layout',
                        tip: 'Move or add on-screen controls',
                        onPressed: () async {
                          // The designer is its own screen; coming back,
                          // rebuild so the overlay reloads the layout it
                          // just saved.
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PadDesignerScreen(),
                            ),
                          );
                          final PadLayout layout =
                              await PadLayoutStore.load();
                          if (mounted) setState(() => _layout = layout);
                        },
                      ),
                      // The two sockets, each showing what is in it.
                      //
                      // This replaced three controls -- a swap button, a
                      // mouse toggle and a pad toggle -- that between them
                      // never said what the machine was actually wired like.
                      // Now the rail shows the wiring, and tapping either
                      // socket rotates the pair.
                      //
                      // Numbered the way the case is, 1 and 2: that is what
                      // is printed beside the sockets and what every game's
                      // instructions say. UAE counts from 0 internally, and
                      // that is UAE's business.
                      _tool(
                        icon: _padPort == 0
                            ? Icons.videogame_asset
                            : Icons.mouse,
                        label: 'Port 1',
                        tip: _padPort == 0
                            ? 'Port 1: joystick — tap to swap the ports'
                            : 'Port 1: mouse — tap to swap the ports',
                        active: _padPort == 0,
                        onPressed: _swapPorts,
                      ),
                      _tool(
                        icon: _padPort == 1
                            ? Icons.videogame_asset
                            : Icons.mouse,
                        label: 'Port 2',
                        tip: _padPort == 1
                            ? 'Port 2: joystick — tap to swap the ports'
                            : 'Port 2: mouse — tap to swap the ports',
                        active: _padPort == 1,
                        onPressed: _swapPorts,
                      ),
                      _tool(
                        icon: _rightHeld
                            ? Icons.ads_click
                            : Icons.menu_open,
                        label: _rightHeld ? 'Held' : 'Menu',
                        tip: _rightHeld
                            ? 'Right button held — move the pointer, then tap '
                                  'to choose'
                            : 'Hold the right mouse button, for Amiga menus',
                        active: _rightHeld,
                        onPressed: () {
                          setState(() => _rightHeld = !_rightHeld);
                          widget.core.mouseButton(1, _rightHeld);
                        },
                      ),
                      _tool(
                        icon: Icons.album,
                        label: 'Disk',
                        tip: 'Swap disk',
                        onPressed: _swapDisk,
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Rotates the two ports: the joystick moves, and the mouse takes the
  /// socket it left. Both stay plugged in.
  void _swapPorts() {
    AppLog.info('ports', 'swap requested (joystick was in port ${_padPort + 1})');
    // Let go first: a direction still held when the device changes port
    // leaves the Amiga holding it with nothing left to release it.
    widget.core.padReleaseAll(_pad);
    widget.core.swapPadPort();
    // The core applies it on its own thread, so read it back rather than
    // assume -- a core too old to have the export never moves, and the labels
    // correctly go on saying what is really there.
    _portPollTimer?.cancel();
    _portPollTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final int now = widget.core.padPort;
      AppLog.info(
        'ports',
        now == _padPort
            ? 'core did NOT move the joystick (still port ${now + 1})'
            : 'joystick now in port ${now + 1}',
      );
      setState(() => _padPort = now);
    });
  }

  /// Asks which drive when there is more than one, then which disk.
  Future<void> _swapDisk() async {
    final int drives = widget.core.floppyCount;
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
    if (path != null) widget.core.insertFloppy(drive, path);
  }

  /// One control: an icon with its name under it.
  ///
  /// The label is not decoration. A tooltip needs a long press, which on a
  /// handheld nobody discovers and which competes with the game for the same
  /// touch -- so an icon-only control is a control whose meaning is a guess.
  /// Guessing wrong here ends a session or moves the joystick out from under
  /// the player, so every one of these says what it is.
  Widget _tool({
    required IconData icon,
    required String label,
    required String tip,
    required VoidCallback onPressed,
    bool active = false,
    int labelLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _showControls();
            onPressed();
          },
          child: SizedBox(
            width: 52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF4040E0)
                        : const Color(0xFF24292E),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: labelLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    color: active ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How a session ended, so the launcher knows where to put the user back.
enum EmulatorExit {
  /// Snapshot written; the Resume shelf has it.
  paused,

  /// Ended, nothing kept.
  closed,
}

/// The way back into the game, over the dimmed picture.
class _ResumeButton extends StatelessWidget {
  const _ResumeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF21B2030),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.play_arrow, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Resume',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Paused',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A secondary choice on the pause menu: what to do with a stopped machine.
class _MenuChoice extends StatelessWidget {
  const _MenuChoice({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC12151A),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
