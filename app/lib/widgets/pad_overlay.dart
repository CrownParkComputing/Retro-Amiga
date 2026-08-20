import 'package:flutter/material.dart';

import '../data/pad_layout.dart';
import 'cd32_pad.dart';
import 'pad_key_button.dart';
import 'wobble_joystick.dart';

/// The on-screen pad, laid over the Amiga's picture where the designer put
/// it: a stick, fire buttons (or the CD32 cluster), and any added keys.
///
/// Callback-driven, so it does not care what is underneath -- the in-process
/// core's FFI or the :sdl Activity's channel both fit. The stick and the
/// added direction buttons are combined here, because driving the core from
/// each of them directly would make the last one to move win.
class PadOverlay extends StatefulWidget {
  const PadOverlay({
    super.key,
    required this.layout,
    required this.onDirections,
    required this.onButton,
    required this.onKey,
  });

  final PadLayout layout;
  final void Function(bool up, bool down, bool left, bool right) onDirections;
  final void Function(int button, bool pressed) onButton;
  final void Function(int code, bool pressed) onKey;

  /// UAE4ARM_HOST_JOY_FIRE1 / FIRE2.
  static const int fire1 = 0;
  static const int fire2 = 1;

  @override
  State<PadOverlay> createState() => _PadOverlayState();
}

class _PadOverlayState extends State<PadOverlay> {
  bool _stickUp = false, _stickDown = false, _stickLeft = false, _stickRight = false;
  final Set<PadDirection> _held = <PadDirection>{};
  bool? _sentUp, _sentDown, _sentLeft, _sentRight;

  void _send() {
    final bool up = _stickUp || _held.contains(PadDirection.up);
    final bool down = _stickDown || _held.contains(PadDirection.down);
    final bool left = _stickLeft || _held.contains(PadDirection.left);
    final bool right = _stickRight || _held.contains(PadDirection.right);
    if (up == _sentUp && down == _sentDown && left == _sentLeft && right == _sentRight) {
      return;
    }
    _sentUp = up;
    _sentDown = down;
    _sentLeft = left;
    _sentRight = right;
    widget.onDirections(up, down, left, right);
  }

  void _stickMoved(bool up, bool down, bool left, bool right) {
    _stickUp = up;
    _stickDown = down;
    _stickLeft = left;
    _stickRight = right;
    _send();
  }

  void _buttonDirection(PadDirection d, bool down) {
    if (down) {
      _held.add(d);
    } else {
      _held.remove(d);
    }
    _send();
  }

  @override
  void dispose() {
    // Anything held when the pad disappears would stay held.
    if (_sentUp == true || _sentDown == true || _sentLeft == true || _sentRight == true) {
      widget.onDirections(false, false, false, false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PadLayout layout = widget.layout;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size area = constraints.biggest;
        return Stack(
          children: <Widget>[
            _Placed(
              area: area,
              fraction: layout.stick,
              child: WobbleJoystick(size: 150, onDirections: _stickMoved),
            ),
            _Placed(
              area: area,
              fraction: layout.buttons,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final PadButton button in layout.customButtons) ...<Widget>[
                    PadKeyButton(
                      button: button,
                      onKey: widget.onKey,
                      onDirection: _buttonDirection,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (layout.style == PadStyle.cd32)
                    Cd32Pad(onButton: widget.onButton)
                  else ...<Widget>[
                    _FireButton(
                      label: '2',
                      colour: const Color(0xFF3050DC),
                      onChanged: (bool p) => widget.onButton(PadOverlay.fire2, p),
                    ),
                    const SizedBox(height: 12),
                    _FireButton(
                      label: '1',
                      colour: const Color(0xFFDC3232),
                      onChanged: (bool p) => widget.onButton(PadOverlay.fire1, p),
                    ),
                  ],
                ],
              ),
            ),
            if (layout.style == PadStyle.cd32)
              _Placed(
                area: area,
                fraction: layout.transport,
                child: Cd32Transport(onButton: widget.onButton),
              ),
          ],
        );
      },
    );
  }
}

/// A control at its saved place: the fraction says where its centre goes.
class _Placed extends StatelessWidget {
  const _Placed({required this.area, required this.fraction, required this.child});

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

class _FireButton extends StatefulWidget {
  const _FireButton({required this.label, required this.colour, required this.onChanged});

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
          border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
