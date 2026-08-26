import 'dart:math';

import 'package:flutter/material.dart';

/// A top-down analog-style "wobble" joystick: a circular base with a
/// draggable knob that leans/offsets toward the drag point (clamped to a
/// max travel radius) and springs back to center on release.
///
/// The real C64 joystick port is digital (8-way + center, no true analog),
/// so even though the visuals are analog-style the output is discretized
/// to the same `onDirections(up, down, left, right)` shape [DpadView] used
/// to feed the emulator, including a matching dead zone (18% of the base
/// radius, mirroring DpadView's 18%-of-width dead zone) near the center.
class WobbleJoystick extends StatefulWidget {
  final void Function(bool up, bool down, bool left, bool right)? onDirections;
  final double size;

  const WobbleJoystick({super.key, this.onDirections, this.size = 140});

  @override
  State<WobbleJoystick> createState() => _WobbleJoystickState();
}

class _WobbleJoystickState extends State<WobbleJoystick>
    with SingleTickerProviderStateMixin {
  // Built in initState rather than as a `late final` initialiser. A lazy
  // one is not created until something first touches it -- and if nothing
  // ever does (the player leaves the game without moving the stick, or the
  // touch controls are hidden again) then dispose() is that first touch,
  // which builds an AnimationController against an element that has already
  // been deactivated and trips a framework assertion on the way out.
  late final AnimationController _springController;
  Animation<Offset>? _springAnim;

  /// Where the knob is and whether it is pushed, as something the painter can
  /// watch directly.
  ///
  /// This was widget state, set through setState -- once per touch move while
  /// the stick is being used, and once per display frame for the whole of the
  /// spring-back. Every one of those rebuilt this widget and its subtree to
  /// change two numbers that only the painter reads. On the tablets the store
  /// reviews came from that is a rebuild storm running for exactly as long as
  /// the player is holding a direction, which is to say all the time.
  ///
  /// A notifier handed to CustomPainter.repaint goes straight to the render
  /// object: no rebuild, no layout, just the repaint that was always needed.
  final _KnobState _knob = _KnobState();

  bool _up = false, _down = false, _left = false, _right = false;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    _knob.dispose();
    super.dispose();
  }

  bool get _active => _up || _down || _left || _right;

  void _emit(bool up, bool down, bool left, bool right) {
    if (up == _up && down == _down && left == _left && right == _right) return;
    _up = up;
    _down = down;
    _left = left;
    _right = right;
    _knob.setActive(_active);
    widget.onDirections?.call(_up, _down, _left, _right);
  }

  void _updateFromLocal(Offset local, double radius) {
    _springController.stop();
    final center = Offset(radius, radius);
    var delta = local - center;
    final dist = delta.distance;
    // Knob travel is clamped well inside the base so the ring around it
    // stays visible -- selling the "stick leaning against its base" look.
    final maxTravel = radius * 0.6;
    if (dist > maxTravel) {
      delta = Offset.fromDirection(delta.direction, maxTravel);
    }
    _knob.setOffset(delta);

    final deadZone = radius * 0.18;
    if (dist < deadZone) {
      _emit(false, false, false, false);
      return;
    }

    // Discretize the drag angle into 8 compass sectors (45 degrees each,
    // centered on the cardinal/diagonal directions) -- diagonals report
    // both adjacent flags true, same as DpadView's crossed dead-zone test.
    final degrees = (delta.direction * 180 / pi + 360) % 360;
    final sector = ((degrees + 22.5) / 45).floor() % 8;
    // sector 0 = right, going clockwise (screen y grows downward):
    // 0 right, 1 down-right, 2 down, 3 down-left, 4 left, 5 up-left, 6 up, 7 up-right
    const rightSectors = {0, 1, 7};
    const downSectors = {1, 2, 3};
    const leftSectors = {3, 4, 5};
    const upSectors = {5, 6, 7};
    _emit(
      upSectors.contains(sector),
      downSectors.contains(sector),
      leftSectors.contains(sector),
      rightSectors.contains(sector),
    );
  }

  void _release() {
    final begin = _knob.offset;
    _springAnim = Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(parent: _springController, curve: Curves.elasticOut),
    )..addListener(() => _knob.setOffset(_springAnim!.value));
    _springController
      ..value = 0
      ..forward();
    _emit(false, false, false, false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final radius = constraints.maxWidth / 2;
          return GestureDetector(
            onPanDown: (d) => _updateFromLocal(d.localPosition, radius),
            onPanUpdate: (d) => _updateFromLocal(d.localPosition, radius),
            onPanEnd: (_) => _release(),
            onPanCancel: _release,
            // The stick springs back on an AnimationController, so it
            // repaints at the display's rate for as long as it is moving.
            // Without a boundary that repaint is shared with whatever else
            // is in the same layer -- over a running game, the picture and
            // the status strip -- so every nudge of the stick redrew them
            // too.
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WobblePainter(_knob),
                size: Size(widget.size, widget.size),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The knob's position and whether it is pushed, as a repaint source.
///
/// Notifies only on a real change, so a touch move that lands on the same
/// pixel -- and the tail of a spring-back, which converges -- costs nothing.
class _KnobState extends ChangeNotifier {
  Offset offset = Offset.zero;
  bool active = false;

  void setOffset(Offset next) {
    if (next == offset) return;
    offset = next;
    notifyListeners();
  }

  void setActive(bool next) {
    if (next == active) return;
    active = next;
    notifyListeners();
  }
}

class _WobblePainter extends CustomPainter {
  final _KnobState state;

  const _WobblePainter(this.state) : super(repaint: state);

  Offset get knobOffset => state.offset;
  bool get active => state.active;

  static const _baseFill = Color(0x445F6670);
  static const _baseStroke = Color(0x99D6DADF);
  static const _guideStroke = Color(0x33D6DADF);
  static const _knobFillIdle = Color(0xE0C5CBD3);
  static const _knobFillActive = Color(0xFF34D9C4);
  static const _knobStroke = Color(0xEEFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    final strokeWidth = (size.width * 0.02).clamp(2.0, double.infinity);

    // Base ring.
    canvas.drawCircle(
      center,
      baseRadius - strokeWidth / 2,
      Paint()..color = _baseFill,
    );
    canvas.drawCircle(
      center,
      baseRadius - strokeWidth / 2,
      Paint()
        ..color = _baseStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    // Concentric guide rings so the base reads as an analog stick socket.
    for (final f in [0.35, 0.68]) {
      canvas.drawCircle(
        center,
        baseRadius * f,
        Paint()
          ..color = _guideStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final knobCenter = center + knobOffset;
    final knobRadius = baseRadius * 0.4;

    // Shadow offset opposite the lean, to fake the stick tilting away from
    // its socket toward the drag direction.
    final shadowOffset = -knobOffset * 0.15;
    canvas.drawCircle(
      knobCenter + shadowOffset + const Offset(0, 3),
      knobRadius * 0.95,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    final knobFill = active ? _knobFillActive : _knobFillIdle;
    final highlightAlign = Alignment(
      (-knobOffset.dx / baseRadius).clamp(-1.0, 1.0) * 0.4 - 0.25,
      (-knobOffset.dy / baseRadius).clamp(-1.0, 1.0) * 0.4 - 0.25,
    );
    final gradient = RadialGradient(
      center: highlightAlign,
      radius: 0.95,
      colors: [Colors.white.withValues(alpha: 0.95), knobFill],
    );
    canvas.drawCircle(
      knobCenter,
      knobRadius,
      Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: knobCenter, radius: knobRadius),
        ),
    );
    canvas.drawCircle(
      knobCenter,
      knobRadius,
      Paint()
        ..color = _knobStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.width * 0.012).clamp(1.5, double.infinity),
    );
  }

  @override
  bool shouldRepaint(covariant _WobblePainter old) => old.state != state;
}
