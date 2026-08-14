import 'package:flutter/material.dart';

import '../data/pad_layout.dart';

/// An on-screen button the player added, bound to an Amiga key or a joystick
/// direction.
///
/// Key presses go straight out as raw Amiga key codes. Direction presses do
/// not: they report upward so the overlay can combine them with the stick,
/// because two things driving the same joystick independently means the last
/// one to move wins, and holding this button would cancel the stick.
class PadKeyButton extends StatefulWidget {
  const PadKeyButton({
    super.key,
    required this.button,
    required this.onKey,
    required this.onDirection,
    this.onRemove,
    this.enabled = true,
    this.size = 52,
  });

  final PadButton button;

  /// (raw Amiga key code, pressed).
  final void Function(int code, bool pressed) onKey;

  final void Function(PadDirection direction, bool down) onDirection;

  /// Shown as a delete badge while the layout is being arranged.
  final VoidCallback? onRemove;

  /// False while arranging, so dragging the cluster into place does not press
  /// every button it passes over.
  final bool enabled;

  final double size;

  @override
  State<PadKeyButton> createState() => _PadKeyButtonState();
}

class _PadKeyButtonState extends State<PadKeyButton> {
  bool _pressed = false;

  void _send(bool down) {
    final PadButton button = widget.button;
    if (button.isDirection) {
      widget.onDirection(button.direction!, down);
    } else {
      widget.onKey(button.key!.code, down);
    }
  }

  void _down() {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    _send(true);
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _send(false);
  }

  @override
  void dispose() {
    // A button removed while held must not leave the key down in the emulated
    // matrix, or the direction latched on.
    if (_pressed) _send(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget face = GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: Container(
        constraints: BoxConstraints(minWidth: widget.size),
        height: widget.size,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size / 2),
          color: _pressed
              ? Colors.tealAccent.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.22),
          border: Border.all(
            color: _pressed
                ? Colors.white
                : Colors.white.withValues(alpha: 0.6),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.button.label,
          maxLines: 1,
          style: TextStyle(
            color: _pressed ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (widget.onRemove == null) return face;

    // The badge sits INSIDE the button's box, in room made for it, rather
    // than hanging off the corner. A widget drawn outside its parent's bounds
    // still paints but is not hit-tested, which is why the delete badge could
    // be seen and not tapped.
    return Stack(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 11, right: 11),
          child: face,
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: widget.onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
