import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/amiga_keys.dart';
import 'data/pad_layout.dart';
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

  /// Matches UAE4ARM_HOST_PAD_JOYSTICK in uae4arm_host.h.
  static const int joystick = 1;

  /// UAE4ARM_HOST_JOY_FIRE1 / FIRE2.
  static const int fire1 = 0;
  static const int fire2 = 1;

  static Future<void> attach() =>
      _channel.invokeMethod('padAttach', <String, Object?>{'pad': joystick});

  static Future<void> direction(bool up, bool down, bool left, bool right) =>
      _channel.invokeMethod('padDirection', <String, Object?>{
        'pad': joystick,
        'left': left,
        'right': right,
        'up': up,
        'down': down,
      });

  static Future<void> button(int button, bool pressed) => _channel.invokeMethod(
    'padButton',
    <String, Object?>{'pad': joystick, 'button': button, 'pressed': pressed},
  );

  /// Called when the pad goes away mid-press, so a held direction cannot stick.
  static Future<void> releaseAll() => _channel.invokeMethod(
    'padReleaseAll',
    <String, Object?>{'pad': joystick},
  );

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
  static Future<void> toggleKeyboard() =>
      _channel.invokeMethod('toggleKeyboard');

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
  bool _editing = false;
  bool _padVisible = true;

  /// What the stick is saying, kept apart from what the added direction
  /// buttons are saying so the two can be combined. Driving the core from
  /// each of them directly would make the last one to move win, and holding
  /// an added UP button would cancel the stick.
  bool _stickUp = false;
  bool _stickDown = false;
  bool _stickLeft = false;
  bool _stickRight = false;
  final Set<PadDirection> _heldButtons = <PadDirection>{};

  @override
  void initState() {
    super.initState();
    OverlayPad.attach();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final PadLayout layout = PadLayout.decode(await OverlayPad.loadLayout());
    if (mounted) setState(() => _layout = layout);
  }

  @override
  void dispose() {
    OverlayPad.releaseAll();
    super.dispose();
  }

  void _sendDirections() {
    OverlayPad.direction(
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

  Future<void> _move(bool stick, Offset2 to) async {
    setState(() {
      _layout = stick
          ? _layout.copyWith(stick: to)
          : _layout.copyWith(buttons: to);
    });
  }

  Future<void> _commit() => OverlayPad.saveLayout(_layout.encode());

  Future<void> _addButton() async {
    final PadButton? button = await showPadButtonPicker(context);
    if (button == null) return;
    // Adding the same key twice would stack two identical buttons on top of
    // each other, which looks like the tap did nothing.
    if (_layout.customButtons.any((PadButton b) => b.id == button.id)) return;
    setState(() {
      _layout = _layout.copyWith(
        customButtons: <PadButton>[..._layout.customButtons, button],
      );
    });
    await _commit();
  }

  Future<void> _removeButton(PadButton button) async {
    setState(() {
      _layout = _layout.copyWith(
        customButtons: _layout.customButtons
            .where((PadButton b) => b.id != button.id)
            .toList(),
      );
    });
    await _commit();
  }

  Future<void> _reset() async {
    setState(() => _layout = PadLayout.defaults);
    await _commit();
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
      body: Stack(
        children: <Widget>[
          // The controls, wherever the player has put them. LayoutBuilder
          // because the saved positions are fractions and can only become
          // pixels once the play area has a size.
          if (_padVisible)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size area = constraints.biggest;
                  return Stack(
                    children: <Widget>[
                      _MovableControl(
                        area: area,
                        fraction: _layout.stick,
                        editing: _editing,
                        label: 'Joystick',
                        onMoved: (Offset2 to) => _move(true, to),
                        onMoveEnd: _commit,
                        child: WobbleJoystick(
                          size: 150,
                          onDirections: _stickMoved,
                        ),
                      ),
                      _MovableControl(
                        area: area,
                        fraction: _layout.buttons,
                        editing: _editing,
                        label: 'Buttons',
                        onMoved: (Offset2 to) => _move(false, to),
                        onMoveEnd: _commit,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            // Added buttons sit above fire rather than
                            // replacing it.
                            for (final PadButton button
                                in _layout.customButtons) ...<Widget>[
                              PadKeyButton(
                                button: button,
                                onKey: OverlayPad.sendKey,
                                onDirection: _buttonDirection,
                                onRemove:
                                    _editing ? () => _removeButton(button) : null,
                              ),
                              const SizedBox(height: 8),
                            ],
                            _FireButton(
                              label: '2',
                              colour: const Color(0xFF3050DC),
                              onChanged: (bool pressed) =>
                                  OverlayPad.button(OverlayPad.fire2, pressed),
                            ),
                            const SizedBox(height: 12),
                            _FireButton(
                              label: '1',
                              colour: const Color(0xFFDC3232),
                              onChanged: (bool pressed) =>
                                  OverlayPad.button(OverlayPad.fire1, pressed),
                            ),
                          ],
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
                      OverlayPad.releaseAll();
                    }
                  },
                ),
                const SizedBox(height: 10),
                _OverlayIconButton(
                  icon: Icons.keyboard,
                  onPressed: OverlayPad.toggleKeyboard,
                ),
                const SizedBox(height: 10),
                // One swap for every drive: it asks which when there is more
                // than one.
                _OverlayIconButton(
                  icon: Icons.swap_horiz,
                  onPressed: _swapDisk,
                ),
                const SizedBox(height: 10),
                // Arrange mode, the same open_with/check pair the C64 front
                // end uses.
                _OverlayIconButton(
                  icon: _editing ? Icons.check : Icons.open_with,
                  active: _editing,
                  onPressed: () {
                    setState(() => _editing = !_editing);
                    if (!_editing) _commit();
                  },
                ),
              ],
            ),
          ),

          // Says what mode you are in and how to leave it. Without this the
          // controls just stop working and grow a border, which reads as a
          // bug rather than a mode.
          if (_editing)
            Positioned(
              left: 0,
              right: 0,
              top: 12 + safe.top,
              child: Center(child: _EditBar(onAdd: _addButton, onReset: _reset)),
            ),
        ],
      ),
    );
  }
}

/// A control the player can drag while the layout is being arranged.
class _MovableControl extends StatelessWidget {
  const _MovableControl({
    required this.area,
    required this.fraction,
    required this.editing,
    required this.label,
    required this.onMoved,
    required this.onMoveEnd,
    required this.child,
  });

  final Size area;
  final Offset2 fraction;
  final bool editing;
  final String label;
  final ValueChanged<Offset2> onMoved;
  final VoidCallback onMoveEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: fraction.dx * area.width,
      top: fraction.dy * area.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: editing
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails d) {
                  if (area.width == 0 || area.height == 0) return;
                  onMoved(fraction.shifted(
                    d.delta.dx / area.width,
                    d.delta.dy / area.height,
                  ));
                },
                onPanEnd: (_) => onMoveEnd(),
                child: _chrome(child),
              )
            : child,
      ),
    );
  }

  Widget _chrome(Widget inner) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.tealAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.open_with, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Absorbed so dragging the stick moves it rather than playing.
          AbsorbPointer(child: inner),
        ],
      ),
    );
  }
}

class _EditBar extends StatelessWidget {
  const _EditBar({required this.onAdd, required this.onReset});

  final VoidCallback onAdd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.tealAccent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Drag the controls where you want them',
            style: TextStyle(
              color: Colors.tealAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 14),
          // Adding a button belongs in the mode where you are already
          // arranging them: you add one and then want to put it somewhere.
          GestureDetector(
            onTap: onAdd,
            child: const Text(
              '+ ADD BUTTON',
              style: TextStyle(
                color: Colors.tealAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: onReset,
            child: const Text(
              'RESET',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
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

/// Modal that asks what a new button should do.
///
/// Directions come first because they are four options against sixty, and
/// because "UP to jump" is the commonest reason to add a button at all.
Future<PadButton?> showPadButtonPicker(BuildContext context) {
  return showDialog<PadButton>(
    context: context,
    builder: (BuildContext context) => Dialog(
      backgroundColor: const Color(0xFF141A1F),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Choose what the new button does',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  const _PickerHeading('JOYSTICK DIRECTION'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final PadDirection direction in PadDirection.values)
                        _PickerChip(
                          label: direction.label,
                          onTap: () => Navigator.of(context)
                              .pop(PadButton.direction(direction)),
                        ),
                    ],
                  ),
                  for (final MapEntry<String, List<AmigaKey>> group
                      in AmigaKeys.groups.entries) ...<Widget>[
                    _PickerHeading(group.key.toUpperCase()),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final AmigaKey key in group.value)
                          _PickerChip(
                            label: key.label,
                            onTap: () =>
                                Navigator.of(context).pop(PadButton.key(key)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 8),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickerHeading extends StatelessWidget {
  const _PickerHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF3D4652)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: Text(label),
    );
  }
}
