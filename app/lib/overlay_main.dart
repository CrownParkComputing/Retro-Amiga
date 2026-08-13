import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/pad_layout.dart';
import 'widgets/cd32_pad.dart';
import 'widgets/pad_key_button.dart';
import 'widgets/wobble_joystick.dart';

/// Entry point for the in-game overlay engine.
///
/// This runs in a second Flutter engine hosted by the emulator Activity, above
/// SDL's surface. It must stay transparent: anything opaque here hides the
/// Amiga behind it.
@pragma('vm:entry-point')
void emulatorOverlayMain() {
  runApp(const EmulatorOverlayApp());
}

/// Talks to the emulator Activity, which forwards straight into the emulated
/// joystick through the native pad API.
class OverlayPad {
  static const MethodChannel _channel = MethodChannel('uae4arm2026/overlay');

  /// UAE4ARM_HOST_PAD_JOYSTICK / _CD32 in uae4arm_host.h.
  static const int joystick = 1;
  static const int cd32 = 2;

  /// UAE4ARM_HOST_JOY_FIRE1 / FIRE2.
  static const int fire1 = 0;
  static const int fire2 = 1;

  /// JSEM_MODE for port 1: a plain joystick, or a CD32 pad. The core has to
  /// be told which, or the seven-button pad reports into a port that only
  /// understands two of them.
  static const int modeJoystick = 3;
  static const int modeCd32 = 7;

  static int padFor(PadStyle style) =>
      style == PadStyle.cd32 ? cd32 : joystick;

  static Future<void> attach(int pad) =>
      _channel.invokeMethod('padAttach', <String, Object?>{'pad': pad});

  static Future<void> setPortMode(int mode) =>
      _channel.invokeMethod('portMode', <String, Object?>{'mode': mode});

  static Future<void> direction(
    int pad,
    bool up,
    bool down,
    bool left,
    bool right,
  ) =>
      _channel.invokeMethod('padDirection', <String, Object?>{
        'pad': pad,
        'left': left,
        'right': right,
        'up': up,
        'down': down,
      });

  static Future<void> button(int pad, int button, bool pressed) =>
      _channel.invokeMethod(
        'padButton',
        <String, Object?>{'pad': pad, 'button': button, 'pressed': pressed},
      );

  /// Called when the pad goes away mid-press, so a held direction cannot stick.
  static Future<void> releaseAll(int pad) => _channel.invokeMethod(
    'padReleaseAll',
    <String, Object?>{'pad': pad},
  );

  /// Whether the running config is a CD32, which decides which pad is drawn
  /// before anyone has chosen one.
  static Future<bool> isCd32() async =>
      await _channel.invokeMethod<bool>('isCd32') ?? false;

  /// Whether a real controller is attached.
  static Future<bool> hasGamepad() async =>
      await _channel.invokeMethod<bool>('hasGamepad') ?? false;

  /// Relative mouse motion, in Amiga pixels.
  static Future<void> mouseMove(int dx, int dy) =>
      _channel.invokeMethod('mouseMove', <String, Object?>{
        'dx': dx,
        'dy': dy,
      });

  /// 0 is the left button, 1 the right.
  static Future<void> mouseButton(int button, bool pressed) =>
      _channel.invokeMethod('mouseButton', <String, Object?>{
        'button': button,
        'pressed': pressed,
      });

  /// An Amiga raw key code, for the buttons the player adds themselves.
  static Future<void> sendKey(int code, bool pressed) =>
      _channel.invokeMethod('sendKey', <String, Object?>{
        'code': code,
        'pressed': pressed,
      });

  /// The rest of what a session needs, drawn here rather than by the Activity
  /// so the icons are the same Material set the launcher uses - which is what
  /// the C64 front end does too. The Activity keeps the behaviour; this just
  /// asks for it.
  /// Returns whether the keyboard is now up.
  static Future<bool> toggleKeyboard() async =>
      await _channel.invokeMethod<bool>('toggleKeyboard') ?? false;

  /// Pause leaves the game and goes back to the workbench.
  ///
  /// Pausing to sit and look at a frozen game is not what anyone wants the
  /// button for - they want to stop playing. The Activity writes a save state
  /// on the way out, so Resume brings the game back exactly here, which makes
  /// this a pause in the only sense that matters.
  static Future<void> pauseToWorkbench() =>
      _channel.invokeMethod('pauseToWorkbench');

  /// How many floppy drives the running machine has, so the swap button knows
  /// whether it has to ask which one.
  static Future<int> floppyCount() async =>
      await _channel.invokeMethod<int>('floppyCount') ?? 1;

  /// [drive] 0 is DF0, 1 is DF1, and so on. Swapping mid-game is what a
  /// multi-disk game needs and the reason this is on the strip.
  static Future<void> insertDisk(int drive) =>
      _channel.invokeMethod('insertDisk', <String, Object?>{'drive': drive});

  /// The layout lives in the Activity's preferences rather than in this
  /// engine: the overlay engine is built by hand and has no plugins
  /// registered, so shared_preferences is not available to it.
  static Future<String?> loadLayout() async =>
      _channel.invokeMethod<String>('layoutLoad');

  static Future<void> saveLayout(String json) =>
      _channel.invokeMethod('layoutSave', <String, Object?>{'layout': json});
}

class EmulatorOverlayApp extends StatelessWidget {
  const EmulatorOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      // Transparent all the way down: the emulator is what shows through.
      color: Color(0x00000000),
      home: EmulatorOverlay(),
    );
  }
}

class EmulatorOverlay extends StatefulWidget {
  const EmulatorOverlay({super.key});

  @override
  State<EmulatorOverlay> createState() => _EmulatorOverlayState();
}

class _EmulatorOverlayState extends State<EmulatorOverlay> {
  PadLayout _layout = PadLayout.defaults;
  /// The drawn pad starts hidden when a real controller is attached: it would
  /// be sitting over the game covering a screen nobody needs to touch. It is
  /// a DEFAULT, not a rule - the pad icon still turns it on, which matters on
  /// a handheld, where the built-in controller is always "attached" and a
  /// player may still want a button the pad has and the handheld does not.
  bool _padVisible = true;

  /// The mouse, for Workbench and the games that want one - and for AGS,
  /// where the menu is a pointer and a click. A mode rather than a second
  /// control: the whole screen becomes the trackpad, which is the only way a
  /// pointer is usable on a phone.
  bool _mouseMode = false;

  /// The strip fades out when it has been left alone, so the game is not
  /// playing behind a column of icons all session. Any touch brings it back.
  bool _stripVisible = true;
  Timer? _stripTimer;
  static const Duration _stripLinger = Duration(seconds: 3);

  /// The on-screen keyboard covers the bottom of the screen, which is where
  /// the controls are. Drawing a joystick over the letters it is standing on
  /// makes both unusable, so the pad steps aside while the keyboard is up.
  bool _keyboardUp = false;

  /// What the stick is saying, kept apart from what the added direction
  /// buttons are saying so the two can be combined. Driving the core from
  /// each of them directly would make the last one to move win, and holding
  /// an added UP button would cancel the stick.
  bool _stickUp = false;
  bool _stickDown = false;
  bool _stickLeft = false;
  bool _stickRight = false;
  final Set<PadDirection> _heldButtons = <PadDirection>{};

  int get _pad => OverlayPad.padFor(_layout.style);

  @override
  void initState() {
    super.initState();
    _loadLayout();
    _checkGamepad();
    _touched();
  }

  Future<void> _checkGamepad() async {
    final bool pad = await OverlayPad.hasGamepad();
    if (mounted && pad) setState(() => _padVisible = false);
  }

  Future<void> _loadLayout() async {
    // The saved layout wins; with none, a CD32 config gets the CD32 pad,
    // because a CD32 game asking for the blue button on a two-button stick
    // is unplayable and the machine already knows which it is.
    final String? saved = await OverlayPad.loadLayout();
    final bool cd32 = saved == null ? await OverlayPad.isCd32() : false;
    final PadLayout layout = PadLayout.decode(
      saved,
      fallbackStyle: cd32 ? PadStyle.cd32 : PadStyle.joystick,
    );
    if (!mounted) return;
    setState(() => _layout = layout);
    _attach();
  }

  /// Registers the pad the layout asks for and tells port 1 what it is.
  void _attach() {
    OverlayPad.attach(_pad);
    OverlayPad.setPortMode(_layout.style == PadStyle.cd32
        ? OverlayPad.modeCd32
        : OverlayPad.modeJoystick);
  }

  /// Shows the strip and starts its countdown again.
  void _touched() {
    _stripTimer?.cancel();
    _stripTimer = Timer(_stripLinger, () {
      if (mounted) setState(() => _stripVisible = false);
    });
    if (!_stripVisible && mounted) setState(() => _stripVisible = true);
  }

  @override
  void dispose() {
    _stripTimer?.cancel();
    OverlayPad.releaseAll(_pad);
    super.dispose();
  }

  void _sendDirections() {
    OverlayPad.direction(
      _pad,
      _stickUp || _heldButtons.contains(PadDirection.up),
      _stickDown || _heldButtons.contains(PadDirection.down),
      _stickLeft || _heldButtons.contains(PadDirection.left),
      _stickRight || _heldButtons.contains(PadDirection.right),
    );
  }

  void _stickMoved(bool up, bool down, bool left, bool right) {
    _stickUp = up;
    _stickDown = down;
    _stickLeft = left;
    _stickRight = right;
    _sendDirections();
  }

  void _buttonDirection(PadDirection direction, bool down) {
    if (down) {
      _heldButtons.add(direction);
    } else {
      _heldButtons.remove(direction);
    }
    _sendDirections();
  }

  /// One swap button for however many drives there are.
  ///
  /// With a single drive it goes straight to the file picker, because asking
  /// "which drive?" when there is one is just a tap in the way. With more it
  /// asks first - a game that wants disk two mid-level cannot be served by a
  /// button hard-wired to DF0.
  Future<void> _swapDisk() async {
    final int drives = await OverlayPad.floppyCount();
    if (drives <= 1) {
      await OverlayPad.insertDisk(0);
      return;
    }
    if (!mounted) return;
    final int? drive = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        backgroundColor: const Color(0xFF141A1F),
        title: const Text(
          'Swap disk in',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        children: <Widget>[
          for (int i = 0; i < drives; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(i),
              child: Text(
                'DF$i',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
    if (drive != null) await OverlayPad.insertDisk(drive);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        // Watch only - this must not consume anything, or the pad below it
        // would stop working.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touched(),
        child: Stack(
        children: <Widget>[
          // The trackpad, when the mouse is on. Underneath the controls, so
          // the stick and the strip take their own touches first and this
          // gets the rest of the screen.
          if (_mouseMode) const Positioned.fill(child: _TouchMouse()),
          // The controls, where the designer in Settings put them.
          // LayoutBuilder because the saved positions are fractions and can
          // only become pixels once the play area has a size.
          if (_padVisible && !_keyboardUp)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size area = constraints.biggest;
                  return Stack(
                    children: <Widget>[
                      _Placed(
                        area: area,
                        fraction: _layout.stick,
                        child: WobbleJoystick(
                          size: 150,
                          onDirections: _stickMoved,
                        ),
                      ),
                      _Placed(
                        area: area,
                        fraction: _layout.buttons,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            // Added buttons sit above the pad rather than
                            // replacing anything on it.
                            for (final PadButton button
                                in _layout.customButtons) ...<Widget>[
                              PadKeyButton(
                                button: button,
                                onKey: OverlayPad.sendKey,
                                onDirection: _buttonDirection,
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_layout.style == PadStyle.cd32)
                              Cd32Pad(
                                onButton: (int button, bool pressed) =>
                                    OverlayPad.button(_pad, button, pressed),
                              )
                            else ...<Widget>[
                              _FireButton(
                                label: '2',
                                colour: const Color(0xFF3050DC),
                                onChanged: (bool pressed) => OverlayPad.button(
                                    _pad, OverlayPad.fire2, pressed),
                              ),
                              const SizedBox(height: 12),
                              _FireButton(
                                label: '1',
                                colour: const Color(0xFFDC3232),
                                onChanged: (bool pressed) => OverlayPad.button(
                                    _pad, OverlayPad.fire1, pressed),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_layout.style == PadStyle.cd32)
                        _Placed(
                          area: area,
                          fraction: _layout.transport,
                          child: Cd32Transport(
                            onButton: (int button, bool pressed) =>
                                OverlayPad.button(_pad, button, pressed),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

          // The session strip, top right. Toggles only - nothing here opens a
          // menu, and each icon says what it does.
          Positioned(
            right: 12 + safe.right,
            top: 12 + safe.top,
            child: AnimatedOpacity(
              opacity: _stripVisible ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_stripVisible,
                child: Column(
                  children: <Widget>[
                // Pause goes back to the workbench, saving where you were.
                _OverlayIconButton(
                  icon: Icons.pause,
                  onPressed: OverlayPad.pauseToWorkbench,
                ),
                const SizedBox(height: 10),
                _OverlayIconButton(
                  icon: Icons.videogame_asset,
                  active: _padVisible,
                  onPressed: () {
                    setState(() => _padVisible = !_padVisible);
                    // Hiding the pad while a direction is held would leave it
                    // held for the rest of the game.
                    if (!_padVisible) {
                      _stickMoved(false, false, false, false);
                      _heldButtons.clear();
                      OverlayPad.releaseAll(_pad);
                    }
                  },
                ),
                const SizedBox(height: 10),
                // The mouse. Beside the keyboard because it is the other
                // half of the same thing: what Workbench, and AGS, are driven
                // with.
                _OverlayIconButton(
                  icon: Icons.mouse,
                  active: _mouseMode,
                  onPressed: () {
                    setState(() => _mouseMode = !_mouseMode);
                    // Leaving the mode with a button held would leave the
                    // Amiga holding it.
                    if (!_mouseMode) {
                      OverlayPad.mouseButton(0, false);
                      OverlayPad.mouseButton(1, false);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _OverlayIconButton(
                  icon: Icons.keyboard,
                  active: _keyboardUp,
                  onPressed: () async {
                    final bool up = await OverlayPad.toggleKeyboard();
                    if (!mounted) return;
                    setState(() => _keyboardUp = up);
                    // Anything held when the pad disappears would stay held.
                    if (up) {
                      _stickMoved(false, false, false, false);
                      _heldButtons.clear();
                      OverlayPad.releaseAll(_pad);
                    }
                  },
                ),
                const SizedBox(height: 10),
                // One swap for every drive: it asks which when there is more
                // than one.
                _OverlayIconButton(
                  icon: Icons.swap_horiz,
                  onPressed: _swapDisk,
                ),
                // No arrange button: the pad is designed in Settings, where
                // a game is not running underneath the fiddling.
                  ],
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// A control at its saved place: the fraction says where its centre goes.
class _Placed extends StatelessWidget {
  const _Placed({
    required this.area,
    required this.fraction,
    required this.child,
  });

  final Size area;
  final Offset2 fraction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: fraction.dx * area.width,
      top: fraction.dy * area.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: child,
      ),
    );
  }
}

/// The screen as a trackpad.
///
/// Relative, not absolute: the Amiga has no idea where a finger is on a host
/// screen, and jumping the pointer to wherever you touched would fight
/// whatever position the guest believes in. So a drag pushes the pointer the
/// way the finger went, a tap is a left click, and two fingers are a right
/// click - the arrangement every trackpad has taught everybody already.
class _TouchMouse extends StatefulWidget {
  const _TouchMouse();

  @override
  State<_TouchMouse> createState() => _TouchMouseState();
}

class _TouchMouseState extends State<_TouchMouse> {
  /// Fingers down, so a second one can mean the right button.
  int _pointers = 0;

  /// Whether this gesture has moved far enough to be a drag rather than a tap.
  bool _moved = false;

  /// Pointer travel per screen point. Above 1 so crossing a Workbench screen
  /// does not need three swipes.
  static const double _speed = 1.6;

  /// Leftovers below a whole pixel, kept rather than thrown away: a slow drag
  /// is a long run of sub-pixel deltas, and rounding each one to zero would
  /// make the pointer refuse to move at all.
  double _restX = 0;
  double _restY = 0;

  void _move(Offset delta) {
    _restX += delta.dx * _speed;
    _restY += delta.dy * _speed;
    final int dx = _restX.truncate();
    final int dy = _restY.truncate();
    if (dx == 0 && dy == 0) return;
    _restX -= dx;
    _restY -= dy;
    OverlayPad.mouseMove(dx, dy);
  }

  Future<void> _click(int button) async {
    await OverlayPad.mouseButton(button, true);
    // Long enough for the guest to see a press and a release as a click; the
    // Amiga polls its mouse, so a press and release in the same frame can be
    // missed entirely.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await OverlayPad.mouseButton(button, false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent event) {
        _pointers++;
        if (_pointers == 1) _moved = false;
      },
      onPointerMove: (PointerMoveEvent event) {
        if (event.delta.distance > 0.5) _moved = true;
        _move(event.delta);
      },
      onPointerUp: (PointerUpEvent event) {
        final int fingers = _pointers;
        _pointers = (_pointers - 1).clamp(0, 10);
        if (_moved) return;
        _click(fingers >= 2 ? 1 : 0);
      },
      onPointerCancel: (_) => _pointers = (_pointers - 1).clamp(0, 10),
    );
  }
}

class _FireButton extends StatefulWidget {
  const _FireButton({
    required this.label,
    required this.colour,
    required this.onChanged,
  });

  final String label;
  final Color colour;
  final ValueChanged<bool> onChanged;

  @override
  State<_FireButton> createState() => _FireButtonState();
}

class _FireButtonState extends State<_FireButton> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.onChanged(pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.colour.withValues(alpha: _pressed ? 0.85 : 0.45),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.65),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;

  /// Drawn lit when the thing it controls is on, so a toggle says which way
  /// it is rather than only what it does.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(
            color: active
                ? Colors.tealAccent
                : Colors.white.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          icon,
          color: active ? Colors.tealAccent : Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
