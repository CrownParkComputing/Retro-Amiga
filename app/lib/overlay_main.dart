import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static Future<void> openMenu() => _channel.invokeMethod('openMenu');
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
  @override
  void initState() {
    super.initState();
    OverlayPad.attach();
  }

  @override
  void dispose() {
    OverlayPad.releaseAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          // Joystick, bottom left.
          Positioned(
            left: 16 + safe.left,
            bottom: 16 + safe.bottom,
            child: WobbleJoystick(
              size: 150,
              onDirections: (bool up, bool down, bool left, bool right) {
                OverlayPad.direction(up, down, left, right);
              },
            ),
          ),

          // Fire buttons, bottom right.
          Positioned(
            right: 16 + safe.right,
            bottom: 24 + safe.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
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

          // Menu, top right.
          Positioned(
            right: 12 + safe.right,
            top: 12 + safe.top,
            child: _OverlayIconButton(
              icon: Icons.pause,
              onPressed: OverlayPad.openMenu,
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
  const _OverlayIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

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
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
