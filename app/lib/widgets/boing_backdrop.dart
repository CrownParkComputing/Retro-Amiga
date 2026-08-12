import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The Boing Ball, drawn rather than played back.
///
/// It is a real sphere: a 16 x 8 grid of quads projected orthographically,
/// back faces culled, chequered red and white, spinning about an axis tilted
/// off vertical exactly as the 1984 demo's was. Drawing it means it is crisp
/// at any size and the spin stays tied to real elapsed time, so it does not
/// run at double speed on a 120Hz iPad - which a frame-counted animation
/// would.
///
/// The wireframe room behind it is part of the demo, not decoration: the ball
/// reads as bouncing because the grid gives it somewhere to bounce in.
class BoingBackdrop extends StatefulWidget {
  const BoingBackdrop({super.key, this.opacity = 1.0});

  /// Faded down while the workbench is in use, full while it is idle.
  final double opacity;

  @override
  State<BoingBackdrop> createState() => _BoingBackdropState();
}

class _BoingBackdropState extends State<BoingBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      setState(() => _elapsed = elapsed);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.opacity <= 0) return const SizedBox.expand();
    return Opacity(
      opacity: widget.opacity,
      child: CustomPaint(
        painter: _BoingPainter(_elapsed.inMicroseconds / 1e6),
        size: Size.infinite,
      ),
    );
  }
}

class _BoingPainter extends CustomPainter {
  const _BoingPainter(this.seconds);

  /// Real elapsed seconds, so the motion is wall-clock rather than per-frame.
  final double seconds;

  // The demo's own proportions.
  static const int _longitudes = 16;
  static const int _latitudes = 8;
  static const double _tilt = 17 * math.pi / 180;

  static const Color _red = Color(0xFFE01B24);
  static const Color _white = Color(0xFFF5F5F5);
  static const Color _grid = Color(0xFF3B1E52);
  static const Color _gridLine = Color(0xFF6B3E8F);
  static const Color _shadow = Color(0x552A1440);

  @override
  void paint(Canvas canvas, Size size) {
    _paintRoom(canvas, size);

    final double radius = math.min(size.width, size.height) * 0.16;

    // Horizontal sweep across the room, and a bounce that is fast at the
    // bottom and slow at the top - abs(sin) rather than sin, which is what
    // makes it read as gravity rather than a hover.
    final double sweep = math.sin(seconds * 0.9);
    final double cx = size.width * (0.5 + sweep * 0.32);
    final double floor = size.height * 0.74;
    final double bounce = (math.sin(seconds * 2.4)).abs();
    final double cy = floor - bounce * size.height * 0.34;

    // The shadow is flattened onto the floor and tracks the ball's height, so
    // it shrinks as the ball rises.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + radius * 0.5, floor + radius * 0.55),
        width: radius * (2.1 - bounce * 0.7),
        height: radius * (0.55 - bounce * 0.2),
      ),
      Paint()..color = _shadow,
    );

    // Rolling, not just spinning: for a ball rolling without slipping the
    // rotation angle is proportional to how far it has travelled, not to how
    // long it has been going. Tying it to the sweep rather than to elapsed
    // time is what makes it reverse smoothly at each end instead of snapping
    // to the opposite direction, and makes the surface appear to grip.
    //
    // Negative because of the projection below: increasing the spin moves the
    // face of the ball to the left, so travelling right needs the spin to
    // decrease.
    const double turnsPerSweep = 5.5;
    final double spin = -sweep * turnsPerSweep;
    _paintBall(canvas, Offset(cx, cy), radius, spin);
  }

  void _paintRoom(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _grid);

    final Paint line = Paint()
      ..color = _gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const int columns = 14;
    const int rows = 10;
    for (int i = 0; i <= columns; i++) {
      final double x = size.width * i / columns;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (int i = 0; i <= rows; i++) {
      final double y = size.height * i / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Projects a point on the unit sphere, spun about its own axis and then
  /// tilted, to the screen. Returns the projected offset and the z of the
  /// surface normal, which is the same thing on a unit sphere and is what the
  /// back-face cull tests.
  ({Offset point, double z}) _project(
    double theta,
    double phi,
    double spin,
    Offset centre,
    double radius,
  ) {
    // Spin about the vertical axis.
    final double a = theta + spin;
    double x = math.sin(phi) * math.cos(a);
    double y = math.cos(phi);
    final double z = math.sin(phi) * math.sin(a);

    // Then tilt the whole ball, which is what stops the poles sitting dead
    // centre and gives the demo its look.
    final double xt = x * math.cos(_tilt) - y * math.sin(_tilt);
    final double yt = x * math.sin(_tilt) + y * math.cos(_tilt);
    x = xt;
    y = yt;

    return (
      point: Offset(centre.dx + x * radius, centre.dy - y * radius),
      z: z,
    );
  }

  void _paintBall(Canvas canvas, Offset centre, double radius, double spin) {
    final Paint fill = Paint()..isAntiAlias = true;

    for (int i = 0; i < _longitudes; i++) {
      final double t0 = i * 2 * math.pi / _longitudes;
      final double t1 = (i + 1) * 2 * math.pi / _longitudes;

      for (int j = 0; j < _latitudes; j++) {
        final double p0 = j * math.pi / _latitudes;
        final double p1 = (j + 1) * math.pi / _latitudes;

        final corners = <({Offset point, double z})>[
          _project(t0, p0, spin, centre, radius),
          _project(t1, p0, spin, centre, radius),
          _project(t1, p1, spin, centre, radius),
          _project(t0, p1, spin, centre, radius),
        ];

        // Cull the far side. Without this the pattern on the back shows
        // through and the ball looks flat.
        final double facing =
            corners.map((c) => c.z).reduce((a, b) => a + b) / corners.length;
        if (facing <= 0) continue;

        final Path quad = Path()..moveTo(corners[0].point.dx, corners[0].point.dy);
        for (int k = 1; k < corners.length; k++) {
          quad.lineTo(corners[k].point.dx, corners[k].point.dy);
        }
        quad.close();

        fill.color = (i + j).isEven ? _red : _white;
        canvas.drawPath(quad, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_BoingPainter oldDelegate) =>
      oldDelegate.seconds != seconds;
}
