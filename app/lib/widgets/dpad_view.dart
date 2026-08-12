import 'package:flutter/material.dart';

/// A digital four-way pad: the alternative to [WobbleJoystick] for people who
/// want to feel the edges of a direction instead of aiming a stick.
///
/// It emits the same `onDirections(up, down, left, right)` shape as the
/// wobble stick, so the emulator screen can swap one for the other without
/// caring which is on screen.
///
/// **Not four separate buttons.** The C64 port is 8-way, and a cross of
/// independent [GestureDetector]s can only ever report the one it was
/// pressed on: a thumb resting between up and right would pick a single
/// winner, which loses diagonals -- and diagonals are how you jump forward
/// in most of the library. Instead the whole pad is one [Listener] that
/// tracks every active pointer and derives directions from where they are
/// relative to the centre, so resting on a corner presses both arms, and
/// sliding from one arm to the next changes direction without lifting off.
///
/// The dead zone is 18% of the radius, matching [WobbleJoystick] so the two
/// feel the same distance from neutral.
class DpadView extends StatefulWidget {
  final void Function(bool up, bool down, bool left, bool right)? onDirections;
  final double size;

  const DpadView({super.key, this.onDirections, this.size = 140});

  @override
  State<DpadView> createState() => _DpadViewState();
}

class _DpadViewState extends State<DpadView> {
  /// Live pointers, by id, in local coordinates. A map rather than a single
  /// offset because a second finger must not cancel the first -- players
  /// hold a direction with one thumb and tap a diagonal with the other.
  final Map<int, Offset> _pointers = {};

  bool _up = false, _down = false, _left = false, _right = false;

  /// Fraction of the radius a pointer must clear before it counts as a
  /// direction at all.
  static const _deadZone = 0.18;

  /// How far off-axis a pointer may be and still press an arm. Lower than
  /// 45 degrees on purpose: it widens the diagonal corners, which are hard
  /// to hold accurately on glass with no tactile edge to find.
  static const _axisThreshold = 0.38;

  void _recompute() {
    final r = widget.size / 2;
    var up = false, down = false, left = false, right = false;

    for (final p in _pointers.values) {
      final dx = (p.dx - r) / r;
      final dy = (p.dy - r) / r;
      if (dx * dx + dy * dy < _deadZone * _deadZone) continue;
      if (dx <= -_axisThreshold) left = true;
      if (dx >= _axisThreshold) right = true;
      if (dy <= -_axisThreshold) up = true;
      if (dy >= _axisThreshold) down = true;
    }

    if (up == _up && down == _down && left == _left && right == _right) return;
    setState(() {
      _up = up;
      _down = down;
      _left = left;
      _right = right;
    });
    widget.onDirections?.call(up, down, left, right);
  }

  void _release(int pointer) {
    _pointers.remove(pointer);
    _recompute();
  }

  @override
  void dispose() {
    // A pad torn down mid-press (quick settings opened, controls hidden,
    // the game exited) would otherwise leave the joystick bit set in the
    // core and the character walking into a wall forever.
    if (_up || _down || _left || _right) {
      widget.onDirections?.call(false, false, false, false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointers[e.pointer] = e.localPosition;
        _recompute();
      },
      onPointerMove: (e) {
        _pointers[e.pointer] = e.localPosition;
        _recompute();
      },
      onPointerUp: (e) => _release(e.pointer),
      onPointerCancel: (e) => _release(e.pointer),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _DpadPainter(
            up: _up,
            down: _down,
            left: _left,
            right: _right,
          ),
        ),
      ),
    );
  }
}

class _DpadPainter extends CustomPainter {
  final bool up, down, left, right;

  const _DpadPainter({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    // Arm width and length as fractions of the pad, chosen so the cross
    // reads as a cross at a glance at thumb size.
    final arm = size.width * 0.30;
    final centre = Offset(r, r);

    final fill = Paint()..color = Colors.white.withValues(alpha: 0.10);
    final pressed = Paint()..color = Colors.tealAccent.withValues(alpha: 0.55);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.35);

    Rect vertical = Rect.fromCenter(
      center: centre,
      width: arm,
      height: size.height * 0.92,
    );
    Rect horizontal = Rect.fromCenter(
      center: centre,
      width: size.width * 0.92,
      height: arm,
    );
    final cross = Path()
      ..addRRect(RRect.fromRectAndRadius(vertical, const Radius.circular(10)))
      ..addRRect(
        RRect.fromRectAndRadius(horizontal, const Radius.circular(10)),
      );

    canvas.drawPath(cross, fill);
    canvas.drawPath(cross, stroke);

    // Highlight only the arms actually held, so a diagonal visibly lights
    // two of them -- the quickest way to see the pad is doing 8-way.
    void arm4(bool on, Rect rect) {
      if (!on) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        pressed,
      );
    }

    final half = size.height * 0.46;
    arm4(up, Rect.fromLTWH(r - arm / 2, r - half, arm, half - arm * 0.2));
    arm4(
      down,
      Rect.fromLTWH(r - arm / 2, r + arm * 0.2, arm, half - arm * 0.2),
    );
    arm4(left, Rect.fromLTWH(r - half, r - arm / 2, half - arm * 0.2, arm));
    arm4(
      right,
      Rect.fromLTWH(r + arm * 0.2, r - arm / 2, half - arm * 0.2, arm),
    );

    // Arrow glyphs, drawn last so they stay visible on a pressed arm.
    final tri = Paint()..color = Colors.white.withValues(alpha: 0.75);
    void arrow(Offset tip, Offset a, Offset b) {
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..close(),
        tri,
      );
    }

    final s = size.width * 0.055;
    final o = size.width * 0.30;
    arrow(
      Offset(r, r - o - s),
      Offset(r - s, r - o + s),
      Offset(r + s, r - o + s),
    );
    arrow(
      Offset(r, r + o + s),
      Offset(r - s, r + o - s),
      Offset(r + s, r + o - s),
    );
    arrow(
      Offset(r - o - s, r),
      Offset(r - o + s, r - s),
      Offset(r - o + s, r + s),
    );
    arrow(
      Offset(r + o + s, r),
      Offset(r + o - s, r - s),
      Offset(r + o - s, r + s),
    );
  }

  @override
  bool shouldRepaint(_DpadPainter old) =>
      old.up != up ||
      old.down != down ||
      old.left != left ||
      old.right != right;
}
