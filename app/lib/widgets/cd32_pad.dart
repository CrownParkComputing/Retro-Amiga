import 'package:flutter/material.dart';

/// The CD32 joypad's four coloured buttons, in the diamond they sit in on the
/// pad: red bottom, blue left, green right, yellow top.
///
/// The transport keys are [Cd32Transport], a separate control. The colours are the
/// point: CD32 games say "press blue", never "press button two", so a pad
/// drawn in grey with numbers on it would be unusable for the games it exists
/// to serve.
///
/// The indices are UAE4ARM_HOST_CD32_* from uae4arm_host.h.
class Cd32Pad extends StatelessWidget {
  const Cd32Pad({super.key, required this.onButton, this.enabled = true});

  /// (button index, pressed).
  final void Function(int button, bool pressed) onButton;

  /// False while the layout is being arranged, so dragging the pad into place
  /// does not fire everything it passes under.
  final bool enabled;

  static const int red = 0;
  static const int blue = 1;
  static const int green = 2;
  static const int yellow = 3;
  static const int play = 4;
  static const int rewind = 5;
  static const int forward = 6;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        children: <Widget>[
          Align(
            alignment: Alignment.topCenter,
            child: _Cd32Button(
              label: 'Y',
              colour: const Color(0xFFD8C43C),
              enabled: enabled,
              onChanged: (bool p) => onButton(yellow, p),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _Cd32Button(
              label: 'B',
              colour: const Color(0xFF3050DC),
              enabled: enabled,
              onChanged: (bool p) => onButton(blue, p),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _Cd32Button(
              label: 'G',
              colour: const Color(0xFF2E9E44),
              enabled: enabled,
              onChanged: (bool p) => onButton(green, p),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Cd32Button(
              label: 'R',
              colour: const Color(0xFFDC3232),
              enabled: enabled,
              onChanged: (bool p) => onButton(red, p),
            ),
          ),
        ],
      ),
    );
  }
}

/// The CD32's transport keys: rewind, play, forward.
///
/// A control of its own rather than part of the pad, so it can be put
/// somewhere your thumb is not. These work the CD, not the game, and losing
/// your place on the soundtrack because a finger strayed off the fire button
/// is not a trade anybody would make.
class Cd32Transport extends StatelessWidget {
  const Cd32Transport({super.key, required this.onButton, this.enabled = true});

  final void Function(int button, bool pressed) onButton;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Cd32Button(
          label: '<<',
          colour: const Color(0xFF5A5A5A),
          size: 36,
          enabled: enabled,
          onChanged: (bool p) => onButton(Cd32Pad.rewind, p),
        ),
        const SizedBox(width: 8),
        _Cd32Button(
          label: '>',
          colour: const Color(0xFF5A5A5A),
          size: 36,
          enabled: enabled,
          onChanged: (bool p) => onButton(Cd32Pad.play, p),
        ),
        const SizedBox(width: 8),
        _Cd32Button(
          label: '>>',
          colour: const Color(0xFF5A5A5A),
          size: 36,
          enabled: enabled,
          onChanged: (bool p) => onButton(Cd32Pad.forward, p),
        ),
      ],
    );
  }
}

class _Cd32Button extends StatefulWidget {
  const _Cd32Button({
    required this.label,
    required this.colour,
    required this.onChanged,
    required this.enabled,
    this.size = 64,
  });

  final String label;
  final Color colour;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final double size;

  @override
  State<_Cd32Button> createState() => _Cd32ButtonState();
}

class _Cd32ButtonState extends State<_Cd32Button> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (!widget.enabled || _pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.onChanged(pressed);
  }

  @override
  void dispose() {
    // Losing the widget mid-press must not leave the button held down.
    if (_pressed) widget.onChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.colour.withValues(alpha: _pressed ? 0.9 : 0.45),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.65),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.size < 50 ? 13 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
