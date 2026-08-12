import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The backdrop demo: copper bars, the Boing Ball, and a sine scroller.
///
/// The three things an Amiga demo did that nothing else could, drawn rather
/// than played back:
///
///  * Copper bars. The copper changed video registers mid-scanline, so a
///    machine with 32 colours on screen could show a different one on every
///    line. Here that is a per-line gradient, animated the way the copper
///    lists were.
///  * The ball. A real sphere - a 16 x 8 quad grid, back faces culled, on a
///    tilted axis - which rolls rather than spins: the rotation is tied to how
///    far it has travelled, not to how long it has been going, so it reverses
///    smoothly at each end and the surface appears to grip.
///  * The scroller. Sine-warped text along the bottom, because every demo had
///    one.
///
/// Everything is driven from real elapsed seconds, so it runs at the same
/// speed on a 120Hz iPad as on a 60Hz handheld.
class BoingBackdrop extends StatefulWidget {
  const BoingBackdrop({super.key, this.opacity = 1.0, this.scrollText});

  /// Faded down while the workbench is in use, full while it is idle.
  final double opacity;

  /// What the scroller says. Null uses the built-in greeting.
  final String? scrollText;

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
        painter: _BoingPainter(
          seconds: _elapsed.inMicroseconds / 1e6,
          text: widget.scrollText ?? _BoingPainter.defaultText,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _BoingPainter extends CustomPainter {
  _BoingPainter({required this.seconds, required this.text});

  /// Real elapsed seconds, so the motion is wall-clock rather than per-frame.
  final double seconds;
  final String text;

  static const String defaultText =
      'AMIGA-RETRO  ***  KICKSTART YOUR MEMORY  ***  '
      'ONE FRONT END, EVERY MACHINE: A500 A600 A1200 A3000 A4000 CD32 CDTV  '
      '***  PROTRACKER PLAYER INSIDE, FOUR CHANNELS AS INTENDED  ***  '
      'GREETINGS TO EVERYONE STILL BOOTING A 68000  ***  '
      'WRAP  ';

  // The demo's own proportions.
  static const int _longitudes = 16;
  static const int _latitudes = 8;
  static const double _tilt = 17 * math.pi / 180;

  static const Color _red = Color(0xFFE01B24);
  static const Color _white = Color(0xFFF5F5F5);
  static const Color _backdrop = Color(0xFF07040E);
  static const Color _gridLine = Color(0x337C4DA8);
  static const Color _shadow = Color(0x44160A26);

  /// Copper bars cycle through these. Period palette: saturated, and never
  /// more than a handful at once.
  static const List<Color> _copper = <Color>[
    Color(0xFF2B6CFF),
    Color(0xFF00C2FF),
    Color(0xFF00E28A),
    Color(0xFFFFD400),
    Color(0xFFFF6A00),
    Color(0xFFE01B24),
    Color(0xFF9B30FF),
  ];

  /// One TextPainter per glyph, laid out once and reused every frame. Laying
  /// out the string per frame would be the expensive part of a scroller.
  static final Map<String, TextPainter> _glyphs = <String, TextPainter>{};

  static TextPainter _glyph(String character) {
    return _glyphs.putIfAbsent(character, () {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: character,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: Color(0xFFFFD400),
            shadows: <Shadow>[
              Shadow(color: Color(0xFFE01B24), offset: Offset(0, 2)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _backdrop);
    _paintCopperBars(canvas, size);
    _paintFloor(canvas, size);

    final double radius = math.min(size.width, size.height) * 0.15;

    // The whole screen is the room. The ball travels the full width, and
    // bounces from just under the top to just above the bottom, staying a
    // radius inside on every side so it never clips off.
    //
    // The sweep is a triangle wave, not a sine: a sine slows to a stop at each
    // wall, so the chequer wound down to nothing and unwound again, which
    // reads as the texture snapping back. A ball crossing a room travels at
    // one speed and reverses when it hits something, and that is what a
    // triangle gives - constant speed, so constant roll, with the direction
    // flipping at the wall.
    final double travel = size.width - radius * 2;
    const double crossingsPerSecond = 0.22;
    final double phase = (seconds * crossingsPerSecond * 2) % 2.0;
    final double sweep = phase < 1 ? phase : 2 - phase; // 0..1..0
    final double cx = radius + sweep * travel;

    final double top = radius + size.height * 0.04;
    final double floor = size.height - radius - size.height * 0.10;
    // abs(sin) rather than sin: fast at the bottom, slow at the top, which is
    // what reads as gravity rather than a hover.
    final double bounce = math.sin(seconds * 1.9).abs();
    final double cy = floor - bounce * (floor - top);

    // The shadow flattens onto the floor and shrinks as the ball rises.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + radius * 0.35, floor + radius * 0.75),
        width: radius * (2.0 - bounce * 0.8),
        height: radius * (0.5 - bounce * 0.2),
      ),
      Paint()..color = _shadow,
    );

    // Rolling without slipping: the rotation angle follows distance
    // travelled, which the triangle sweep already is. Negative because
    // increasing the spin moves the face of the ball left, so travelling right
    // needs it to decrease.
    const double turnsPerCrossing = 8.0;
    _paintBall(canvas, Offset(cx, cy), radius, -sweep * turnsPerCrossing);

    _paintScroller(canvas, size);
  }

  /// Horizontal bands whose colour changes down the screen and drifts with
  /// time, the way a copper list did.
  void _paintCopperBars(Canvas canvas, Size size) {
    const int bars = 5;
    final double barHeight = size.height * 0.085;

    for (int b = 0; b < bars; b++) {
      // Each bar rides its own slow sine, offset so they cross rather than
      // move as a block.
      final double phase = seconds * 0.35 + b * 1.7;
      final double centre =
          size.height * (0.5 + 0.42 * math.sin(phase));
      final Color colour = _copper[b % _copper.length];

      final Rect rect = Rect.fromCenter(
        center: Offset(size.width / 2, centre),
        width: size.width,
        height: barHeight,
      );
      // Bright in the middle, dark at the edges: a bar was a ramp of shades
      // of one colour, not a flat block.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colour.withValues(alpha: 0.0),
              colour.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.35),
              colour.withValues(alpha: 0.55),
              colour.withValues(alpha: 0.0),
            ],
            stops: const <double>[0.0, 0.32, 0.5, 0.68, 1.0],
          ).createShader(rect),
      );
    }
  }

  /// A receding grid along the bottom, so the ball has something to bounce on.
  void _paintFloor(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = _gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final double horizon = size.height * 0.62;
    const int columns = 16;
    for (int i = 0; i <= columns; i++) {
      final double x = size.width * i / columns;
      // Converge towards the centre at the horizon, which is what makes it
      // read as a floor rather than a wall.
      final double top = size.width / 2 + (x - size.width / 2) * 0.35;
      canvas.drawLine(Offset(top, horizon), Offset(x, size.height), line);
    }
    const int rows = 7;
    for (int i = 0; i <= rows; i++) {
      // Spaced by a square so the rows bunch up towards the horizon.
      final double t = math.pow(i / rows, 2.0).toDouble();
      final double y = horizon + (size.height - horizon) * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Projects a point on the unit sphere, spun about its own axis and then
  /// tilted. The returned z is the surface normal's, which on a unit sphere is
  /// the same thing, and is what the back-face cull tests.
  ({Offset point, double z}) _project(
    double theta,
    double phi,
    double spin,
    Offset centre,
    double radius,
  ) {
    final double a = theta + spin;
    double x = math.sin(phi) * math.cos(a);
    double y = math.cos(phi);
    final double z = math.sin(phi) * math.sin(a);

    final double xt = x * math.cos(_tilt) - y * math.sin(_tilt);
    final double yt = x * math.sin(_tilt) + y * math.cos(_tilt);
    x = xt;
    y = yt;

    return (point: Offset(centre.dx + x * radius, centre.dy - y * radius), z: z);
  }

  void _paintBall(Canvas canvas, Offset centre, double radius, double spin) {
    final Paint fill = Paint()..isAntiAlias = true;

    for (int i = 0; i < _longitudes; i++) {
      final double t0 = i * 2 * math.pi / _longitudes;
      final double t1 = (i + 1) * 2 * math.pi / _longitudes;

      for (int j = 0; j < _latitudes; j++) {
        final double p0 = j * math.pi / _latitudes;
        final double p1 = (j + 1) * math.pi / _latitudes;

        final List<({Offset point, double z})> corners =
            <({Offset point, double z})>[
          _project(t0, p0, spin, centre, radius),
          _project(t1, p0, spin, centre, radius),
          _project(t1, p1, spin, centre, radius),
          _project(t0, p1, spin, centre, radius),
        ];

        // Cull the far side, or the pattern on the back shows through and the
        // ball looks flat.
        double facing = 0;
        for (final ({Offset point, double z}) c in corners) {
          facing += c.z;
        }
        if (facing <= 0) continue;

        final Path quad = Path()
          ..moveTo(corners[0].point.dx, corners[0].point.dy);
        for (int k = 1; k < corners.length; k++) {
          quad.lineTo(corners[k].point.dx, corners[k].point.dy);
        }
        quad.close();

        fill.color = (i + j).isEven ? _red : _white;
        canvas.drawPath(quad, fill);
      }
    }
  }

  /// Text running right to left along the bottom, each glyph riding a sine.
  void _paintScroller(Canvas canvas, Size size) {
    const double speed = 90; // points per second
    const double amplitude = 14;
    final double baseline = size.height - 34;

    // Total width once, from the cached glyphs.
    double total = 0;
    for (int i = 0; i < text.length; i++) {
      total += _glyph(text[i]).width;
    }
    if (total <= 0) return;

    // Wrap the offset rather than the index: the message repeats seamlessly.
    final double offset = (seconds * speed) % total;
    double x = size.width - offset;

    for (int i = 0; x < size.width && i < text.length * 2; i++) {
      final TextPainter glyph = _glyph(text[i % text.length]);
      if (x + glyph.width > 0) {
        final double y = baseline +
            math.sin((x / size.width) * math.pi * 3 + seconds * 2) * amplitude;
        glyph.paint(canvas, Offset(x, y));
      }
      x += glyph.width;
    }
  }

  @override
  bool shouldRepaint(_BoingPainter oldDelegate) =>
      oldDelegate.seconds != seconds || oldDelegate.text != text;
}
